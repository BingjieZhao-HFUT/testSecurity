# ============================================================================
# SmartWelding - Industrial Robot OLP System
# Copyright (c) 2025. All rights reserved.
# ============================================================================

cmake_minimum_required(VERSION 3.21)

# MSVC on this workspace emits localized `/showIncludes` lines.
# Set the exact prefix before project()/language enable so CMake's Ninja
# generator can parse and suppress them instead of echoing them to the console.
if(MSVC)
    set(CMAKE_CL_SHOWINCLUDES_PREFIX "注意: 包含文件: ")
    set(CMAKE_C_CL_SHOWINCLUDES_PREFIX "注意: 包含文件: ")
    set(CMAKE_CXX_CL_SHOWINCLUDES_PREFIX "注意: 包含文件: ")
endif()

# CMAKE_CUDA_ARCHITECTURES is set inside if(ENABLE_CUDA) below — not here.
# ============================================================================
# CMake Policy Settings (Suppress warnings)
# ============================================================================
# CMP0167: FindBoost module is removed in CMake 4.0, use BoostConfig.cmake
if(POLICY CMP0167)
    cmake_policy(SET CMP0167 NEW)
endif()

# CMP0144: find_package uses upper-case <PACKAGENAME>_ROOT variables
if(POLICY CMP0144)
    cmake_policy(SET CMP0144 NEW)
endif()

# Suppress VTK cross-compilation warning for MSVC
set(CMAKE_CROSSCOMPILING FALSE CACHE BOOL "Not cross-compiling" FORCE)

# Set PowerShell path for vcpkg (to suppress warning)
if(WIN32)
    set(VCPKG_POWERSHELL_PATH "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe" CACHE FILEPATH "PowerShell executable path")
endif()

# CMAKE_CUDA_HOST_COMPILER is set dynamically inside if(ENABLE_CUDA) after project()
# so that we can use the already-detected CMAKE_CXX_COMPILER path instead of a
# hardcoded machine-specific path that would break on other developers' machines.

# ============================================================================
# Workaround notes for newer MSVC toolchains and CMake feature detection.
# ============================================================================
# if(MSVC AND MSVC_VERSION GREATER_EQUAL 1930)
#     # MSVC 19.30+ (VS 2022+) 鍏ㄩ潰鏀寔 C++20
#     set(CMAKE_CXX_COMPILE_FEATURES cxx_std_20)
#     set(CMAKE_CXX20_STANDARD_COMPILE_OPTION "-std:c++20")
#     set(CMAKE_CXX20_EXTENSION_COMPILE_OPTION "-std:c++20")
#
#     # set(CMAKE_CXX_COMPILER_ID "MSVC" CACHE STRING "" FORCE)
#     # set(CMAKE_CXX_COMPILER_VERSION "${MSVC_VERSION}" CACHE STRING "" FORCE)
#
#     message(STATUS "[SmartWelding] Forcing C++20 support for MSVC ${MSVC_VERSION}")
# endif()

project(SmartWelding
    VERSION 0.0.1
    DESCRIPTION "Industrial Robot Offline Programming System - v0.0.1"
    LANGUAGES CXX C
)

# ============================================================================
# Core Configuration Options
# ============================================================================
option(SW_ENABLE_DEV_LICENSE_BYPASS "Development ONLY: Bypass VMProtect license checks" OFF)
if(SW_ENABLE_DEV_LICENSE_BYPASS)
    message(WARNING "================================================================\n"
                    "  [SECURITY] LICENSE BYPASS IS ENABLED (SW_ENABLE_DEV_LICENSE_BYPASS=ON)\n"
                    "  Do NOT use in CI or production builds! This creates a backdoor.\n"
                    "================================================================")
    add_compile_definitions(SW_DEV_LICENSE_BYPASS)
endif()

# Recognition parser gating: IFC stack is experimental and disabled by default.
option(SMARTWELDING_ENABLE_IFC "Enable IFC parser sources in recognition module" OFF)
if(SMARTWELDING_ENABLE_IFC)
    message(STATUS "[SmartWelding] IFC recognition parser is ENABLED")
else()
    message(STATUS "[SmartWelding] IFC recognition parser is DISABLED (default)")
endif()

# ============================================================================
# Global Python Environment Sanitization
# ============================================================================
# Some external software injects legacy PYTHONPATH/PYTHONHOME values globally,
# which can break Python detection in CMake/Qt/pybind11 (e.g. encodings import
# failures). Clear once here before any find_package() calls.
if(DEFINED ENV{PYTHONPATH} AND NOT "$ENV{PYTHONPATH}" STREQUAL "")
    message(WARNING "[SmartWelding] Clearing inherited PYTHONPATH to stabilize package detection")
    set(ENV{PYTHONPATH} "")
endif()
if(DEFINED ENV{PYTHONHOME} AND NOT "$ENV{PYTHONHOME}" STREQUAL "")
    message(WARNING "[SmartWelding] Clearing inherited PYTHONHOME to stabilize package detection")
    set(ENV{PYTHONHOME} "")
endif()

