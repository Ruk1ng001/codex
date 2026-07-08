<#
.SYNOPSIS
  用 WiX Toolset 构建 cx CLI 的 Windows 原生安装器（.msi）(US-011)。

.DESCRIPTION
  只在 CI 的 Windows runner 上跑（见 .github/workflows/package-windows.yml 可复用工作流）；
  本机（维护者 ARM64 Linux）不参与打包 —— WiX/MSI 是 Windows 工具链，与 macOS .pkg 一样。

  职责：把编译产物 cx.exe + 渲染好的 config.toml + US-008 幂等写入脚本组装成一个 .msi，
  产物双击即弹图形化安装向导（选目录 / 进度 / 完成页），装完写用户 PATH + 登记 ARP 卸载入口。

  ── 输入从哪来（与 packaging/macos/build-pkg.sh 的分工一致）──────────────────
    - cx.exe        由 build.yml 编译产出（US-009），不在此重编译。
    - config.toml   由 scripts/render-config.sh 渲染（US-007，渠道值经 CI Secret 注入），含 token。
    - writer        installer/write-default-config.ps1（US-008），复用其幂等契约，不重复实现。

  ── WiX 工具链 ──────────────────────────────────────────────────────
    使用 WiX v5/v4 的 dotnet 工具（`wix`）+ UI 扩展（WixToolset.UI.wixext）。
    CI 里先 `dotnet tool install --global wix` 并 `wix extension add WixToolset.UI.wixext`。

.PARAMETER Binary
  cx.exe 路径（编译产物）。等价环境变量 CX_BINARY。

.PARAMETER Config
  成品 config.toml 路径（render-config.sh 渲染产物，含真实渠道值）。等价 CX_CONFIG。

.PARAMETER Version
  完整定制版本号（形如 0.142.5-cx.1），写进 ARP 展示版本与产物文件名。等价 CX_VERSION。

.PARAMETER Arch
  目标架构标签（x64 / arm64，仅用于产物命名与展示）。等价 CX_ARCH，默认 x64。

.PARAMETER Out
  输出 .msi 路径。等价 CX_MSI_OUT，默认 dist\cx-<version>-<arch>.msi。

.EXAMPLE
  packaging\windows\build-msi.ps1 -Binary dist\cx.exe -Config dist\config.toml -Version 0.142.5-cx.1 -Arch x64
#>
[CmdletBinding()]
param(
    [string]$Binary  = $env:CX_BINARY,
    [string]$Config  = $env:CX_CONFIG,
    [string]$Version = $env:CX_VERSION,
    [string]$Arch    = $env:CX_ARCH,
    [string]$Out     = $env:CX_MSI_OUT
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step { param([string]$m) Write-Host "[msi] $m" -ForegroundColor Cyan }
function Die        { param([string]$m) Write-Host "[msi] $m" -ForegroundColor Red; exit 1 }

if ([string]::IsNullOrWhiteSpace($Binary))  { Die "缺少 -Binary（cx.exe 路径）。" }
if ([string]::IsNullOrWhiteSpace($Config))  { Die "缺少 -Config（成品 config.toml 路径）。" }
if ([string]::IsNullOrWhiteSpace($Version)) { Die "缺少 -Version（版本号，如 0.142.5-cx.1）。" }
if ([string]::IsNullOrWhiteSpace($Arch))    { $Arch = "x64" }

if (-not (Test-Path -LiteralPath $Binary -PathType Leaf)) { Die "找不到二进制: $Binary" }
if (-not (Test-Path -LiteralPath $Config -PathType Leaf)) { Die "找不到成品配置: $Config" }

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$wxs    = Join-Path $scriptDir "cx.wxs"
$writer = Join-Path $scriptDir "..\..\installer\write-default-config.ps1"
$license = Join-Path $scriptDir "License.rtf"

foreach ($f in @($wxs, $writer, $license)) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { Die "缺少必需文件: $f" }
}

# ── MSI 数字版本 ────────────────────────────────────────────────────
# MSI 的 ProductVersion 只接受 a.b.c[.d] 且各段为数字。把定制版本 0.142.5-cx.1
# 转成 0.142.5.1：取 -cx. 前的三段数字 + -cx.N 的 N 作第四段。
$msiVersion = $null
if ($Version -match '^(?<base>[0-9]+\.[0-9]+\.[0-9]+)(?:-cx\.(?<n>[0-9]+))?') {
    $base = $Matches['base']
    $n = if ($Matches.ContainsKey('n') -and $Matches['n']) { $Matches['n'] } else { "0" }
    $msiVersion = "$base.$n"
} else {
    Die "无法从版本号 '$Version' 解析出 MSI 数字版本（期望形如 0.142.5-cx.1）。"
}
Write-Step "定制版本 $Version → MSI 数字版本 $msiVersion"

