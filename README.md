# cx

`cx` 是基于 [`openai/codex`](https://github.com/openai/codex) 的定制跟随版本：命令行编码助手，
中文界面，内置渠道开箱即用。跟随官方最新稳定 release 自动编译发布。

> 官方源码以 git submodule 形式引入（`codex/`），本仓库只叠加品牌/渠道补丁与打包配置，
> 不手改上游源码。维护者定制说明见 [CUSTOMIZATION.md](CUSTOMIZATION.md)。

---

## 安装

**推荐方式：下载原生安装包，双击按向导安装。** 无需运行任何脚本、无需手改 PATH，
安装完成后打开一个新终端直接输入 `cx` 即可。

从 [GitHub Releases](../../releases) 下载对应平台的安装包：

| 平台 | 安装包 | 说明 |
|------|--------|------|
| macOS (Apple Silicon) | `cx-<版本>-arm64.pkg` | 双击按向导安装，装到 `/usr/local/bin/cx` |
| Windows (x64) | `cx-<版本>-x64.msi` | 双击按向导安装（per-user，无需管理员） |

> 也提供裸二进制 `cx` / `cx.exe` 作为高级/自动化场景的附加资产，
> 配合 `installer/install.sh`（Mac）或 `installer/install.ps1`（Windows）安装。
> 一般用户用上面的安装包即可，无需接触脚本。

安装包会自动完成三件事：装入 `cx` 可执行文件、把它加入 PATH、写入内置渠道配置
（若你已有 `~/.codex/config.toml` 且含内置渠道段，则**不覆盖**你的配置）。

### macOS：双击安装

1. 下载 `cx-<版本>-arm64.pkg`。
2. 双击打开，按「安装器」向导完成（需要管理员密码，因为要写入 `/usr/local/bin`）。
3. 打开一个**新终端**，运行 `cx`。

如果安装包未签名，macOS **Gatekeeper** 双击时会提示「无法打开，因为它来自身份不明的
开发者」。绕过方法（二选一）：

- **右键打开**（推荐）：在 Finder 里右键点击（或 Control + 单击）`.pkg` → 选「打开」→
  弹窗里再点「打开」。
- **命令行去隔离属性**：
  ```sh
  xattr -d com.apple.quarantine ~/Downloads/cx-<版本>-arm64.pkg
  ```

详见 [packaging/macos/README.md](packaging/macos/README.md)。

### Windows：双击安装

1. 下载 `cx-<版本>-x64.msi`。
2. 双击打开，按向导完成（欢迎 → 许可 → 选目录 → 确认 → 完成）。默认装到
   `%LOCALAPPDATA%\Programs\cx`，**per-user 安装，无需管理员权限**。
3. 打开一个**新的** PowerShell 或 CMD 窗口，运行 `cx`。

如果安装包未签名，Windows **SmartScreen** 可能提示「Windows 已保护你的电脑」。这是给
未知发布者的常规告警，并非文件有害。绕过方法（二选一）：

- **弹窗里点「仍要运行」**（推荐）：点「更多信息 / More info」→「仍要运行 / Run anyway」。
- **解除锁定**：右键 `.msi` →「属性」→ 勾选「解除锁定 / Unblock」→ 确定；
  或在 PowerShell 里 `Unblock-File .\cx-<版本>-x64.msi`。

详见 [packaging/windows/README.md](packaging/windows/README.md)。

---

## 卸载

### macOS

`.pkg` 没有原生卸载器，用仓库提供的卸载脚本：

```sh
sudo packaging/macos/uninstall.sh            # 删二进制 + forget 收据，配置默认保留
sudo packaging/macos/uninstall.sh --purge-config  # 同时删除 ~/.codex/config.toml
```

或手动：

```sh
sudo rm -f /usr/local/bin/cx
sudo pkgutil --forget com.cx.cli
```

### Windows

`.msi` 在「应用和功能 / 控制面板 → 程序和功能」有标准卸载入口：

- **图形界面**：设置 → 应用 → 已安装的应用 → 找到 **cx CLI** → 卸载。
- **命令行**：`Get-Package "cx CLI" | Uninstall-Package`。

卸载会移除 `cx.exe`、随包分发的 `config.toml` 副本，并从用户 PATH 移除安装目录。
你的个人配置 `%USERPROFILE%\.codex\config.toml` **默认保留**，需彻底清理时手动删除。

---

## 配置

内置渠道配置在首次安装时写入 `~/.codex/config.toml`（Windows 为
`%USERPROFILE%\.codex\config.toml`）。若该文件已存在且含内置渠道段，安装器**不会覆盖**，
尊重你的手动修改。如需切换到自己的渠道，直接编辑该文件即可。

---

## 面向维护者

- [CUSTOMIZATION.md](CUSTOMIZATION.md) —— 所有定制替换点清单（命令名 / 品牌名 / 渠道 /
  启动动画 / 安装包产品名·Publisher·图标·标识符）+ 自动更新/发布流程。
- [TODO.md](TODO.md) —— 项目计划、决策表、目录结构、里程碑。
- [brand/SECURITY.md](brand/SECURITY.md) —— 分发前安全清理结论（内置 token 方案、凭据剥离）。