# ============================================================================
# CUDA Auto-Detection (鍙€夛紝瀹夎 CUDA Toolkit 鍚庤嚜鍔ㄥ惎鐢?
# ============================================================================
# ROOT CAUSE: CLion's post-configure CUDA compiler probing invokes nvcc with
# ALL flags from CMAKE_CXX_FLAGS *and* directory COMPILE_OPTIONS.  MSVC flags
# like /bigobj are misinterpreted by nvcc as file paths (e.g. "D:/bigobj").
#
# STRATEGY: Before ANY CUDA detection, we completely blank out all compiler
# flag variables and directory compile options.  After enable_language(CUDA)
# succeeds, we add MSVC flags back using an INTERFACE library
# (SmartWelding_MSVC_Flags) linked via link_libraries().  This ensures MSVC
# flags propagate to target-level options but NEVER to directory-level
# COMPILE_OPTIONS, so CLion's CUDA compiler probing never sees them.
# ============================================================================
# Default OFF so that machines without CUDA Toolkit configure cleanly without
# errors.  Developers with CUDA hardware should set -DENABLE_CUDA=ON explicitly
# (or via CMakeSettings.json / build.ps1) to enable GPU acceleration.
option(ENABLE_CUDA "Enable NVIDIA CUDA support for GPU acceleration" OFF)
if(ENABLE_CUDA)
    # ---- Pre-detection: set CUDA config variables ----
    # These MUST be set before check_language(CUDA) / enable_language(CUDA).
    # We place them here (after project()) so we can reference CMAKE_CXX_COMPILER
    # instead of a brittle hardcoded path.
    if(NOT DEFINED CMAKE_CUDA_ARCHITECTURES)
        set(CMAKE_CUDA_ARCHITECTURES "86;89;100;120")
    endif()
    if(WIN32 AND MSVC AND NOT DEFINED CMAKE_CUDA_HOST_COMPILER)
        # Use the same cl.exe that CMake already located for the CXX language.
        # This avoids hardcoding a machine-specific MSVC version path.
        set(CMAKE_CUDA_HOST_COMPILER "${CMAKE_CXX_COMPILER}" CACHE FILEPATH "MSVC cl.exe for nvcc")
        message(STATUS "[SmartWelding] CUDA host compiler auto-set: ${CMAKE_CUDA_HOST_COMPILER}")
    endif()

    # ---- STEP 1: Nuclear cleanup of ALL compiler flag variables ----
    # Save original values for logging, then blank them completely.
    # This ensures check_language(CUDA) and enable_language(CUDA) see
    # absolutely no MSVC-specific flags.
    set(_SW_ALL_FLAG_VARS
        CMAKE_CXX_FLAGS CMAKE_C_FLAGS CMAKE_CUDA_FLAGS
        CMAKE_CXX_FLAGS_DEBUG CMAKE_C_FLAGS_DEBUG CMAKE_CUDA_FLAGS_DEBUG
        CMAKE_CXX_FLAGS_RELEASE CMAKE_C_FLAGS_RELEASE CMAKE_CUDA_FLAGS_RELEASE
        CMAKE_CXX_FLAGS_RELWITHDEBINFO CMAKE_C_FLAGS_RELWITHDEBINFO CMAKE_CUDA_FLAGS_RELWITHDEBINFO
        CMAKE_CXX_FLAGS_MINSIZEREL CMAKE_C_FLAGS_MINSIZEREL CMAKE_CUDA_FLAGS_MINSIZEREL
    )

    # List of MSVC flags that MUST NOT appear in any variable that nvcc sees
    set(_SW_MSVC_ONLY_FLAGS "bigobj" "utf-8" "permissive-" "Zc:__cplusplus" "MP" "W3" "EHsc" "openmp")

    foreach(_VAR ${_SW_ALL_FLAG_VARS})
        if(DEFINED ${_VAR})
            set(_VAL "${${_VAR}}")
            foreach(_F ${_SW_MSVC_ONLY_FLAGS})
                string(REPLACE "/${_F}" " " _VAL "${_VAL}")
                string(REPLACE "-${_F}" " " _VAL "${_VAL}")
            endforeach()
            # Collapse whitespace
            string(REGEX REPLACE "[ \t]+" " " _VAL "${_VAL}")
            string(STRIP "${_VAL}" _VAL)
            # Force-write to both cache and local scope
            set(${_VAR} "${_VAL}" CACHE STRING "" FORCE)
            set(${_VAR} "${_VAL}")
        endif()
    endforeach()

    # ---- STEP 2: Clean directory-level COMPILE_OPTIONS ----
    # vcpkg toolchain or previous runs may have injected options here
    get_directory_property(_SW_DIR_OPTS COMPILE_OPTIONS)
    if(_SW_DIR_OPTS)
        set(_SW_CLEAN_OPTS "")
        foreach(_OPT ${_SW_DIR_OPTS})
            set(_KEEP TRUE)
            foreach(_BAD ${_SW_MSVC_ONLY_FLAGS})
                if(_OPT MATCHES "[-/]${_BAD}")
                    set(_KEEP FALSE)
                    break()
                endif()
            endforeach()
            if(_KEEP)
                list(APPEND _SW_CLEAN_OPTS "${_OPT}")
            endif()
        endforeach()
        set_directory_properties(PROPERTIES COMPILE_OPTIONS "${_SW_CLEAN_OPTS}")
    endif()

    message(STATUS "[SmartWelding] Pre-CUDA flag sanitization complete.")
    message(STATUS "  CMAKE_CXX_FLAGS = '${CMAKE_CXX_FLAGS}'")

    # ---- STEP 3: Detect and enable CUDA ----
    include(CheckLanguage)
    check_language(CUDA)
    if(CMAKE_CUDA_COMPILER)
        enable_language(CUDA)
        set(SMARTWELDING_HAS_CUDA TRUE CACHE BOOL "CUDA support detected" FORCE)
        message(STATUS "[SmartWelding] CUDA compiler found: ${CMAKE_CUDA_COMPILER}")
        message(STATUS "[SmartWelding] CUDA architectures: ${CMAKE_CUDA_ARCHITECTURES}")

        set(CMAKE_CUDA_STANDARD 20)
        set(CMAKE_CUDA_STANDARD_REQUIRED ON)

        # Multi-thread compilation for nvcc
        if(NOT CMAKE_CUDA_FLAGS MATCHES "--threads")
            string(APPEND CMAKE_CUDA_FLAGS " --threads 8")
        endif()

        # Forward essential MSVC flags to host compiler via -Xcompiler
        if(MSVC)
            foreach(_FLAG "/utf-8" "/bigobj")
                if(NOT CMAKE_CUDA_FLAGS MATCHES "-Xcompiler=${_FLAG}")
                    string(APPEND CMAKE_CUDA_FLAGS " -Xcompiler=${_FLAG}")
                endif()
            endforeach()
            # Write to cache so the build system sees these flags
            set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS}" CACHE STRING "Flags for CUDA compiler" FORCE)
        endif()

        message(STATUS "[SmartWelding] CMAKE_CUDA_FLAGS = '${CMAKE_CUDA_FLAGS}'")

        # ---- STEP 4: POST-CUDA second scrub ----
        # enable_language(CUDA) may have re-populated CXX/C variables.
        # IMPORTANT: Do NOT scrub CMAKE_CUDA_FLAGS* 鈥?they contain our
        # properly constructed -Xcompiler=/bigobj and -Xcompiler=/utf-8 flags.
        set(_SW_POST_CUDA_SCRUB_VARS
            CMAKE_CXX_FLAGS CMAKE_C_FLAGS
            CMAKE_CXX_FLAGS_DEBUG CMAKE_C_FLAGS_DEBUG
            CMAKE_CXX_FLAGS_RELEASE CMAKE_C_FLAGS_RELEASE
            CMAKE_CXX_FLAGS_RELWITHDEBINFO CMAKE_C_FLAGS_RELWITHDEBINFO
            CMAKE_CXX_FLAGS_MINSIZEREL CMAKE_C_FLAGS_MINSIZEREL
        )
        foreach(_VAR ${_SW_POST_CUDA_SCRUB_VARS})
            if(DEFINED ${_VAR})
                set(_VAL "${${_VAR}}")
                set(_DIRTY FALSE)
                foreach(_F ${_SW_MSVC_ONLY_FLAGS})
                    string(FIND "${_VAL}" "/${_F}" _P1)
                    string(FIND "${_VAL}" "-${_F}" _P2)
                    if(NOT _P1 EQUAL -1 OR NOT _P2 EQUAL -1)
                        string(REPLACE "/${_F}" " " _VAL "${_VAL}")
                        string(REPLACE "-${_F}" " " _VAL "${_VAL}")
                        set(_DIRTY TRUE)
                    endif()
                endforeach()
                if(_DIRTY)
                    string(REGEX REPLACE "[ \t]+" " " _VAL "${_VAL}")
                    string(STRIP "${_VAL}" _VAL)
                    set(${_VAR} "${_VAL}" CACHE STRING "" FORCE)
                    set(${_VAR} "${_VAL}")
                    message(STATUS "[SmartWelding] Post-CUDA scrub cleaned ${_VAR}")
                endif()
            endif()
        endforeach()

        # Also re-scrub directory compile options
        get_directory_property(_SW_DIR_OPTS2 COMPILE_OPTIONS)
        if(_SW_DIR_OPTS2)
            set(_SW_CLEAN2 "")
            foreach(_OPT ${_SW_DIR_OPTS2})
                set(_KEEP TRUE)
                foreach(_BAD ${_SW_MSVC_ONLY_FLAGS})
                    if(_OPT MATCHES "[-/]${_BAD}")
                        set(_KEEP FALSE)
                        break()
                    endif()
                endforeach()
                if(_KEEP)
                    list(APPEND _SW_CLEAN2 "${_OPT}")
                endif()
            endforeach()
            set_directory_properties(PROPERTIES COMPILE_OPTIONS "${_SW_CLEAN2}")
        endif()
    else()
        set(SMARTWELDING_HAS_CUDA FALSE CACHE BOOL "CUDA support detected" FORCE)
        message(STATUS "[SmartWelding] CUDA compiler not found - GPU acceleration DISABLED")
        message(STATUS "[SmartWelding] To enable: install CUDA Toolkit and re-run CMake")
    endif()

else()
    set(SMARTWELDING_HAS_CUDA FALSE CACHE BOOL "CUDA support detected" FORCE)
    message(STATUS "[SmartWelding] CUDA support disabled by ENABLE_CUDA=OFF")
endif()

# ============================================================================
# Post-Project Compiler Configuration (缂栬瘧鍣ㄥ凡妫€娴嬪畬鎴?
# ============================================================================

# 纭繚 MSVC 浣跨敤 UTF-8 缂栫爜
if(MSVC)
    add_definitions(-DUNICODE -D_UNICODE)
    # NOTE: /utf-8 /EHsc are already in CMAKE_CXX_FLAGS (see Compiler Options section below)
    # Do NOT use add_compile_options here 鈥?generator expressions leak to nvcc
endif()
# ============================================================================
# C++ Standard Configuration
# ============================================================================
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Qt6 headers (e.g. QRunnable constexpr defaulted ctor) are more compatible
# with C++23 rules on recent MSVC toolchains.
set(CMAKE_CXX_STANDARD 23)

# Windows-specific: Disable min/max macros from windows.h (conflicts with std::min/max and Pinocchio)
if(WIN32)
    add_definitions(-DNOMINMAX)
    add_definitions(-DWIN32_LEAN_AND_MEAN)
endif()

# Qt AUTOMOC/AUTOUIC/AUTORCC
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTOUIC ON)
set(CMAKE_AUTORCC ON)

# ============================================================================
# Build Configuration
# ============================================================================
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)  # For code analysis tools
set(CMAKE_POSITION_INDEPENDENT_CODE ON)  # For plugin system

# Output directories
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

# Multi-config generators (Visual Studio, Xcode)
foreach(CONFIG ${CMAKE_CONFIGURATION_TYPES})
    string(TOUPPER ${CONFIG} CONFIG_UPPER)
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_${CONFIG_UPPER} ${CMAKE_BINARY_DIR}/bin/${CONFIG})
    set(CMAKE_LIBRARY_OUTPUT_DIRECTORY_${CONFIG_UPPER} ${CMAKE_BINARY_DIR}/lib/${CONFIG})
    set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY_${CONFIG_UPPER} ${CMAKE_BINARY_DIR}/lib/${CONFIG})
endforeach()

# ============================================================================
# vcpkg Integration (Auto-detect)
# ============================================================================
if(DEFINED ENV{VCPKG_ROOT} AND NOT DEFINED CMAKE_TOOLCHAIN_FILE)
    set(CMAKE_TOOLCHAIN_FILE "$ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake"
        CACHE STRING "Vcpkg toolchain file")
    message(STATUS "Using vcpkg toolchain: ${CMAKE_TOOLCHAIN_FILE}")
endif()

