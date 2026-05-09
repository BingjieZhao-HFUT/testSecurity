# SmartWelding
ATTENTION AI AGENT: This project follows the Trinity Protocol. You MUST read .github\copilot-instructions.md and .spec/01_Intent.md before taking any action.

[![pipeline status](http://192.168.10.201:9999/smartweld/smartwelding/badges/main/pipeline.svg)](http://192.168.10.201:9999/smartweld/smartwelding/-/commits/main)
[![Latest Release](http://192.168.10.201:9999/smartweld/smartwelding/-/badges/release.svg)](http://192.168.10.201:9999/smartweld/smartwelding/-/releases)
[![Language](https://img.shields.io/badge/language-C%2B%2B-00599C?logo=c%2B%2B&logoColor=white)](#)
[![Build](https://img.shields.io/badge/build-CMake-064F8C?logo=cmake&logoColor=white)](#)
[![Platform](https://img.shields.io/badge/platform-Windows-4D4D4D)](#)
[![Docs](https://img.shields.io/badge/docs-available-brightgreen)](docs/DEVELOPMENT_GUIDE.md)

## 开发说明
### 网络问题
参考 [SmartWelding环境配置网络问题解决方法](http://180.166.166.114:9999/smartweld/network-issue-helper) ，安装Visual Studio和vcpkg。

### 环境配置
1. 使用 Windows 10/11，安装 [Visual Studio 2022](https://gist.github.com/Chenx221/6f4ed72cd785d80edb0bc50c9921daf7)（包含 C++ 开发工具和Windows SDK等必要组件）
2. 安装`python>=3.11`环境（如使用[miniconda3](https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/)），并确保 `python --version` 命令行输出正确。
3. 使用 [vcpkg](https://github.com/Microsoft/vcpkg) 管理第三方库依赖，根据`vcpkg.json`安装依赖项，即在项目根目录运行 (vcpkg需要添加到系统PATH)：
```bash
vcpkg install --triplet x64-windows
```
注：当前仓库内置了 `python3` 的本地 overlay 端口(新增0021.patch)，用于规避 Windows 上 `python3:x64-windows@3.12.9` 在 copied buildtree 中解析 `PCbuild/python.props` 失败的问题。若遇到python3安装失败，可尝试运行带` --overlay-ports=./vcpkg-overlay-ports`的安装命令。
4. 若有Nvidia显卡，使用命令`nvidia-smi`查看驱动版本，随后安装不高于该版本的`nvcc`工具包([CUDA Toolkit](https://developer.nvidia.com/cuda-toolkit-archive))，以启用CUDA相关功能模块。5
5. 使用 Visual Studio 打开项目文件夹，管理CMake配置，可参考以下`CMakeSettings.json`示例进行配置：
 - 因第三方库要求，`configurationType` 不可设置为 `Debug`，建议使用 `RelWithDebInfo` 以兼顾调试信息和编译优化。
 - `scripts/build.ps1` 已改为直接读取仓库根目录的 `CMakeSettings.json`，默认使用 `x64-Release`，并在导入 `Microsoft.VisualStudio.DevShell.dll` 后进入 VS 开发环境再执行 CMake。
 - 日常开发默认使用 `x64-Release`。只有在确实需要刷新依赖时，才使用 `x64-Release-UpdateVcpkg`；不要在普通开发流程里手工改写 `VCPKG_MANIFEST_INSTALL`。
 - GitLab CI 已内置同等优化：会自动检测当前 commit 是否改动 `vcpkg.json`。若未改动，则自动以 `VCPKG_MANIFEST_INSTALL=OFF` 跳过 manifest 刷新；若改动，则自动执行依赖刷新，无需手动调整 CI 参数。
```json
{
  "configurations": [
    {
      "name": "x64-Release",
      "generator": "Ninja",
      "configurationType": "RelWithDebInfo",
      "buildRoot": "${projectDir}\\out\\build\\${name}",
      "installRoot": "${projectDir}\\out\\install\\${name}",
      "buildCommandArgs": "",
      "ctestCommandArgs": "",
      "cmakeToolchain": "\"D:\\vcpkg\\scripts\\buildsystems\\vcpkg.cmake\"",
      "inheritEnvironments": [ "msvc_x64_x64" ],
      "environments": [
        { "PYTHONPATH": "" },
        { "PYTHONHOME": "" }
      ],
      "cmakeCommandArgs": "-DVCPKG_INSTALLED_DIR=${projectDir}\\vcpkg_installed",
      "variables": [
        {
          "name": "VCPKG_MANIFEST_INSTALL",
          "value": "OFF",
          "type": "BOOL"
        },
        {
          "name": "SW_ENABLE_DEV_LICENSE_BYPASS",
          "value": "ON",
          "type": "BOOL"
        }
      ]
    }
  ]
}
```

6. 关键CMake参数项：
   - `SW_ENABLE_DEV_LICENSE_BYPASS`: 开发阶段使用，允许绕过许可证验证，便于快速迭代。**生产环境必须关闭**。
   - `ENABLE_TESTS`: 启用单元测试构建，可以在test目录下运行测试用例验证功能正确性。
   - `ENABLE_CUDA`: 默认关闭，有显卡建议开启。根据是否安装CUDA工具包自动检测，启用相关功能模块。
   - `ENABLE_PYTHON_EMBEDDING`: 无Python环境建议关闭。启用Python嵌入功能，允许在C++代码中直接调用Python脚本，便于快速集成和测试算法。

7. CMake生成后，需要将`third_parties/Lib/bin`添加至系统环境变量后，重启Visual Studio后再进行编译运行。

### 仓库代码规范
1. GitLab使用请阅读[SmartWelding GitLab使用说明](https://greatway.feishu.cn/wiki/FQbowVP0ciOELJkYzJ0cZHBpnby?from=from_copylink)。
2. 使用 [clang-format (LLVM 22.1.1)](https://github.com/llvm/llvm-project/releases/) 进行代码格式化，配置文件位于 `.clang-format`。可一键运行`clang_format.bat`进行格式化。
3. AI Coding依据`.clinerules`所定义的原则，以及`.spec`下的模块规范进行代码生成和修改。

### Harness 护栏工程

Harness 是 SmartWelding 的代码质量守卫系统，在 `git commit` 时自动拦截不合规代码，确保 AI Agent 和人类开发者遵守统一规范。

> **完整开发者指南**：[docs/HARNESS_GUIDE.md](docs/HARNESS_GUIDE.md)（检查规则详解、日常工作流、故障排除、扩展方法）

#### 快速启用
```powershell
# 安装 pre-commit hook（一次性）
pwsh -File scripts/harness/install_hooks.ps1
```
安装后每次 `git commit` 会自动运行以下检查（仅检查暂存文件）：

| 检查 | 规则 | 阻止提交? |
|------|------|-----------|
| **行数硬限** | `.cpp` ≤ 2000 / `.h/.hpp` ≤ 500 | 新文件或行数增长时阻止 |
| **UTF-8 BOM** | 所有源文件禁止 BOM | 阻止 |
| **Mermaid note for** | `.spec/modules/` 下禁止未注释的 `note for` | 阻止 |
| **clang-format** | C++ 文件必须符合 `.clang-format` 格式规范 | 阻止 |

> 存量超标文件（如 MainWindow.h）修改时若行数未增长，会降级为警告而非阻止。

#### 手动全量扫描
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/harness/verify_line_count.ps1 -All
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/harness/verify_utf8.ps1 -All
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/harness/verify_mermaid_sync.ps1 -All
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/harness/verify_clang_format.ps1 -All
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/harness/verify_public_api_boundary.ps1 -All
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/harness/verify_recognition_access.ps1 -All
```
或在 VS Code 中：`Ctrl+Shift+P` → `Tasks: Run Task` → `Harness: 全量检查`

#### 文件结构
```
scripts/harness/
├── pre-commit              # Git hook 入口（shell，必须 LF 行尾）
├── install_hooks.ps1       # 一键安装脚本
├── verify_line_count.ps1   # 行数检查（含 HEAD 对比降级逻辑）
├── verify_utf8.ps1         # BOM 检测
├── verify_mermaid_sync.ps1 # Mermaid 完整性检查
├── verify_clang_format.ps1 # clang-format 格式检查
├── verify_public_api_boundary.ps1 # 公共 API 头边界检查
└── verify_recognition_access.ps1 # 识别访问边界检查（禁止识别模块外直接调用 RecognitionService::instance）
```

#### 被拦截了怎么办？
- **BOM**：`$c = [IO.File]::ReadAllText($file); [IO.File]::WriteAllText($file, $c, [Text.UTF8Encoding]::new($false))`
- **行数超标**：拆分文件，参考 `copilot-instructions.md` 中的 MainWindow 模式
- **Mermaid note for**：将 `note for` 语句用 `%%` 注释
- **clang-format**：在项目根目录运行 `clang_format.bat`

### 创建加密安装包
受保护发布版的CMake配置名称需命名为`x64-Release-VMP`，则对应的安装路径为`out\install\x64-Release-VMP`，运行`cpack_vmp.ps1`脚本生成的安装包位于`out\SmartWelding-0.0.1-win64.exe`。
- 打包：使用CPack-NSIS进行打包，需要安装makensis（[nsis下载网站](https://nsis.sourceforge.io/Download)）
- 加密：使用VMProtect进行加密，需安装VMProtect，项目定义及序列号在`SmartWelding.vmp`中。

## 项目文档

### 核心规范（`.spec/`）

AI Agent 和核心开发相关的意图文档、Mermaid 逻辑图、模块定义：

- 全局意图总纲：[.spec/01_Intent.md](.spec/01_Intent.md)
- 总目录索引：[.spec/00_Table_of_Contents.md](.spec/00_Table_of_Contents.md)

### 开发者指南（`docs/`）

面向人类开发者的环境搭建、工作流和编码规范：

- **三位一体开发者指南**：[docs/DEVELOPMENT_GUIDE.md](docs/DEVELOPMENT_GUIDE.md)（入职必读）
- Harness 护栏详细指南：[docs/HARNESS_GUIDE.md](docs/HARNESS_GUIDE.md)
- 编码规范：[docs/CODING_STANDARDS.md](docs/CODING_STANDARDS.md)
- 项目概览：[docs/SUMMARY.md](docs/SUMMARY.md)
- 项目结构：[docs/PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md)

### 项目管理

- [CHANGELOG.md](CHANGELOG.md)
