# =============================================================================
# test_git_read.ps1
# 测试目标：验证 git 在文件加密场景下，能否正常完成版本管理核心功能
#   1. git cat-file  — git 对象库中存储的内容（密文 or 明文？）
#   2. git diff      — 两版本之间差异（是否有意义？）
#   3. git log -p    — 历史补丁（是否可读？）
#   4. git show      — 指定提交的文件内容
#   5. git blame     — 行级别追溯
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Header($msg) {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "  $msg" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
}

function Write-Result($label, $ok, $detail = "") {
    $icon  = if ($ok) { "[PASS]" } else { "[FAIL]" }
    $color = if ($ok) { "Green"  } else { "Red"    }
    Write-Host "$icon $label" -ForegroundColor $color
    if ($detail) { Write-Host "       $detail" -ForegroundColor Gray }
}

# ---------------------------------------------------------------------------
# 0. 基本信息
# ---------------------------------------------------------------------------
Write-Header "0. 仓库基本信息"
$branch = git branch --show-current
$head   = git rev-parse --short HEAD
Write-Host "当前分支  : $branch"
Write-Host "HEAD 提交 : $head"
Write-Host "所有提交  :"
git log --oneline

# ---------------------------------------------------------------------------
# 1. 检查 git 对象库中存储的是明文还是密文
# ---------------------------------------------------------------------------
Write-Header "1. git 对象库内容检查 (git cat-file)"

$raw = git cat-file -p "HEAD:main.cpp" 2>&1
$isEncrypted = $raw -match "%TSD-Header"  # 加密头标识

Write-Result "git 对象库中 main.cpp 已加密" $isEncrypted

# 验证工作区文件是明文
$workingContent = Get-Content "main.cpp" -Raw -ErrorAction SilentlyContinue
$isPlaintext = $workingContent -match "#include"
Write-Result "工作区 main.cpp 是明文（可被编译器读取）" $isPlaintext

Write-Host ""
Write-Host "结论：git 对象库存密文，工作区是明文 → 加密透明化（clean/smudge filter）" -ForegroundColor Yellow

# ---------------------------------------------------------------------------
# 2. git diff 功能测试（需要至少两个提交）
# ---------------------------------------------------------------------------
Write-Header "2. git diff 功能测试"

$commitCount = (git rev-list HEAD --count) -as [int]
Write-Host "当前提交数量: $commitCount"