# ============================================================================
# Compiler Options (Security & Performance)
# ============================================================================
if(MSVC)
    # -----------------------------------------------------------------------
    # CRITICAL: We MUST NOT use add_compile_options() for MSVC flags when CUDA
    # is enabled!  add_compile_options() writes to the directory-level
    # COMPILE_OPTIONS property.  CLion's CUDA compiler probing reads this
    # property and passes ALL entries (including generator expressions) to nvcc.
    # Generator expressions like $<$<COMPILE_LANGUAGE:C,CXX>:/bigobj> are NOT
    # properly filtered during probing, causing:
    #     nvcc fatal : Don't know what to do with 'D:/bigobj'
    #
    # SOLUTION: Create an INTERFACE library that carries MSVC flags, and link
    # all C/C++ targets to it.  This keeps directory COMPILE_OPTIONS clean
    # while still applying the flags to the correct targets at build time.
    # -----------------------------------------------------------------------

    # Final aggressive scrub: remove any MSVC-only flags that may have been
    # re-injected by find_package() calls or vcpkg toolchain.
    set(_SW_POST_SCRUB_VARS
        CMAKE_CXX_FLAGS CMAKE_C_FLAGS
        CMAKE_CXX_FLAGS_DEBUG CMAKE_CXX_FLAGS_RELEASE

        
        CMAKE_CXX_FLAGS_RELWITHDEBINFO CMAKE_CXX_FLAGS_MINSIZEREL
        CMAKE_C_FLAGS_DEBUG CMAKE_C_FLAGS_RELEASE
        CMAKE_C_FLAGS_RELWITHDEBINFO CMAKE_C_FLAGS_MINSIZEREL
    )
    set(_SW_POST_SCRUB_FLAGS "bigobj" "utf-8" "permissive-" "Zc:__cplusplus" "MP" "W3" "EHsc" "openmp")

    foreach(_SW_VAR ${_SW_POST_SCRUB_VARS})
        if(DEFINED ${_SW_VAR})
            set(_VAL "${${_SW_VAR}}")
            foreach(_F ${_SW_POST_SCRUB_FLAGS})
                string(REPLACE "/${_F}" " " _VAL "${_VAL}")
                string(REPLACE "-${_F}" " " _VAL "${_VAL}")
            endforeach()
            string(REGEX REPLACE "[ \t]+" " " _VAL "${_VAL}")
            string(STRIP "${_VAL}" _VAL)
            set(${_SW_VAR} "${_VAL}" CACHE STRING "" FORCE)
            set(${_SW_VAR} "${_VAL}")
        endif()
    endforeach()

    # Also scrub directory compile options (safety)
    get_directory_property(_SW_CO COMPILE_OPTIONS)
    if(_SW_CO)
        set(_SW_CO_CLEAN "")
        foreach(_OPT ${_SW_CO})
            set(_OK TRUE)
            foreach(_BAD ${_SW_POST_SCRUB_FLAGS})
                if(_OPT MATCHES "[-/]${_BAD}")
                    set(_OK FALSE)
                    break()
                endif()
            endforeach()
            if(_OK)
                list(APPEND _SW_CO_CLEAN "${_OPT}")
            endif()
        endforeach()
        set_directory_properties(PROPERTIES COMPILE_OPTIONS "${_SW_CO_CLEAN}")
    endif()

    # Create an INTERFACE library to carry MSVC compile flags.
    # All C/C++ targets should link to this.  CUDA targets must NOT link to it.
    # INTERFACE_COMPILE_OPTIONS are propagated to consumers but NOT to the
    # directory-level COMPILE_OPTIONS, so CLion CUDA probing won't see them.
    add_library(SmartWelding_MSVC_Flags INTERFACE)
    target_compile_options(SmartWelding_MSVC_Flags INTERFACE
        $<$<COMPILE_LANGUAGE:C,CXX>:/utf-8>
        $<$<COMPILE_LANGUAGE:C,CXX>:/EHsc>
        $<$<COMPILE_LANGUAGE:C,CXX>:/W3>
        $<$<COMPILE_LANGUAGE:C,CXX>:/bigobj>
        $<$<COMPILE_LANGUAGE:C,CXX>:/MP>
        $<$<COMPILE_LANGUAGE:CXX>:/permissive->
        $<$<COMPILE_LANGUAGE:CXX>:/Zc:__cplusplus>
    )
    # Apply MSVC flags to ALL targets created after this point.
    # For pure-CUDA targets the $<COMPILE_LANGUAGE:C,CXX> genexps
    # evaluate to empty 鈥?no MSVC flags leak into nvcc.
    link_libraries(SmartWelding_MSVC_Flags)

    # Release optimizations
    if(NOT CMAKE_CXX_FLAGS_RELEASE MATCHES "/O2")
        string(APPEND CMAKE_CXX_FLAGS_RELEASE " /O2 /Ob2")
    endif()
else()
    add_compile_options(
        -Wall -Wextra -Wpedantic
        -Wno-unused-parameter
        -fstack-protector-strong
        -fPIE
    )
    string(APPEND CMAKE_CXX_FLAGS_RELEASE " -O3 -DNDEBUG")
endif()

# ============================================================================
# Find Required Packages(Corrected for Pinocchio/hpp-fcl)
# ============================================================================

# GLEW must be found BEFORE VTK (VTK depends on it)
# Provide hints for vcpkg-installed GLEW
if(VCPKG_TOOLCHAIN)
    set(GLEW_INCLUDE_DIR "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/include" CACHE PATH "GLEW include directory")
    if(CMAKE_BUILD_TYPE STREQUAL "Debug")
        set(GLEW_LIBRARY "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/debug/lib/glew32d.lib" CACHE FILEPATH "GLEW library")
    else()
        set(GLEW_LIBRARY "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib/glew32.lib" CACHE FILEPATH "GLEW library")
    endif()
endif()
find_package(GLEW REQUIRED)

# VTK must be found EARLY to avoid Freetype target conflicts
# (VTK's internal FindFreetype may conflict with other packages)
# Workaround for VTK dumpbin detection failure on jsoncpp
set(JsonCpp_LIBRARY_TYPE "STATIC" CACHE STRING "JsonCpp library type")

# Workaround: Suppress VTK warning about MSVC unsupported cross-compilation.
# 2. If valid, VTK_FOUND is set. We explicitly skip REQUIRED call to avoid re-triggering the warning.
find_package(VTK QUIET)

if(NOT VTK_FOUND)
    find_package(VTK REQUIRED)  # VTK for 3D visualization
endif()


#set(hpp-fcl_DIR "D:/vcpkg/installed/x64-windows/lib/cmake/hpp-fcl")
#set(pinocchio_DIR "D:/vcpkg/installed/x64-windows/lib/cmake/pinocchio")

