<#
.SYNOPSIS
  首启动幂等写入(Windows 安装器)——把内置渠道配置写入 %USERPROFILE%\.codex\config.toml。

.DESCRIPTION
  目标：用户首次启动就有可用配置，且绝不覆盖其后续的手动修改。

  ── 行为契约（与 installer/write-default-config.sh 逐条对齐）─────────────
    1. 配置目录：尊重 $env:CODEX_HOME（与 codex 本体解析一致），未设置则用
       %USERPROFILE%\.codex（保持官方默认目录，不改动）。配置文件固定为 <目录>\config.toml。
       ⚠ Windows 用 $env:USERPROFILE 而非 PowerShell 的 $HOME：codex 本体（Rust）
       用 dirs::home_dir() 解析 home，Windows 上它返回 %USERPROFILE%（FOLDERID_Profile），
       而 PowerShell 的 $HOME 是 $env:HOMEDRIVE$env:HOMEPATH，域环境下二者可能不一致，
       若用 $HOME 写入会导致 codex 读不到本脚本写的配置（US-019）。bash 版对应用 $HOME，
       因为 Unix 上 dirs::home_dir() 就是读 $HOME，两端各自与 codex 本体解析一致。
    2. 幂等判定：目标 config.toml 已存在且含段头 [model_providers.newapi]
       ⇒ 完全不动，尊重用户的手动修改（幂等，退出码 0）。
    3. 不存在      ⇒ 创建目录并写入内置渠道配置。
    4. 存在但缺该段 ⇒ 追加内置渠道配置（带注释分隔块），不动用户原有内容。

  ── 要写入的内容从哪来 ──────────────────────────────────────────────
    -SourceConfig 参数 = 成品配置文件路径；省略时默认取脚本同目录的 config.toml。
    该成品配置由打包期 scripts/render-config.sh 渲染（占位符已替换成真实渠道值），
    随安装器一起分发。含 token，属敏感文件。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File installer\write-default-config.ps1
#>
[CmdletBinding()]
param(
    [string]$SourceConfig
)

$ErrorActionPreference = 'Stop'

# 段头标记：幂等判定的唯一依据（TOML 段头，允许前导空白与行尾注释）。
$ProviderSectionRe = '^\s*\[model_providers\.newapi\]\s*(#.*)?$'

function Write-Info { param([string]$Message) Write-Host "[install] $Message" -ForegroundColor Cyan }
function Write-Warn { param([string]$Message) Write-Host "[install] $Message" -ForegroundColor Yellow }
function Die       { param([string]$Message) Write-Host "[install] $Message" -ForegroundColor Red; exit 1 }

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrEmpty($SourceConfig)) {
    $SourceConfig = Join-Path $scriptDir 'config.toml'
}

# 配置目录：CODEX_HOME 优先，否则 %USERPROFILE%\.codex（保持不变）。
# 用 $env:USERPROFILE 而非 $HOME：与 codex 本体 dirs::home_dir() 的 Windows 解析一致（见顶部说明）。
$codexHome = $env:CODEX_HOME
if ([string]::IsNullOrEmpty($codexHome)) {
    $userProfile = $env:USERPROFILE
    if ([string]::IsNullOrEmpty($userProfile)) {
        # 极少数无 %USERPROFILE% 的环境（如某些精简/服务账户）回退到 $HOME，避免直接失败。
        $userProfile = $HOME
    }
    $codexHome = Join-Path $userProfile '.codex'
}
$configPath = Join-Path $codexHome 'config.toml'

if (-not (Test-Path -LiteralPath $SourceConfig -PathType Leaf)) {
    Die "找不到成品配置: $SourceConfig（应由 render-config.sh 渲染后随安装器分发）"
}

# 情况 2：已存在且含内置渠道段 ⇒ 幂等，不动。
if ((Test-Path -LiteralPath $configPath -PathType Leaf) -and
    (Select-String -LiteralPath $configPath -Pattern $ProviderSectionRe -CaseSensitive -Quiet)) {
    Write-Info "已存在内置渠道配置（$configPath 含 [model_providers.newapi]），保持不变。"
    exit 0
}

if (-not (Test-Path -LiteralPath $codexHome -PathType Container)) {
    New-Item -ItemType Directory -Path $codexHome -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    # 情况 3：文件不存在 ⇒ 写入完整内置配置。
    $content = Get-Content -LiteralPath $SourceConfig -Raw
    Set-Content -LiteralPath $configPath -Value $content -NoNewline -Encoding utf8
    Write-Info "已写入内置渠道配置到 $configPath。"
} else {
    # 情况 4：文件存在但缺内置渠道段 ⇒ 追加，不动用户原有内容。
    $content = Get-Content -LiteralPath $SourceConfig -Raw
    $block = "`n# ---- 内置渠道配置（由安装器追加，缺失时补全）----`n" + $content
    Add-Content -LiteralPath $configPath -Value $block -NoNewline -Encoding utf8
    Write-Info "已在 $configPath 追加内置渠道配置（原有内容保留）。"
    Write-Warn "若原文件已含顶层 model / model_provider，TOML 不允许重复键，请手动核对。"
}
