# macOS 原生安装包（`.pkg`）

面向 Mac 用户的原生安装方式：下载 `.pkg`，双击按向导安装，之后新终端直接用 `cx`，
无需运行任何脚本、无需手改 PATH。

> 支持 **Apple Silicon（arm64）**。Intel（x86_64）在恢复编译前暂不提供
> （见 `.github/workflows/build.yml` 矩阵注释）。

---

## 安装

1. 从 [GitHub Releases](../../releases) 下载 `cx-<版本>-arm64.pkg`。
2. 双击打开，按「安装器」向导完成安装（需要管理员密码，因为要写入
   `/usr/local/bin`）。
3. 打开一个**新终端**，直接运行：
   ```sh
   cx
   ```

安装做了两件事：

- **二进制**：把 `cx` 装到 `/usr/local/bin/cx`（系统级可执行路径，默认在 PATH 中，
  新终端可直接调用）。
- **内置渠道配置**：安装后脚本（postinstall）以幂等方式把打包期注入的成品
  `config.toml` 写入当前登录用户的 `~/.codex/config.toml`。
  - 若你已有 `~/.codex/config.toml` 且含 `[model_providers.newapi]` 段 → **不覆盖**，
    尊重你的手动修改；
  - 若文件不存在 → 写入完整内置配置；
  - 若文件存在但缺该段 → 追加内置配置，保留你原有内容。

---

## Gatekeeper（未签名 `.pkg` 的绕过）

如果本项目**未配置** Apple 开发者签名 / 公证的 Secret，产出的 `.pkg` 是未签名的，
macOS Gatekeeper 双击时会拦截并提示「无法打开，因为它来自身份不明的开发者」。
两种绕过方法（二选一）：

### 方法 A：右键打开（推荐，最简单）

在 Finder 里**右键点击**（或按住 Control 单击）`.pkg` → 选择「打开」→ 在弹窗里再次
点「打开」。此后即可正常安装。

### 方法 B：命令行去隔离属性

```sh
xattr -d com.apple.quarantine ~/Downloads/cx-<版本>-arm64.pkg
```

去掉隔离属性后即可双击正常安装。

> 若项目配置了 `CX_SIGN_IDENTITY`（Developer ID Installer 证书）与
> `CX_NOTARIZE_PROFILE`（notarytool keychain profile）两个 Secret，CI 会自动对 `.pkg`
> 签名并公证，用户无需上述绕过步骤。见 `build-pkg.sh` 顶部说明。

---

## 卸载

`.pkg` 没有原生卸载器，需手动移除。仓库提供了脚本化的卸载步骤：

```sh
sudo packaging/macos/uninstall.sh
```

它会：

1. 删除 `/usr/local/bin/cx`；
2. `pkgutil --forget com.cx.cli` 遗忘安装收据（不影响文件，只让系统不再记录该包已装）。

**配置文件默认保留**（`~/.codex/config.toml` 可能已被你手动修改）。如需一并删除：

```sh
sudo packaging/macos/uninstall.sh --purge-config
```

### 手动卸载（不用脚本）

```sh
sudo rm -f /usr/local/bin/cx           # 删二进制
sudo pkgutil --forget com.cx.cli       # 遗忘安装收据
rm -f ~/.codex/config.toml             # （可选）删配置
```

---

## 维护者：本地 / CI 如何构建

`.pkg` 由 `pkgbuild` + `productbuild` 构建，这两个是 **macOS 专有工具**，本机
（ARM64 Linux）不参与打包。构建在 CI 的 `macos-14` runner 上跑
（`.github/workflows/release.yml` 的 `package_macos` job）：

1. 下载 `build.yml` 编译产出的 `cx`（arm64）二进制；
2. `scripts/render-config.sh` 渲染成品 `config.toml`（渠道值经 GitHub Secret 注入）；
3. `packaging/macos/build-pkg.sh` 组装 payload + postinstall，调
   `pkgbuild`/`productbuild` 产出 `.pkg`。

本地在 Mac 上手动构建（需已有编译好的二进制与渲染好的 config）：

```sh
packaging/macos/build-pkg.sh \
  --binary path/to/cx \
  --config path/to/config.toml \
  --version 0.142.5-cx.1 \
  --arch arm64 \
  --out dist/cx-0.142.5-cx.1-arm64.pkg
```

**目录结构**：

```
packaging/macos/
  build-pkg.sh          # 构建脚本（pkgbuild + productbuild），只在 macOS 跑
  uninstall.sh          # 卸载脚本（删二进制 + forget 收据，配置默认保留）
  README.md             # 本文件
  scripts/
    postinstall         # pkg 安装后脚本：以登录用户身份幂等写 ~/.codex/config.toml
```

`postinstall` 复用 `installer/write-default-config.sh`（US-008）的幂等写入契约，
构建时由 `build-pkg.sh` 连同渲染好的 `config.toml` 一起复制进 pkg 的 scripts 段。
