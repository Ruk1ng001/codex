# Windows 原生安装器（`.msi`）

面向 Windows 用户的原生安装方式：下载 `.msi`，双击按向导安装，之后新终端
（PowerShell / CMD）直接用 `cx`，无需运行任何脚本、无需手改 PATH。

> 支持 **x64**。ARM64 Windows 记为可选后续项（`build-msi.ps1` 支持 `-Arch arm64`，
> 但当前 CI 只产出 x64 `.msi`，见 `.github/workflows/build.yml` 矩阵）。

---

## 安装

1. 从 [GitHub Releases](../../releases) 下载 `cx-<版本>-x64.msi`。
2. 双击打开，按安装向导完成安装：
   - 欢迎页 → 许可页 → **选择安装目录**页（默认 `%LOCALAPPDATA%\Programs\cx`）→
     确认页 → 进度页 → 完成页。
   - **per-user 安装，无需管理员权限**（装到当前用户的 `%LOCALAPPDATA%`）。
3. 打开一个**新的** PowerShell 或 CMD 窗口，直接运行：
   ```powershell
   cx
   ```

安装做三件事：

- **二进制**：把 `cx.exe` 装到你选择的目录（默认 `%LOCALAPPDATA%\Programs\cx`）。
- **PATH**：把安装目录写入**用户级** PATH 环境变量。PowerShell 与 CMD 都从这里继承
  PATH，写一次两种 shell 的新会话都能直接 `cx`（当前已开的窗口需重开才生效）。
- **内置渠道配置**：安装后以幂等方式把打包期注入的成品 `config.toml` 写入
  `%USERPROFILE%\.codex\config.toml`。
  - 若你已有 `~/.codex/config.toml` 且含 `[model_providers.newapi]` 段 → **不覆盖**，
    尊重你的手动修改；
  - 若文件不存在 → 写入完整内置配置；
  - 若文件存在但缺该段 → 追加内置配置，保留你原有内容。

---

## SmartScreen（未签名 `.msi` 的绕过）

如果本项目**未配置** Authenticode 代码签名的 Secret，产出的 `.msi` 是未签名的，
Windows SmartScreen 双击时可能提示「Windows 已保护你的电脑 / Windows protected
your PC」。这是给未知发布者的常规告警，**并非**表示文件有害。绕过方法：

### 方法 A：SmartScreen 弹窗里点「仍要运行」（推荐）

在「Windows 已保护你的电脑」弹窗里，点击 **更多信息 / More info**，然后点
**仍要运行 / Run anyway**，即可继续安装。

### 方法 B：文件属性里解除锁定

右键点击下载的 `.msi` → **属性 / Properties** → 在「常规」页底部勾选
**解除锁定 / Unblock** → 确定。之后双击不再告警。

也可在 PowerShell 里解除锁定：

```powershell
Unblock-File .\cx-<版本>-x64.msi
```

> 若项目配置了 `CX_SIGN_PFX_BASE64`（base64 编码的 `.pfx` 证书）与
> `CX_SIGN_PFX_PASSWORD` 两个 Secret，CI 会自动对 `.msi` 做 Authenticode 签名，
> 可降低（有信誉的证书可消除）SmartScreen 告警。见 `build-msi.ps1` 顶部说明。

---

## 卸载

`.msi` 安装会在**「应用和功能 / 控制面板 → 程序和功能」**登记标准卸载入口
（DisplayName `cx CLI`、版本、发布者、卸载命令）。卸载方式二选一：

- **图形界面**：设置 → 应用 → 已安装的应用 → 找到 **cx CLI** → 卸载。
- **命令行**：
  ```powershell
  # 按显示名卸载（PowerShell）
  Get-Package "cx CLI" | Uninstall-Package
  # 或用 msiexec（需要 ProductCode，可从上面命令或注册表获取）
  ```

卸载会移除 `cx.exe`、随包分发的 `config.toml` 副本，并从用户 PATH 中移除安装目录。

**用户配置默认保留**：`%USERPROFILE%\.codex\config.toml` 是你的个人配置（可能已手动
修改），MSI 卸载不会删除它。如需彻底清理，手动删除该文件即可。

---

## 维护者：本地 / CI 如何构建

`.msi` 由 **WiX Toolset**（v5/v4 的 `wix` dotnet 工具）构建，是 **Windows 工具链**，
本机（ARM64 Linux）不参与打包。构建在 CI 的 Windows runner 上跑
（`.github/workflows/release.yml` 的 `package_windows` job）：

1. 下载 `build.yml` 编译产出的 `cx.exe`（x64）；
2. `scripts/render-config.sh` 渲染成品 `config.toml`（渠道值经 GitHub Secret 注入）；
3. `packaging/windows/build-msi.ps1` 调 WiX 把二进制 + config + 幂等写入脚本组装成 `.msi`。

本地在 Windows 上手动构建（需已装 WiX 与 UI 扩展、已有编译好的二进制与渲染好的 config）：

```powershell
# 一次性：安装 WiX 工具与 UI 扩展
dotnet tool install --global wix
wix extension add --global WixToolset.UI.wixext

# 构建
packaging\windows\build-msi.ps1 `
  -Binary path\to\cx.exe `
  -Config path\to\config.toml `
  -Version 0.142.5-cx.1 `
  -Arch x64 `
  -Out dist\cx-0.142.5-cx.1-x64.msi
```

**目录结构**：

```
packaging/windows/
  cx.wxs          # WiX 源文件：定义 .msi（目录/组件/PATH/ARP/配置写入自定义动作）
  build-msi.ps1   # 构建脚本（调 wix），只在 Windows 跑；含可选 Authenticode 签名
  License.rtf     # 安装向导许可页文本
  README.md       # 本文件
```

`cx.wxs` 里安装后写配置的自定义动作复用 `installer/write-default-config.ps1`（US-008）的
幂等契约，构建时由 `build-msi.ps1` 连同渲染好的 `config.toml` 一起打进 `.msi`。