# WiX 架构标签：x64 / arm64（与 build.yml 的 windows target 对齐）。
switch ($Arch) {
    "x64"   { $wixArch = "x64" }
    "arm64" { $wixArch = "arm64" }
    default { Die "不支持的架构: $Arch（应为 x64 / arm64）。" }
}

if ([string]::IsNullOrWhiteSpace($Out)) {
    $Out = Join-Path "dist" ("cx-{0}-{1}.msi" -f $Version, $Arch)
}
$outDir = Split-Path -Parent $Out
if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

Write-Step "二进制:   $Binary"
Write-Step "配置:     $Config"
Write-Step "写入脚本: $writer"
Write-Step "架构:     $wixArch"
Write-Step "输出:     $Out"

# ── 调 WiX 构建 ─────────────────────────────────────────────────────
# 预处理变量经 -d 传入 cx.wxs；-ext 加载 UI 扩展（WixUI_InstallDir）。
$wixArgs = @(
    "build",
    "-arch", $wixArch,
    "-ext", "WixToolset.UI.wixext",
    "-d", "CxExe=$Binary",
    "-d", "CxConfig=$Config",
    "-d", "CxWriter=$writer",
    "-d", "LicenseRtf=$license",
    "-d", "ProductVersion=$msiVersion",
    "-d", "DisplayVersion=$Version",
    "-o", $Out,
    $wxs
)

Write-Step "运行: wix $($wixArgs -join ' ')"
& wix @wixArgs
if ($LASTEXITCODE -ne 0) { Die "wix build 失败（退出码 $LASTEXITCODE）。" }

if (-not (Test-Path -LiteralPath $Out -PathType Leaf)) { Die "wix 未产出 $Out。" }

# ── 可选 Authenticode 代码签名（验收 7，配置了 Secret 才生效）────────────
# 提供 CX_SIGN_PFX_BASE64（base64 的 .pfx）+ CX_SIGN_PFX_PASSWORD 才签名，否则产出未签名 .msi。
if (-not [string]::IsNullOrWhiteSpace($env:CX_SIGN_PFX_BASE64)) {
    Write-Step "对 .msi 做 Authenticode 代码签名"
    $pfxPath = Join-Path ([System.IO.Path]::GetTempPath()) ("cx-sign-{0}.pfx" -f $PID)
    try {
        [System.IO.File]::WriteAllBytes($pfxPath, [System.Convert]::FromBase64String($env:CX_SIGN_PFX_BASE64))
        $signtool = Get-Command signtool.exe -ErrorAction SilentlyContinue
        if (-not $signtool) {
            # signtool 随 Windows SDK 分发，不一定在 PATH；在常见 SDK 路径下搜最新版。
            $found = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\signtool.exe" -ErrorAction SilentlyContinue |
                Sort-Object FullName | Select-Object -Last 1
            if ($found) { $signtool = $found }
        }
        if (-not $signtool) { Die "配置了签名但找不到 signtool.exe（需 Windows SDK）。" }
        $signExe = if ($signtool.Path) { $signtool.Path } else { $signtool.FullName }
        $ts = if ([string]::IsNullOrWhiteSpace($env:CX_SIGN_TIMESTAMP_URL)) { "http://timestamp.digicert.com" } else { $env:CX_SIGN_TIMESTAMP_URL }
        & $signExe sign /f $pfxPath /p $env:CX_SIGN_PFX_PASSWORD /fd SHA256 /tr $ts /td SHA256 $Out
        if ($LASTEXITCODE -ne 0) { Die "signtool 签名失败（退出码 $LASTEXITCODE）。" }
        Write-Step "代码签名完成。"
    } finally {
        if (Test-Path -LiteralPath $pfxPath) { Remove-Item -LiteralPath $pfxPath -Force }
    }
} else {
    Write-Warning "[msi] 未配置 CX_SIGN_PFX_BASE64：产出未签名 .msi，用户双击可能触发 SmartScreen 告警（绕过法见 README）。"
}

Write-Step "完成：$Out"