if ($commitCount -ge 2) {
    $diffOut = git diff HEAD~1 HEAD -- main.cpp 2>&1
    $hasDiff = $diffOut.Length -gt 0

    Write-Result "git diff 在两个提交间产生输出" $hasDiff

    # 检查 diff 输出是否是二进制差异（密文 diff）
    $isBinaryDiff = $diffOut -match "Binary files"
    $isTextDiff   = $diffOut -match "^[+-]" -and -not $isBinaryDiff

    Write-Result "diff 输出为文本（可读）" $isTextDiff "二进制diff=$isBinaryDiff"

    if ($isBinaryDiff) {
        Write-Host ""
        Write-Host "  ⚠ 警告：git diff 产生二进制差异，说明加密后的密文每次不同，" -ForegroundColor Yellow
        Write-Host "           导致 git 无法进行行级别文本对比。" -ForegroundColor Yellow
        Write-Host "    建议：配置 .gitattributes 的 diff driver，使用解密后内容做 diff。" -ForegroundColor Yellow
    }
} else {
    Write-Host "  （跳过：当前只有 $commitCount 个提交，需要 ≥ 2 个才能对比）" -ForegroundColor Gray
    Write-Host "  将在本脚本末尾模拟第二次提交后重新测试。" -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
# 3. git log -p 功能测试
# ---------------------------------------------------------------------------
Write-Header "3. git log -p 历史补丁"

$logOut = git log -p --follow -- main.cpp 2>&1 | Select-Object -First 30
$hasLog = $logOut.Length -gt 0
Write-Result "git log -p 能输出 main.cpp 的历史" $hasLog

$isBinaryLog = ($logOut -join "`n") -match "Binary files"
Write-Result "log 补丁为文本格式（非二进制）" (-not $isBinaryLog)

if ($isBinaryLog) {
    Write-Host "  ⚠ 历史补丁为二进制，行级别变更追溯受限。" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# 4. git show 测试
# ---------------------------------------------------------------------------
Write-Header "4. git show 指定提交内容"

$showOut = git show "HEAD:main.cpp" 2>&1
$showEncrypted = $showOut -match "%TSD-Header"
Write-Result "git show HEAD:main.cpp 返回加密内容（与 cat-file 一致）" $showEncrypted

# ---------------------------------------------------------------------------
# 5. git blame 测试
# ---------------------------------------------------------------------------
Write-Header "5. git blame 行级追溯"

# blame 在工作区操作，不直接读 blob
$blameOut = git blame main.cpp 2>&1
$blameOk  = $blameOut -match "main"  # 能找到函数名
Write-Result "git blame 能在工作区对 main.cpp 进行行级追溯" $blameOk

if (-not $blameOk) {
    Write-Host "  ⚠ blame 失败，可能因为加密数据无法匹配文本行号。" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# 6. 模拟版本变更：修改 main.cpp，提交第二版，再次测 diff
# ---------------------------------------------------------------------------
Write-Header "6. 模拟版本变更后重测 git diff"

$origContent = Get-Content "main.cpp" -Raw

# 在文件末尾追加一行注释（模拟代码修改）
$newContent = $origContent.TrimEnd() + "`n// v2: add diagnostic output`n"
Set-Content "main.cpp" -Value $newContent -NoNewline

git add main.cpp
git commit -m "test: append comment to main.cpp for diff test" | Out-Null
Write-Host "已提交第二版 main.cpp (HEAD = $(git rev-parse --short HEAD))"

# 重新执行 diff
$diffV2 = git diff HEAD~1 HEAD -- main.cpp 2>&1
$isBinaryV2 = ($diffV2 -join "`n") -match "Binary files"
$isTextV2   = ($diffV2 -join "`n") -match "^[+-]" -and -not $isBinaryV2

Write-Result "v2 diff 为文本格式（行级可读 diff）" $isTextV2
Write-Result "v2 diff 产生二进制差异（密文每次不同）" $isBinaryV2

if ($isBinaryV2) {
    Write-Host ""
    Write-Host "  结论：加密密文随机化导致 git diff 退化为二进制对比，" -ForegroundColor Red
    Write-Host "         版本间文本差异无法追溯。" -ForegroundColor Red
    Write-Host ""
    Write-Host "  解决方案选项：" -ForegroundColor Cyan
    Write-Host "    A) 在 .gitattributes 中配置 diff=<driver-name>，" -ForegroundColor White
    Write-Host "       driver 的 textconv 调用解密工具，让 git 用明文做 diff。" -ForegroundColor White
    Write-Host "    B) 使用确定性加密（相同明文 → 相同密文），" -ForegroundColor White
    Write-Host "       但会丧失语义安全性（不推荐）。" -ForegroundColor White
    Write-Host "    C) 仅对敏感文件加密，普通源码保持明文。" -ForegroundColor White
} else {
    Write-Host ""
    Write-Host "  结论：git diff 正常工作，版本管理功能不受加密影响。" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 汇总
# ---------------------------------------------------------------------------
Write-Header "测试汇总"
$items = @(
    "密文存入 git 对象库",
    "工作区明文可被编译器/IDE 读取",
    "git log 能列出历史提交",
    "git show / cat-file 返回密文",
    "git diff 行级文本对比" + (if ($isBinaryV2) { "（受损 ❌）" } else { "（正常 ✅）" }),
    "git blame 行追溯"   + (if ($blameOk)    { "（正常 ✅）" } else { "（受损 ❌）" })
)
$items | ForEach-Object { Write-Host "  • $_" }
Write-Host ""