# Resolve the prebuilt dependency root and auto-extract archives if it is missing.
set(_SW_PREBUILT_LIB_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/third_parties/Lib")

set(_SW_THIRD_PARTIES_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_parties")
set(_SW_UNZIP_BAT "${_SW_THIRD_PARTIES_DIR}/unzip.bat")
set(_SW_REQUIRED_PREBUILT_DIRS
    "${_SW_PREBUILT_LIB_ROOT}/bin"
    "${_SW_PREBUILT_LIB_ROOT}/lib"
    "${_SW_PREBUILT_LIB_ROOT}/include"
    "${_SW_PREBUILT_LIB_ROOT}/share"
)

set(_SW_NEED_UNZIP FALSE)
foreach(_SW_DIR IN LISTS _SW_REQUIRED_PREBUILT_DIRS)
    if(NOT EXISTS "${_SW_DIR}")
        message(STATUS "[SmartWelding] Missing prebuilt dependency directory: ${_SW_DIR}")
        set(_SW_NEED_UNZIP TRUE)
    endif()
endforeach()

if(_SW_NEED_UNZIP)
    if(WIN32 AND EXISTS "${_SW_UNZIP_BAT}")
        message(STATUS "[SmartWelding] Auto-extracting third-party zip packages via: ${_SW_UNZIP_BAT}")
        execute_process(
            COMMAND cmd /c call "${_SW_UNZIP_BAT}"
            WORKING_DIRECTORY "${_SW_THIRD_PARTIES_DIR}"
            RESULT_VARIABLE _SW_UNZIP_RESULT
            OUTPUT_VARIABLE _SW_UNZIP_OUTPUT
            ERROR_VARIABLE _SW_UNZIP_ERROR
        )
        if(_SW_UNZIP_OUTPUT)
            string(STRIP "${_SW_UNZIP_OUTPUT}" _SW_UNZIP_OUTPUT)
            message(STATUS "[SmartWelding] unzip.bat output:\n${_SW_UNZIP_OUTPUT}")
        endif()
        if(NOT _SW_UNZIP_RESULT EQUAL 0)
            string(STRIP "${_SW_UNZIP_ERROR}" _SW_UNZIP_ERROR)
            message(FATAL_ERROR "[SmartWelding] Failed to run unzip.bat (code=${_SW_UNZIP_RESULT}). ${_SW_UNZIP_ERROR}")
        endif()
    else()
        message(FATAL_ERROR "[SmartWelding] Missing prebuilt dependencies and cannot auto-extract. Expected script: ${_SW_UNZIP_BAT}")
    endif()
endif()

foreach(_SW_DIR IN LISTS _SW_REQUIRED_PREBUILT_DIRS)
    if(NOT EXISTS "${_SW_DIR}")
        message(FATAL_ERROR "[SmartWelding] Required prebuilt dependency directory not found: ${_SW_DIR}")
    endif()
endforeach()

set(CMAKE_FIND_PACKAGE_PREFER_CONFIG ON)

list(PREPEND CMAKE_PREFIX_PATH
    "${_SW_PREBUILT_LIB_ROOT}"
)

# 2. 娣诲姞棰勭紪璇戝簱鐨?find_package 璋冪敤
find_package(hpp-fcl REQUIRED)
find_package(zip CONFIG REQUIRED) # Added back for SmartWelding_SDK
find_package(pinocchio REQUIRED)

# 3. 其余依赖保持不变...
find_package(Qt6 REQUIRED COMPONENTS Core Widgets Gui Concurrent Xml OpenGL OpenGLWidgets Svg Network)
# Qt LinguistTools (可选，用于国际化)
find_package(Qt6 COMPONENTS LinguistTools QUIET)
find_package(Boost REQUIRED COMPONENTS system filesystem log log_setup thread serialization)
find_package(Eigen3 REQUIRED)
find_package(OpenSSL REQUIRED)
find_package(pugixml REQUIRED)
find_package(assimp REQUIRED)
find_package(ZLIB REQUIRED)

find_package(OpenGL REQUIRED)
find_package(urdfdom REQUIRED)     # URDF parsing

# Core domain libraries (now required)
find_package(OpenCASCADE CONFIG REQUIRED)
find_package(ompl CONFIG REQUIRED)

find_package(PCL CONFIG REQUIRED COMPONENTS common io filters features segmentation)
find_package(Bullet CONFIG REQUIRED)  # Bullet3 for physics simulation

# Python Embedding (pybind11)
option(ENABLE_PYTHON_EMBEDDING "Enable embedded Python runtime via pybind11" ON)
if(ENABLE_PYTHON_EMBEDDING)
    # Some industrial software sets global PYTHONPATH/PYTHONHOME and breaks
    # CMake Python probing ("Failed to import encodings"). Clear them here
    # for this configure process only.
    if(DEFINED ENV{PYTHONPATH})
        message(WARNING "[SmartWelding] Clearing PYTHONPATH for reliable CMake Python detection")
        set(ENV{PYTHONPATH} "")
    endif()
    if(DEFINED ENV{PYTHONHOME})
        message(WARNING "[SmartWelding] Clearing PYTHONHOME for reliable CMake Python detection")
        set(ENV{PYTHONHOME} "")
    endif()

    # Force pybind11 to use modern FindPython instead of legacy FindPythonLibsNew.
    set(PYBIND11_FINDPYTHON ON CACHE BOOL "Use CMake FindPython with pybind11" FORCE)

    # PATH-only discovery: do not use hardcoded/custom Python roots.
    # Clear cached values from previous configure runs to avoid stale pinned paths.
    unset(Python3_ROOT_DIR CACHE)
    unset(Python3_EXECUTABLE CACHE)

    # Resolve interpreter strictly from PATH first, but skip vcpkg's bundled
    # python to avoid incompatible headers for embedding.
    set(_SW_PYTHON_SEARCH_DIRS "")
    set(_SW_PATH_DIRS "$ENV{PATH}")
    unset(_SW_PYTHON_FROM_PATH CACHE)
    foreach(_SW_PATH_ENTRY IN LISTS _SW_PATH_DIRS)
        string(TOLOWER "${_SW_PATH_ENTRY}" _SW_PATH_ENTRY_LOWER)
        if(_SW_PATH_ENTRY AND NOT _SW_PATH_ENTRY_LOWER MATCHES "vcpkg")
            list(APPEND _SW_PYTHON_SEARCH_DIRS "${_SW_PATH_ENTRY}")
        endif()
    endforeach()

    # Probe PATH candidates and select one that has embed development files.
    set(_SW_PYTHON_FROM_PATH "")
    foreach(_SW_DIR IN LISTS _SW_PYTHON_SEARCH_DIRS)
        foreach(_SW_NAME python3.14.exe python3.13.exe python3.12.exe python3.11.exe python3.exe python.exe)
            set(_SW_CANDIDATE "${_SW_DIR}/${_SW_NAME}")
            if(EXISTS "${_SW_CANDIDATE}")
                get_filename_component(_SW_PY_ROOT "${_SW_CANDIDATE}" DIRECTORY)
                if(EXISTS "${_SW_PY_ROOT}/include/Python.h")
                    file(GLOB _SW_PY_LIBS "${_SW_PY_ROOT}/libs/python3*.lib")
                    if(_SW_PY_LIBS)
                        set(_SW_PYTHON_FROM_PATH "${_SW_CANDIDATE}")
                        break()
                    endif()
                endif()
            endif()
        endforeach()
        if(_SW_PYTHON_FROM_PATH)
            break()
        endif()
    endforeach()

    if(NOT _SW_PYTHON_FROM_PATH)
        message(FATAL_ERROR "[SmartWelding] No PATH Python with embeddable development files found. Require Python >= 3.11 with include/Python.h and libs/python3*.lib")
    endif()
    set(Python3_EXECUTABLE "${_SW_PYTHON_FROM_PATH}" CACHE FILEPATH "Python from PATH" FORCE)
    message(STATUS "[SmartWelding] Python from PATH: ${Python3_EXECUTABLE}")

    # Require Python >= 3.11 from PATH. On Windows, ignore registry lookup so
    # discovery strictly follows PATH order.
    set(Python3_FIND_STRATEGY LOCATION)
    set(Python3_FIND_UNVERSIONED_NAMES FIRST)
    if(WIN32)
        set(Python3_FIND_REGISTRY NEVER)
    endif()

    if(COMMAND _find_package)
        _find_package(Python3 3.11 REQUIRED COMPONENTS Interpreter Development)
    else()
        find_package(Python3 3.11 REQUIRED COMPONENTS Interpreter Development)
    endif()

    if(Python3_VERSION VERSION_LESS 3.11)
        message(FATAL_ERROR
            "[SmartWelding] Python ${Python3_VERSION} found at ${Python3_EXECUTABLE}, but Python >= 3.11 is required for embedding"
        )
    endif()

    find_package(pybind11 CONFIG REQUIRED)
endif()

# Status report
message(STATUS "=== Core Dependencies ===")
message(STATUS "Qt6:          ${Qt6_VERSION}")
message(STATUS "Boost:        ${Boost_VERSION}")
message(STATUS "Eigen3:       ${EIGEN3_VERSION}")
message(STATUS "OpenSSL:      ${OPENSSL_VERSION}")
message(STATUS "=== Domain Libraries ===")
message(STATUS "OpenCASCADE:  ${OpenCASCADE_LIBRARY_DIR}")
message(STATUS "OMPL:         ${ompl_VERSION}")
message(STATUS "FCL:          ${fcl_VERSION}")
message(STATUS "PCL:          ${PCL_VERSION}")
message(STATUS "VTK:          ${VTK_VERSION}")
message(STATUS "Bullet3:      ${BULLET_VERSION}")
message(STATUS "Pinocchio:      ${pinocchio_VERSION} (Found at: ${pinocchio_DIR})")

# ============================================================================
# Global Include Directories
# ============================================================================
include_directories(
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_SOURCE_DIR}/src
    ${Boost_INCLUDE_DIRS}
    ${EIGEN3_INCLUDE_DIR}
)

# ============================================================================
# Subdirectories (v0.0.1 Architecture: kernel/sdk/modules/gui)
# ============================================================================

add_subdirectory(src/domain)
add_subdirectory(src/core)
add_subdirectory(src/sdk)
# Kernel depends on SDK
add_subdirectory(src/kernel)
# Modules depend on SDK, Core
add_subdirectory(src/modules)
# Infrastructure depends on Core
add_subdirectory(src/infrastructure)
# Adapters depend on Domain + Modules (bridges domain interfaces to infrastructure)
add_subdirectory(src/adapters)

# ============================================================================
# Internationalization (i18n) - Qt Linguist (Optional)
# ============================================================================
# Internationalization (i18n) - Qt Linguist
# ============================================================================
option(ENABLE_I18N "Enable Qt Linguist internationalization support" ON)

if(ENABLE_I18N)
    message(STATUS "i18n: Translations ENABLED")

    # Precompiled translation files live under the source translations folder.
    set(QM_FILES
        ${CMAKE_SOURCE_DIR}/translations/smartwelding_en_US.qm
        ${CMAKE_SOURCE_DIR}/translations/smartwelding_zh_CN.qm
    )

    # Copy translation files into the runtime output directory.
    add_custom_target(translations ALL
        COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/translations"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${QM_FILES} "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/translations/"
        COMMENT "[SmartWelding] Copying translation files to output directory"
        DEPENDS ${QM_FILES}
    )

    # Install translations for packaged/runtime builds.
    # LanguageManager resolves these from <exe-dir>/translations.
    install(FILES ${QM_FILES} DESTINATION bin/translations)

    message(STATUS "i18n: Qt Linguist translations ENABLED (en_US, zh_CN)")
else()
    message(STATUS "i18n: DISABLED (ENABLE_I18N=OFF)")
endif()

# Modules layer (pointcloud) - PCL based
# Delegated to src/modules/CMakeLists.txt

# Media module
# Delegated to src/modules/CMakeLists.txt

# GUI layer (main window + VTK viewport)
add_subdirectory(src/gui)

# Main executable
# On Windows, include the resource file for application icon
if(WIN32 AND EXISTS "${CMAKE_SOURCE_DIR}/ui/sw_logo.ico")
    set(SW_RC_FILE "${CMAKE_SOURCE_DIR}/ui/SmartWelding.rc")
else()
    set(SW_RC_FILE "")
endif()

add_executable(SmartWelding src/main.cpp ${SW_RC_FILE})
target_link_libraries(SmartWelding PRIVATE
    SmartWelding_GUI
    SmartWelding_Kernel
    SmartWelding_Kinematics
    SmartWelding_Infrastructure
    SmartWelding_SDK
    SmartWelding_Geometry
    SmartWelding_Collision
    SmartWelding_Planning
    SmartWelding_PointCloud
    SmartWelding_Communication
    SmartWelding_WeldExtraction
)

if(ENABLE_PYTHON_EMBEDDING)
    target_link_libraries(SmartWelding PRIVATE pybind11::embed Python3::Python)
    target_compile_definitions(SmartWelding PRIVATE SMARTWELDING_ENABLE_PYTHON_EMBEDDING=1)
endif()

if(WIN32)
    set_target_properties(SmartWelding PROPERTIES WIN32_EXECUTABLE TRUE)
    # Link shell32 for SetCurrentProcessExplicitAppUserModelID
    target_link_libraries(SmartWelding PRIVATE shell32)

    # Increase stack size for geometry-heavy imports (default: 256 MB)
    if(MSVC)
        set(SW_STACK_SIZE_MB "256" CACHE STRING "Stack size (MB) for SmartWelding.exe")
        math(EXPR _SW_STACK_BYTES "${SW_STACK_SIZE_MB} * 1024 * 1024")
        target_link_options(SmartWelding PRIVATE "/STACK:${_SW_STACK_BYTES}")
    endif()
endif()

if(WIN32 AND EXISTS "${CMAKE_SOURCE_DIR}/ui/sw_logo.ico")
    install(FILES "${CMAKE_SOURCE_DIR}/ui/sw_logo.ico" DESTINATION bin)
endif()

# Ensure translation files are prepared before building the main executable.
if(TARGET translations)
    add_dependencies(SmartWelding translations)
endif()

# --- Qt runtime deployment for build tree (Windows) ---
# 鐩殑锛氬厑璁哥洿鎺ヨ繍琛?build 杈撳嚭鐩綍涓殑 exe锛坃build/bin/Debug 鎴?Release锛?# 鑰屼笉闇€瑕佹墜鍔ㄨ缃?QT_PLUGIN_PATH / PATH銆?# 鍋氭硶锛?#   1) 鐢熸垚 qt.conf 鎸囧悜鐩稿 plugins 鐩綍
#   2) 鍦?Post-Build 闃舵鎶?vcpkg 鐨?Qt6 plugins 澶嶅埗鍒?<exe-dir>/plugins/...
#      Qt 浼氬湪 <exe-dir>/plugins/platforms 涓嬫壘鍒?qwindows(d).dll
if(WIN32)
    set(_SW_PREBUILT_RUNTIME_BIN "${_SW_PREBUILT_LIB_ROOT}/bin")

    # vcpkg toolchain sets VCPKG_INSTALLED_DIR in cache; fall back to _VCPKG_INSTALLED_DIR.
    set(_SW_VCPKG_INSTALLED_DIR "${VCPKG_INSTALLED_DIR}")
    if(NOT _SW_VCPKG_INSTALLED_DIR)
        set(_SW_VCPKG_INSTALLED_DIR "${_VCPKG_INSTALLED_DIR}")
    endif()

    if(_SW_VCPKG_INSTALLED_DIR)
        set(_SW_QT_PLUGINS_RELEASE "${_SW_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/Qt6/plugins")
        set(_SW_QT_PLUGINS_DEBUG   "${_SW_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/debug/Qt6/plugins")

        # qt.conf: tell Qt to look for plugins under <exe-dir>/plugins
        set(_SW_QTCONF_IN "${CMAKE_CURRENT_BINARY_DIR}/qt.conf.in")
        file(WRITE "${_SW_QTCONF_IN}" "[Paths]\nPlugins=plugins\n")

        add_custom_command(TARGET SmartWelding POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${_SW_QTCONF_IN}"
                "$<TARGET_FILE_DIR:SmartWelding>/qt.conf"
            VERBATIM
        )

        # Copy plugins into <exe-dir>/plugins
        add_custom_command(TARGET SmartWelding POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:SmartWelding>/plugins"

            COMMAND ${CMAKE_COMMAND} -E copy_directory
                "$<$<CONFIG:Debug>:${_SW_QT_PLUGINS_DEBUG}>$<$<NOT:$<CONFIG:Debug>>:${_SW_QT_PLUGINS_RELEASE}>/platforms"
                "$<TARGET_FILE_DIR:SmartWelding>/plugins/platforms"

            COMMAND ${CMAKE_COMMAND} -E copy_directory
                "$<$<CONFIG:Debug>:${_SW_QT_PLUGINS_DEBUG}>$<$<NOT:$<CONFIG:Debug>>:${_SW_QT_PLUGINS_RELEASE}>/imageformats"
                "$<TARGET_FILE_DIR:SmartWelding>/plugins/imageformats"

            COMMAND ${CMAKE_COMMAND} -E copy_directory
                "$<$<CONFIG:Debug>:${_SW_QT_PLUGINS_DEBUG}>$<$<NOT:$<CONFIG:Debug>>:${_SW_QT_PLUGINS_RELEASE}>/styles"
                "$<TARGET_FILE_DIR:SmartWelding>/plugins/styles"

            VERBATIM
        )

        # Also copy Qt runtime DLLs next to the executable (windeployqt-like, minimal).
        # vcpkg layout:
        #   release dlls: <installed>/<triplet>/bin
        #   debug   dlls: <installed>/<triplet>/debug/bin
        set(_SW_QT_BIN_RELEASE "${_SW_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/bin")
        set(_SW_QT_BIN_DEBUG   "${_SW_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/debug/bin")

        # Copy Qt6*.dll and icu*.dll from vcpkg bin directly (stable on MSBuild).
        # Note: this may copy more DLLs than strictly necessary, but avoids env/script issues.
        # cmake -E copy_if_different does NOT support wildcards, so we use a helper -P script.
        set(_SW_DEPLOY_QT_DLLS_SCRIPT "${CMAKE_CURRENT_BINARY_DIR}/_sw_deploy_qt_dlls.cmake")
        file(WRITE "${_SW_DEPLOY_QT_DLLS_SCRIPT}" "\
if(NOT DEFINED SRC_DIR OR NOT DEFINED DST_DIR)\n\
  message(FATAL_ERROR \"SRC_DIR/DST_DIR not set\")\n\
endif()\n\
file(MAKE_DIRECTORY \"${DST_DIR}\")\n\
file(GLOB _qt_dlls \"${SRC_DIR}/Qt6*.dll\" \"${SRC_DIR}/icu*.dll\")\n\
foreach(_f IN LISTS _qt_dlls)\n\
  file(COPY \"${_f}\" DESTINATION \"${DST_DIR}\")\n\
endforeach()\n\
")
        add_custom_command(TARGET SmartWelding POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E echo "[SmartWelding] Deploying Qt runtime DLLs to $<TARGET_FILE_DIR:SmartWelding>"
            COMMAND ${CMAKE_COMMAND} -E make_directory $<TARGET_FILE_DIR:SmartWelding>
            COMMAND ${CMAKE_COMMAND}
                -DSRC_DIR=$<$<CONFIG:Debug>:${_SW_QT_BIN_DEBUG}>$<$<NOT:$<CONFIG:Debug>>:${_SW_QT_BIN_RELEASE}>
                -DDST_DIR=$<TARGET_FILE_DIR:SmartWelding>
                -P ${_SW_DEPLOY_QT_DLLS_SCRIPT}
            VERBATIM
        )

        # ========================================================================
        # 娓呯悊鏃х殑 VTK DLL锛堣В鍐崇増鏈笉鍖归厤闂锛?        # 鍦ㄩ儴缃叉柊 DLL 涔嬪墠锛屽厛鍒犻櫎鐩爣鐩綍涓殑鎵€鏈?vtk*.dll
        # ========================================================================
        set(_SW_CLEAN_VTK_DLLS_SCRIPT "${CMAKE_CURRENT_BINARY_DIR}/_sw_clean_vtk_dlls.cmake")
        file(WRITE "${_SW_CLEAN_VTK_DLLS_SCRIPT}" "\
if(NOT DEFINED DST_DIR)\n\
  message(FATAL_ERROR \"DST_DIR not set\")\n\
endif()\n\
file(GLOB _vtk_dlls \"\${DST_DIR}/vtk*.dll\" \"\${DST_DIR}/VTK*.dll\")\n\
list(LENGTH _vtk_dlls _vtk_count)\n\
if(_vtk_count GREATER 0)\n\
  message(STATUS \"[SmartWelding] Cleaning \${_vtk_count} old VTK DLLs from \${DST_DIR}\")\n\
  foreach(_f IN LISTS _vtk_dlls)\n\
    file(REMOVE \"\${_f}\")\n\
  endforeach()\n\
endif()\n\
")
        add_custom_command(TARGET SmartWelding POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E echo "[SmartWelding] Cleaning old VTK DLLs..."
            COMMAND ${CMAKE_COMMAND}
                -DDST_DIR=$<TARGET_FILE_DIR:SmartWelding>
                -P ${_SW_CLEAN_VTK_DLLS_SCRIPT}
            VERBATIM
        )

        # ========================================================================
        # 閮ㄧ讲鎵€鏈?vcpkg DLL锛堝寘鎷?VTK, Boost, OpenCASCADE 绛夛級
        # 杩欒В鍐充簡 "鎵句笉鍒?xxx.dll" 鐨勯棶棰?        # 娉ㄦ剰锛氭€绘槸鏇存柊 DLL 浠ラ伩鍏嶇増鏈笉鍖归厤闂
        # ========================================================================
        set(_SW_DEPLOY_ALL_DLLS_SCRIPT "${CMAKE_CURRENT_BINARY_DIR}/_sw_deploy_all_dlls.cmake")
                file(WRITE "${_SW_DEPLOY_ALL_DLLS_SCRIPT}" [=[
if(NOT DEFINED SRC_DIR OR NOT DEFINED DST_DIR)
    message(FATAL_ERROR "SRC_DIR/DST_DIR not set")
endif()

file(MAKE_DIRECTORY "${DST_DIR}")
file(GLOB _all_dlls "${SRC_DIR}/*.dll")
list(LENGTH _all_dlls _dll_count)
message(STATUS "[SmartWelding] Copying ${_dll_count} DLLs from ${SRC_DIR}")

foreach(_f IN LISTS _all_dlls)
    get_filename_component(_fname "${_f}" NAME)
    set(_dst "${DST_DIR}/${_fname}")

    # Update existing DLLs only when the source timestamp is newer.
    if(EXISTS "${_dst}")
        file(TIMESTAMP "${_f}" _src_time)
        file(TIMESTAMP "${_dst}" _dst_time)
        if(_src_time STRGREATER _dst_time)
            file(COPY "${_f}" DESTINATION "${DST_DIR}")
            message(STATUS "  Updated: ${_fname}")
        endif()
    else()
        file(COPY "${_f}" DESTINATION "${DST_DIR}")
        message(STATUS "  Copied: ${_fname}")
    endif()
endforeach()
]=])
        add_custom_command(TARGET SmartWelding POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E echo "[SmartWelding] Deploying ALL vcpkg DLLs to $<TARGET_FILE_DIR:SmartWelding>"
            COMMAND ${CMAKE_COMMAND}
                -DSRC_DIR=$<$<CONFIG:Debug>:${_SW_QT_BIN_DEBUG}>$<$<NOT:$<CONFIG:Debug>>:${_SW_QT_BIN_RELEASE}>
                -DDST_DIR=$<TARGET_FILE_DIR:SmartWelding>
                -P ${_SW_DEPLOY_ALL_DLLS_SCRIPT}
            VERBATIM
        )
        
        # ========================================================================
        # 鐢熸垚鍚姩鑴氭湰 - 瑙ｅ喅 PATH 涓棫鐗?VTK DLL 鍐茬獊闂
        # ========================================================================
        set(_SW_GENERATE_LAUNCHER_SCRIPT "${CMAKE_BINARY_DIR}/_sw_generate_launcher.cmake")
        file(WRITE ${_SW_GENERATE_LAUNCHER_SCRIPT} [=[
# SmartWelding Launcher Script Generator
if(NOT DEFINED DST_DIR)
    message(FATAL_ERROR "DST_DIR not defined")
endif()

set(LAUNCHER_CONTENT "@echo off
REM SmartWelding Launcher - Resolves VTK DLL version conflicts
REM This script ensures local DLLs are prioritized over system PATH
cd /d \"%~dp0\"
set PATH=%~dp0;%PATH%
start \"\" \"%~dp0SmartWelding.exe\" %*
")

file(WRITE "${DST_DIR}/SmartWelding.bat" "${LAUNCHER_CONTENT}")
message(STATUS "Generated launcher script: ${DST_DIR}/SmartWelding.bat")
]=])
        add_custom_command(TARGET SmartWelding POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E echo "[SmartWelding] Generating launcher script"
            COMMAND ${CMAKE_COMMAND}
                -DDST_DIR=$<TARGET_FILE_DIR:SmartWelding>
                -P ${_SW_GENERATE_LAUNCHER_SCRIPT}
            VERBATIM
        )

        # ========================================================================
        # Deploy embedded Python runtime for build tree (Windows)
        # Ensure <exe-dir>/python3xx.dll and <exe-dir>/Lib/encodings exist so
        # embedded interpreter can bootstrap without relying on system Python.
        # ========================================================================
        if(ENABLE_PYTHON_EMBEDDING)
            get_filename_component(_SW_PYTHON_BIN_DIR "${Python3_EXECUTABLE}" DIRECTORY)
            set(_SW_PYTHON_RUNTIME_DLL_CANDIDATES
                "${_SW_PYTHON_BIN_DIR}/python${Python3_VERSION_MAJOR}${Python3_VERSION_MINOR}.dll"
                "${_SW_PYTHON_BIN_DIR}/python3.dll"
            )

            set(_SW_PYTHON_RUNTIME_DLL "")
            foreach(_SW_PY_DLL IN LISTS _SW_PYTHON_RUNTIME_DLL_CANDIDATES)
                if(EXISTS "${_SW_PY_DLL}")
                    set(_SW_PYTHON_RUNTIME_DLL "${_SW_PY_DLL}")
                    break()
                endif()
            endforeach()

            if(_SW_PYTHON_RUNTIME_DLL)
                add_custom_command(TARGET SmartWelding POST_BUILD
                    COMMAND ${CMAKE_COMMAND} -E echo "[SmartWelding] Deploying embedded Python runtime DLL"
                    COMMAND ${CMAKE_COMMAND} -E copy_if_different
                        "${_SW_PYTHON_RUNTIME_DLL}"
                        "$<TARGET_FILE_DIR:SmartWelding>/"
                    VERBATIM
                )
            else()
                message(WARNING "[SmartWelding] Build-tree deploy: Python runtime DLL not found near ${Python3_EXECUTABLE}")
            endif()

            set(_SW_PYTHON_STDLIB_DIR "${Python3_STDLIB}")
            if(NOT _SW_PYTHON_STDLIB_DIR)
                execute_process(
                    COMMAND "${Python3_EXECUTABLE}" -c "import sysconfig; print(sysconfig.get_path('stdlib'))"
                    OUTPUT_VARIABLE _SW_PYTHON_STDLIB_DIR
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                    ERROR_QUIET
                )
            endif()

            if(_SW_PYTHON_STDLIB_DIR)
                file(TO_CMAKE_PATH "${_SW_PYTHON_STDLIB_DIR}" _SW_PYTHON_STDLIB_DIR)
            endif()

            if(_SW_PYTHON_STDLIB_DIR AND EXISTS "${_SW_PYTHON_STDLIB_DIR}/encodings")
                set(_SW_DEPLOY_PY_STDLIB_SCRIPT "${CMAKE_CURRENT_BINARY_DIR}/_sw_deploy_python_stdlib.cmake")
                file(WRITE "${_SW_DEPLOY_PY_STDLIB_SCRIPT}" [=[
if(NOT DEFINED SRC_LIB_DIR OR NOT DEFINED DST_LIB_DIR)
    message(FATAL_ERROR "SRC_LIB_DIR/DST_LIB_DIR not set")
endif()

if(EXISTS "${DST_LIB_DIR}/encodings/__init__.py")
    message(STATUS "[SmartWelding] Python stdlib already present in build tree: ${DST_LIB_DIR}")
    return()
endif()

file(MAKE_DIRECTORY "${DST_LIB_DIR}")

file(COPY "${SRC_LIB_DIR}/" DESTINATION "${DST_LIB_DIR}"
    PATTERN "__pycache__" EXCLUDE
    PATTERN "site-packages" EXCLUDE
    PATTERN "site-packages/*" EXCLUDE
    PATTERN "test" EXCLUDE
    PATTERN "test/*" EXCLUDE
    PATTERN "tests" EXCLUDE
    PATTERN "tests/*" EXCLUDE
    PATTERN "tkinter" EXCLUDE
    PATTERN "tkinter/*" EXCLUDE
    PATTERN "turtledemo" EXCLUDE
    PATTERN "turtledemo/*" EXCLUDE
    PATTERN "idlelib" EXCLUDE
    PATTERN "idlelib/*" EXCLUDE
    PATTERN "ensurepip" EXCLUDE
    PATTERN "ensurepip/*" EXCLUDE
    PATTERN "venv" EXCLUDE
    PATTERN "venv/*" EXCLUDE
    PATTERN "distutils" EXCLUDE
    PATTERN "distutils/*" EXCLUDE
)

if(NOT EXISTS "${DST_LIB_DIR}/encodings/__init__.py")
    message(FATAL_ERROR "[SmartWelding] Build-tree Python stdlib deploy failed: encodings missing in ${DST_LIB_DIR}")
endif()

message(STATUS "[SmartWelding] Deployed minimal Python stdlib to ${DST_LIB_DIR}")
]=])

                add_custom_command(TARGET SmartWelding POST_BUILD
                    COMMAND ${CMAKE_COMMAND} -E echo "[SmartWelding] Deploying embedded Python stdlib to build tree"
                    COMMAND ${CMAKE_COMMAND}
                        -DSRC_LIB_DIR=${_SW_PYTHON_STDLIB_DIR}
                        -DDST_LIB_DIR=$<TARGET_FILE_DIR:SmartWelding>/Lib
                        -P ${_SW_DEPLOY_PY_STDLIB_SCRIPT}
                    VERBATIM
                )
            else()
                message(WARNING "[SmartWelding] Build-tree deploy: Python stdlib not found (missing encodings) near ${Python3_EXECUTABLE}")
            endif()
        endif()
        
    else()
        message(WARNING "VCPKG_INSTALLED_DIR is not set; build-tree Qt plugin deployment is disabled.")
    endif()
endif()

# Copy config directory to build output
add_custom_command(TARGET SmartWelding POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:SmartWelding>/config"
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${CMAKE_SOURCE_DIR}/config"
        "$<TARGET_FILE_DIR:SmartWelding>/config"
    VERBATIM
)

# OLD v1.0 subdirectories (commented out for migration)
# add_subdirectory(src/Core)           # Foundation layer
# add_subdirectory(src/Infrastructure) # Logging, crash reporting
# add_subdirectory(src/Geometry)       # OCC wrapper
# add_subdirectory(src/Kinematics)     # Pinocchio/FCL integration
# add_subdirectory(src/Planning)       # OMPL algorithms
# add_subdirectory(src/PointCloud)     # PCL processing
# add_subdirectory(src/Plugins)        # Plugin interfaces
# add_subdirectory(src/Application)    # Main executable

option(ENABLE_TESTS "Enable unit tests" ON)
if(ENABLE_TESTS)
    # enable_testing() must be called at top-level so ctest in the build root
    # can discover tests added from subdirectories.
    enable_testing()
    add_subdirectory(tests)              # Unit tests
endif()

# ============================================================================
# Installation Rules
# ============================================================================
option(SMARTWELDING_INSTALL_DEV_ARTIFACTS
    "Install development artifacts (include/ and lib/) for SDK usage"
    OFF
)
option(SMARTWELDING_INSTALL_DEBUG_RUNTIME
    "Install debug runtime dependencies into bin/debug"
    OFF
)

option(SMARTWELDING_INSTALL_PYTHON_SITE_PACKAGES
    "Install Python Lib/site-packages for embedded runtime (can be very large)"
    OFF
)

option(SMARTWELDING_BUNDLE_SYSTEM_RUNTIME
    "Bundle MSVC/UCRT/OpenMP runtime libraries into installer on Windows"
    ON
)

if(WIN32 AND SMARTWELDING_BUNDLE_SYSTEM_RUNTIME)
    set(CMAKE_INSTALL_SYSTEM_RUNTIME_DESTINATION bin)
    set(CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS_SKIP FALSE)
    set(CMAKE_INSTALL_UCRT_LIBRARIES TRUE)
    set(CMAKE_INSTALL_OPENMP_LIBRARIES TRUE)
    include(InstallRequiredSystemLibraries)

    if(CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS)
        install(PROGRAMS ${CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS} DESTINATION bin)
        list(LENGTH CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS _SW_SYSRT_COUNT)
        message(STATUS "[SmartWelding] Bundling ${_SW_SYSRT_COUNT} Windows system runtime libraries into installer")
    else()
        message(WARNING "[SmartWelding] No Windows system runtime libraries were detected for bundling")
    endif()
endif()

# Install targets (preferred over copying the whole build tree).
# This keeps the install layout stable: <prefix>/bin/SmartWelding.exe
install(TARGETS SmartWelding
    RUNTIME DESTINATION bin
)

# Python embedding runtime DLL must be shipped with installer on target machines.
if(WIN32 AND ENABLE_PYTHON_EMBEDDING)
    get_filename_component(_SW_PYTHON_BIN_DIR "${Python3_EXECUTABLE}" DIRECTORY)
    set(_SW_PYTHON_RUNTIME_DLL_CANDIDATES
        "${_SW_PYTHON_BIN_DIR}/python${Python3_VERSION_MAJOR}${Python3_VERSION_MINOR}.dll"
        "${_SW_PYTHON_BIN_DIR}/python3.dll"
    )

    set(_SW_PYTHON_RUNTIME_DLL "")
    foreach(_SW_PY_DLL IN LISTS _SW_PYTHON_RUNTIME_DLL_CANDIDATES)
        if(EXISTS "${_SW_PY_DLL}")
            set(_SW_PYTHON_RUNTIME_DLL "${_SW_PY_DLL}")
            break()
        endif()
    endforeach()

    if(_SW_PYTHON_RUNTIME_DLL)
        install(FILES "${_SW_PYTHON_RUNTIME_DLL}" DESTINATION bin)
        message(STATUS "[SmartWelding] Bundling Python runtime DLL: ${_SW_PYTHON_RUNTIME_DLL}")
    else()
        message(WARNING "[SmartWelding] Python embedding enabled but runtime DLL not found near ${Python3_EXECUTABLE}; target machine may fail with missing python3xx.dll")
    endif()

    # Python standard library is required for interpreter startup
    # (at minimum, Lib/encodings must be present).
    set(_SW_PYTHON_STDLIB_DIR "${Python3_STDLIB}")
    if(NOT _SW_PYTHON_STDLIB_DIR)
        execute_process(
            COMMAND "${Python3_EXECUTABLE}" -c "import sysconfig; print(sysconfig.get_path('stdlib'))"
            OUTPUT_VARIABLE _SW_PYTHON_STDLIB_DIR
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )
    endif()

    if(_SW_PYTHON_STDLIB_DIR)
        file(TO_CMAKE_PATH "${_SW_PYTHON_STDLIB_DIR}" _SW_PYTHON_STDLIB_DIR)
    endif()

    if(_SW_PYTHON_STDLIB_DIR AND EXISTS "${_SW_PYTHON_STDLIB_DIR}/encodings")
        if(SMARTWELDING_INSTALL_PYTHON_SITE_PACKAGES)
            install(
                DIRECTORY "${_SW_PYTHON_STDLIB_DIR}/"
                DESTINATION bin/Lib
                PATTERN "__pycache__" EXCLUDE
            )
            message(STATUS "[SmartWelding] Bundling FULL Python stdlib (including site-packages) from: ${_SW_PYTHON_STDLIB_DIR}")
        else()
            install(
                DIRECTORY "${_SW_PYTHON_STDLIB_DIR}/"
                DESTINATION bin/Lib
                PATTERN "__pycache__" EXCLUDE
                PATTERN "site-packages" EXCLUDE
                PATTERN "site-packages/*" EXCLUDE
                PATTERN "test" EXCLUDE
                PATTERN "test/*" EXCLUDE
                PATTERN "tests" EXCLUDE
                PATTERN "tests/*" EXCLUDE
                PATTERN "tkinter" EXCLUDE
                PATTERN "tkinter/*" EXCLUDE
                PATTERN "turtledemo" EXCLUDE
                PATTERN "turtledemo/*" EXCLUDE
                PATTERN "idlelib" EXCLUDE
                PATTERN "idlelib/*" EXCLUDE
                PATTERN "ensurepip" EXCLUDE
                PATTERN "ensurepip/*" EXCLUDE
                PATTERN "venv" EXCLUDE
                PATTERN "venv/*" EXCLUDE
                PATTERN "distutils" EXCLUDE
                PATTERN "distutils/*" EXCLUDE
            )
            message(STATUS "[SmartWelding] Bundling MINIMAL Python stdlib from: ${_SW_PYTHON_STDLIB_DIR} (site-packages excluded)")
        endif()
    else()
        message(WARNING "[SmartWelding] Python stdlib not found (missing encodings). Embedded Python may abort at startup on target machines.")
    endif()
endif()

if(SMARTWELDING_INSTALL_DEV_ARTIFACTS)
    install(DIRECTORY include/ DESTINATION include)
    install(DIRECTORY ${CMAKE_BINARY_DIR}/lib/ DESTINATION lib)
    message(STATUS "[SmartWelding] Install mode: app + development artifacts (bin/include/lib)")
else()
    message(STATUS "[SmartWelding] Install mode: runtime-only (bin)")
endif()

# NOTE: Avoid copying ${CMAKE_BINARY_DIR}/bin entirely because for multi-config
# generators it contains bin/Debug, bin/Release, etc. which breaks Qt plugin lookup.

# --- Qt runtime deployment (Windows) ---
# Install Qt plugins next to the executable under <prefix>/bin.
# Qt expects <exe-dir>/platforms/qwindows.dll (and other plugin folders).
if(WIN32)
    set(_SW_PREBUILT_RUNTIME_BIN "${_SW_PREBUILT_LIB_ROOT}/bin")

    # vcpkg toolchain sets VCPKG_INSTALLED_DIR in cache; fall back to _VCPKG_INSTALLED_DIR.
    set(_SW_VCPKG_INSTALLED_DIR "${VCPKG_INSTALLED_DIR}")
    if(NOT _SW_VCPKG_INSTALLED_DIR)
        set(_SW_VCPKG_INSTALLED_DIR "${_VCPKG_INSTALLED_DIR}")
    endif()

    if(_SW_VCPKG_INSTALLED_DIR)
        set(_SW_QT_PLUGINS_RELEASE "${_SW_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/Qt6/plugins")
        set(_SW_QT_PLUGINS_DEBUG   "${_SW_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/debug/Qt6/plugins")
        set(_SW_RUNTIME_BIN_RELEASE "${_SW_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/bin")
        set(_SW_RUNTIME_BIN_DEBUG   "${_SW_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/debug/bin")

        if(EXISTS "${_SW_QT_PLUGINS_RELEASE}/platforms")
            install(DIRECTORY "${_SW_QT_PLUGINS_RELEASE}/platforms" DESTINATION bin)
        endif()
        if(EXISTS "${_SW_QT_PLUGINS_RELEASE}/imageformats")
            install(DIRECTORY "${_SW_QT_PLUGINS_RELEASE}/imageformats" DESTINATION bin)
        endif()
        if(EXISTS "${_SW_QT_PLUGINS_RELEASE}/styles")
            install(DIRECTORY "${_SW_QT_PLUGINS_RELEASE}/styles" DESTINATION bin)
        endif()

        # Optional: install debug plugins into a separate folder for development installs.
        if(SMARTWELDING_INSTALL_DEBUG_RUNTIME)
            if(EXISTS "${_SW_QT_PLUGINS_DEBUG}/platforms")
                install(DIRECTORY "${_SW_QT_PLUGINS_DEBUG}/platforms" DESTINATION bin/debug)
            endif()
            if(EXISTS "${_SW_QT_PLUGINS_DEBUG}/imageformats")
                install(DIRECTORY "${_SW_QT_PLUGINS_DEBUG}/imageformats" DESTINATION bin/debug)
            endif()
            if(EXISTS "${_SW_QT_PLUGINS_DEBUG}/styles")
                install(DIRECTORY "${_SW_QT_PLUGINS_DEBUG}/styles" DESTINATION bin/debug)
            endif()
        endif()

        # Install all runtime DLLs from vcpkg to avoid missing dependency errors
        # (e.g. vtkIOGeometry-9.3.dll, vtkGUISupport-9.3.dll,
        #  vtkInteractionWidgets-9.3.dll, Qt6OpenGLWidgets.dll).
        if(EXISTS "${_SW_RUNTIME_BIN_RELEASE}")
            install(
                DIRECTORY "${_SW_RUNTIME_BIN_RELEASE}/"
                DESTINATION bin
                FILES_MATCHING
                PATTERN "*.dll"
            )
        endif()

        # Optional debug runtime DLLs for development installs.
        if(SMARTWELDING_INSTALL_DEBUG_RUNTIME AND EXISTS "${_SW_RUNTIME_BIN_DEBUG}")
            install(
                DIRECTORY "${_SW_RUNTIME_BIN_DEBUG}/"
                DESTINATION bin/debug
                FILES_MATCHING
                PATTERN "*.dll"
            )
        endif()
    else()
        message(WARNING "VCPKG_INSTALLED_DIR is not set; Qt runtime plugins will not be installed.")
    endif()

    # Install prebuilt runtime DLLs shipped under third_parties/Lib/bin.
    # These binaries include non-vcpkg dependencies required on clean target machines.
    if(EXISTS "${_SW_PREBUILT_RUNTIME_BIN}")
        install(
            DIRECTORY "${_SW_PREBUILT_RUNTIME_BIN}/"
            DESTINATION bin
            FILES_MATCHING
            PATTERN "*.dll"
        )
    else()
        message(WARNING "[SmartWelding] Prebuilt runtime bin directory not found: ${_SW_PREBUILT_RUNTIME_BIN}")
    endif()

    # Compatibility alias for legacy dependency chains expecting zlib.dll.
    set(_SW_ZLIB_RUNTIME_CANDIDATES
        "${_SW_RUNTIME_BIN_RELEASE}/zlib1.dll"
        "${_SW_PREBUILT_RUNTIME_BIN}/zlib1.dll"
    )
    set(_SW_ZLIB_RUNTIME_SOURCE "")
    foreach(_SW_ZLIB_CANDIDATE IN LISTS _SW_ZLIB_RUNTIME_CANDIDATES)
        if(EXISTS "${_SW_ZLIB_CANDIDATE}")
            set(_SW_ZLIB_RUNTIME_SOURCE "${_SW_ZLIB_CANDIDATE}")
            break()
        endif()
    endforeach()
    if(_SW_ZLIB_RUNTIME_SOURCE)
        install(FILES "${_SW_ZLIB_RUNTIME_SOURCE}" DESTINATION bin RENAME zlib.dll)
    else()
        message(WARNING "[SmartWelding] zlib1.dll not found in runtime sources; zlib.dll compatibility alias will be missing")
    endif()
endif()

# ============================================================================
# CPack Configuration (Packaging)
# ============================================================================
set(CPACK_PACKAGE_NAME "SmartWelding")
set(CPACK_PACKAGE_VENDOR "Greatway")
set(CPACK_PACKAGE_VERSION "${CMAKE_PROJECT_VERSION}")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "${CMAKE_PROJECT_DESCRIPTION}")
set(CPACK_PACKAGE_CONTACT "Greatway Support")
if(DEFINED PROJECT_HOMEPAGE_URL AND NOT "${PROJECT_HOMEPAGE_URL}" STREQUAL "")
    set(CPACK_PACKAGE_HOMEPAGE_URL "${PROJECT_HOMEPAGE_URL}")
endif()
set(CPACK_PACKAGE_INSTALL_DIRECTORY "SmartWelding")
set(CPACK_PACKAGE_INSTALL_REGISTRY_KEY "SmartWelding")
set(CPACK_PACKAGE_FILE_NAME "${CPACK_PACKAGE_NAME}-${CPACK_PACKAGE_VERSION}-win64")
set(CPACK_GENERATOR "NSIS")
set(CPACK_SOURCE_GENERATOR "")
set(CPACK_NSIS_DISPLAY_NAME "SmartWelding")
set(CPACK_NSIS_PACKAGE_NAME "SmartWelding")
set(CPACK_NSIS_EXECUTABLES_DIRECTORY "bin")
set(CPACK_PACKAGE_EXECUTABLES "SmartWelding" "SmartWelding")
set(CPACK_NSIS_INSTALLED_ICON_NAME "bin/SmartWelding.exe")
set(CPACK_NSIS_MUI_FINISHPAGE_RUN "SmartWelding.exe")
set(CPACK_NSIS_MUI_FINISHPAGE_RUN_TEXT "瀹夎瀹屾垚鍚庤繍琛?SmartWelding")
set(CPACK_NSIS_MUI_ABORTWARNING ON)
if(EXISTS "${CMAKE_SOURCE_DIR}/ui/sw_logo.ico")
    file(TO_CMAKE_PATH "${CMAKE_SOURCE_DIR}/ui/sw_logo.ico" _SW_NSIS_ICON)
    set(CPACK_NSIS_MUI_ICON "${_SW_NSIS_ICON}")
    set(CPACK_NSIS_MUI_UNIICON "${_SW_NSIS_ICON}")
endif()
set(CPACK_NSIS_CONTACT "${CPACK_PACKAGE_CONTACT}")
set(CPACK_NSIS_URL_INFO_ABOUT "${CPACK_PACKAGE_HOMEPAGE_URL}")

# Optional fancy UI bits (only if assets exist)
set(_SW_NSIS_WELCOME_BMP "${CMAKE_SOURCE_DIR}/ui/nsis_welcome.bmp")
set(_SW_NSIS_HEADER_BMP "${CMAKE_SOURCE_DIR}/ui/nsis_header.bmp")
if(EXISTS "${_SW_NSIS_WELCOME_BMP}")
    file(TO_CMAKE_PATH "${_SW_NSIS_WELCOME_BMP}" _SW_NSIS_WELCOME_BMP_PATH)
    set(CPACK_NSIS_MUI_WELCOMEFINISHPAGE_BITMAP "${_SW_NSIS_WELCOME_BMP_PATH}")
    set(CPACK_NSIS_MUI_UNWELCOMEFINISHPAGE_BITMAP "${_SW_NSIS_WELCOME_BMP_PATH}")
endif()
if(EXISTS "${_SW_NSIS_HEADER_BMP}")
    file(TO_CMAKE_PATH "${_SW_NSIS_HEADER_BMP}" _SW_NSIS_HEADER_BMP_PATH)
    set(CPACK_NSIS_MUI_HEADERIMAGE ON)
    set(CPACK_NSIS_MUI_HEADERIMAGE_RIGHT ON)
    set(CPACK_NSIS_MUI_HEADERIMAGE_BITMAP "${_SW_NSIS_HEADER_BMP_PATH}")
endif()
if(DEFINED CPACK_PACKAGE_HOMEPAGE_URL AND NOT "${CPACK_PACKAGE_HOMEPAGE_URL}" STREQUAL "")
    set(CPACK_NSIS_MUI_FINISHPAGE_LINK "璁块棶瀹樼綉")
    set(CPACK_NSIS_MUI_FINISHPAGE_LINK_LOCATION "${CPACK_PACKAGE_HOMEPAGE_URL}")
endif()

# Keep ARP metadata on CPack native variables to avoid fragile string escaping
# in CPACK_NSIS_EXTRA_*_COMMANDS that can break generated CPackConfig.cmake.
set(CPACK_NSIS_ENABLE_UNINSTALL_BEFORE_INSTALL ON)
include(CPack)

# ============================================================================
# 鏈€缁堝畨鍏ㄧ綉锛氭繁搴︽竻鐞嗘墍鏈夊彲鑳芥畫鐣?MSVC 鏍囧織鐨勫彉閲?# ============================================================================
if(MSVC AND SMARTWELDING_HAS_CUDA)
    # 瀹氫箟闇€瑕佹竻鐞嗙殑鎵€鏈夋爣蹇?    set(_SW_BAD_FLAGS "bigobj" "utf-8" "permissive-" "Zc:__cplusplus" "MP" "W3" "EHsc")

    # 瀹氫箟闇€瑕佹壂鎻忕殑鎵€鏈夊彉閲忥紙鍖呮嫭鎵€鏈夐厤缃彉浣擄級
    set(_SW_VARS_TO_SCRUB
        CMAKE_CXX_FLAGS CMAKE_C_FLAGS
        CMAKE_CXX_FLAGS_DEBUG CMAKE_C_FLAGS_DEBUG
        CMAKE_CXX_FLAGS_RELEASE CMAKE_C_FLAGS_RELEASE
        CMAKE_CXX_FLAGS_RELWITHDEBINFO CMAKE_C_FLAGS_RELWITHDEBINFO
        CMAKE_CXX_FLAGS_MINSIZEREL CMAKE_C_FLAGS_MINSIZEREL
    )

    foreach(_VAR ${_SW_VARS_TO_SCRUB})
        if(DEFINED ${_VAR})
            set(_VAL "${${_VAR}}")
            set(_CHANGED FALSE)

            foreach(_F ${_SW_BAD_FLAGS})
                # 鏄惧紡妫€鏌?/flag 鍜?-flag 涓ょ褰㈠紡
                string(FIND "${_VAL}" "/${_F}" _POS_SLASH)
                string(FIND "${_VAL}" "-${_F}" _POS_DASH)

                if(NOT _POS_SLASH EQUAL -1 OR NOT _POS_DASH EQUAL -1)
                    string(REPLACE "/${_F}" " " _VAL "${_VAL}")
                    string(REPLACE "-${_F}" " " _VAL "${_VAL}")
                    set(_CHANGED TRUE)
                endif()
            endforeach()

            if(_CHANGED)
                # 娓呯悊澶氫綑绌烘牸骞跺悓姝ュ洖缂撳瓨锛團ORCE 寮哄埗瑕嗙洊锛?                string(REGEX REPLACE "[ \t]+" " " _VAL "${_VAL}")
                string(STRIP "${_VAL}" _VAL)
                set(${_VAR} "${_VAL}" CACHE STRING "" FORCE)
                message(STATUS "[SmartWelding] Final scrub cleaned ${_VAR}: '${_VAL}'")
            endif()
        endif()
    endforeach()
endif()
