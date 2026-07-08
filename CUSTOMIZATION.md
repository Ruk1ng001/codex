# 定制替换点清单

> 本文件供后续维护者使用：把本项目从占位品牌（命令名 `cx`、内置示例渠道）替换成
> 正式产品所需改动的**全部**替换点，逐项标明「改哪里、怎么改」。
>
> 核心原则：官方源码 `codex/` 是 git **submodule**，永远保持官方原样、只 fetch 不手改。
> 所有对源码的改动都以 `brand/patches/*.patch` 补丁形式叠加（见
> [补丁工作流](#补丁工作流)）。配置类改动（渠道值）走纯配置注入，连补丁都不需要。

---

## 目录：五个替换点

| # | 替换点 | 载体 | 改动方式 |
|---|--------|------|----------|
| 1 | [命令名](#1-命令名) | 补丁 `01-rename-cx` | 改一个 Rust 常量 + 一处 npm bin key |
| 2 | [品牌名 / 欢迎语](#2-品牌名--欢迎语) | 补丁 `02-brand-i18n` | 改 TUI 中文文案 |
| 3 | [渠道 base_url / token / model](#3-渠道-base_url--token--model) | 配置注入（无补丁） | 改环境变量 / `channel.env`，不改源码 |
| 4 | [启动动画](#4-启动动画) | 新建补丁组（当前无） | 替换 frames 文本或改 variant 选择 |
| 5 | [安装器与原生安装包](#5-安装器与原生安装包) | 安装器脚本 / `.pkg` / `.msi` 配置 | 改产品名 / Publisher / 图标 / 标识符等 |

---

## 1. 命令名

主命令名当前为占位短名 `cx`（原官方为 `codex`）。

**改动点集中在补丁 `01-rename-cx`（`brand/patches/01-rename-cx.patch`）覆盖的两个文件：**

- `codex-rs/cli/src/main.rs` —— 顶层常量 **`const COMMAND_NAME: &str = "cx";`** 是唯一改名点。
  clap 的 `bin_name = COMMAND_NAME` 与 `override_usage = command_usage()` 都引用它，
  `command_usage()` 用 `format!` 内联该常量拼出用法行。**改名只改这一个常量的值。**
- `codex-cli/package.json` —— npm `bin` key `"cx": "bin/codex.js"`。**仅当走 npm 分发时**
  需同步改这个 key（当前分发走安装器 + 裸二进制，npm 非主路径）。

**注意**：cargo 产物二进制名仍是 `codex`（`codex-rs/cli/Cargo.toml` 的 `[[bin]] name` 未改），
改名 `cx` 发生在 CI 的 stage 阶段（`build.yml` 里 `cargo build --bin codex` 后 `cp` 重命名成 `cx`）。
若想让 cargo 直接产出 `cx`，需在补丁里额外改 `Cargo.toml` 的 bin name（牵动更多，当前未做）。

**怎么改名**（例：`cx` → `mycli`）：
1. 修改 submodule 内 `codex-rs/cli/src/main.rs` 的 `COMMAND_NAME` 值（以及 `package.json` bin key）。
2. `scripts/make-patches.sh` 重新导出补丁 → 覆盖 `01-rename-cx.patch`。
3. 若安装器/文档里出现 `cx` 字样，一并替换（见替换点 5 与本文其他小节）。

---

## 2. 品牌名 / 欢迎语

品牌层文案（欢迎语、登录项、信任目录提示、输入框占位）已中文化，集中在补丁
`02-brand-i18n`（`brand/patches/02-brand-i18n.patch`），覆盖四个文件：

| 文件（相对 `codex/`） | 内容 |
|---|---|
| `codex-rs/tui/src/onboarding/welcome.rs` | **品牌欢迎语**：「欢迎使用 cx，你的命令行编码助手」（原 `Welcome to Codex, OpenAI's command-line coding agent`） |
| `codex-rs/tui/src/onboarding/auth.rs` | 登录选项标题/描述、浏览器与设备码提示、成功页、API key 录入页、错误文案 |
| `codex-rs/tui/src/onboarding/trust_directory.rs` | 当前目录、Git 子目录警告、信任说明、是/否选项、确认提示 |
| `codex-rs/tui/src/chatwidget.rs` | `PLACEHOLDERS`(8) + `SIDE_PLACEHOLDERS`(3) 输入框占位提示 |

**改品牌名**：欢迎语里的 `cx` 是品牌名出现的主要可见位置，在 `welcome.rs` 里改。
若同步改了命令名（替换点 1），记得让欢迎语中的名字与之一致。

**怎么改**：
1. 修改 submodule 内上述文件的中文字符串。
2. `scripts/make-patches.sh` 重新导出 → 覆盖 `02-brand-i18n.patch`。

⚠️ **快照测试影响**：这些字符串大量出现在 `codex-rs/tui/src/` 的 `#[cfg(test)]`
`insta` 快照断言（`.snap`）里，改文案会让这些测试失败。**这是预期取舍**——
release 走 CI 只 `cargo build --release`、从不 `cargo test`，故不受影响。
若将来 CI 加测试步骤，需对 tui 快照测试豁免或重生成 `.snap`。

（可选、当前未做）`codex-rs/core/src/default_client.rs` 的 `DEFAULT_ORIGINATOR`
是遥测标识（非可见文案），如需彻底去 OpenAI 品牌痕迹可另建补丁组处理。

---

## 3. 渠道 base_url / token / model

内置渠道走**纯配置注入，不改源码、不需要补丁**。三个值由占位符 → 环境变量映射，
在打包期渲染。

**模板**：`brand/config.template.toml`，含三个占位符：
```toml
model = "__MODEL__"
[model_providers.newapi]
base_url = "__BASE_URL__"
experimental_bearer_token = "__TOKEN__"
```

**占位符 → 环境变量的唯一映射表**在 `scripts/render-config.sh` 顶部的 `PLACEHOLDER_VARS`：

| 占位符 | 环境变量 | 含义 |
|---|---|---|
| `__BASE_URL__` | `CX_BASE_URL` | 渠道 API 地址（**必须提供 `/v1/responses` 端点**） |
| `__TOKEN__` | `CX_TOKEN` | 渠道 bearer token |
| `__MODEL__` | `CX_MODEL` | 默认模型名 |

**真实值来源（优先级从高到低）**：
1. 进程环境变量 —— CI 里由 **GitHub Actions Secret** 注入，绝不进 git；
2. `brand/channel.env` —— 本地打包用（示例见 `brand/channel.env.example`），
   已被根 `.gitignore` 忽略，绝不进 git。

**怎么换渠道**：线上改 CI Secret（`CX_BASE_URL`/`CX_TOKEN`/`CX_MODEL`），
本地改 `brand/channel.env`。**模板和源码都不用动。** 增删占位符只改 `render-config.sh`
的 `PLACEHOLDER_VARS` 一张表。

**provider key 限制**：不能用保留字 `openai`/`amazon-bedrock`/`ollama`/`lmstudio`，
当前用 `newapi`。若要改 key，需同步改 `config.template.toml` 里的段名
`[model_providers.newapi]` 和顶层 `model_provider = "newapi"`。

渲染产物 `brand/config.toml` 由安装器随包分发，首次启动经
`installer/write-default-config.*` 幂等写入 `~/.codex/config.toml`（`CODEX_HOME` 优先）。

**打包期嵌入成品 config（US-016）**：`release.yml` 的 `package_macos` / `package_windows`
job 在打包前调 `render-config.sh` 渲染出成品 `config.toml`，再交给 `build-pkg.sh` /
`build-msi.ps1` 打进 `.pkg` / `.msi`——安装包本身即「完整产品」，装完即用，无需任何外部
脚本或手动配置。四条安全约定：

- **渠道值只经 GitHub Secret 注入**（`CX_BASE_URL`/`CX_TOKEN`/`CX_MODEL`），绝不进 git 历史。
- **不进 CI 日志明文**：渲染前先 `::add-mask::` 把渠道值登记为掩码，万一后续步骤误回显，
  日志里也只显示 `***`。
- **成品 config 不作独立可下载资产**：只藏在 `.pkg` / `.msi` 内部；package job 上传前先删掉
  裸 `config.toml` 并断言其不存在，release 汇总 job 再兜底断言待发布目录无任何 `*.toml`。
- **换渠道零改脚本**：同上——只改 CI Secret / `channel.env`，打包脚本本体不动。

---

## 4. 启动动画

**当前状态：无自定义动画补丁**（沿用官方内置动画）。

启动动画是 `codex/codex-rs/tui/frames/<variant>/frame_1.txt` … `frame_36.txt` 的
装饰性 ASCII 粒子艺术，**编译期由 `include_str!` 嵌入二进制**，无品牌文字（无 "CODEX" Logo）。

- **variant 列表**：`codex-rs/tui/src/frames.rs` 的 `frames_for!("<目录名>")` +
  `ALL_VARIANTS` 数组（当前 10 个：`default`/`codex`/`openai`/`blocks`/`dots`/`hash`/
  `hbars`/`vbars`/`shapes`/`slug`）。
- **选择逻辑**：`codex-rs/tui/src/ascii_animation.rs`，默认 `variant_idx = 0`，
  `pick_random_variant()` 随机切换。

**怎么替换动画**（需新建补丁组，当前 manifest 未声明）：

- 方式 A（换内容，最简单）：直接替换某个 variant 目录下的 `frame_1.txt`…`frame_36.txt`
  文本（保持 36 帧、文件名不变），把改动导出为新补丁组。
- 方式 B（换 variant 集合）：改 `frames.rs` 的 `frames_for!` 目录名与 `ALL_VARIANTS`，
  和/或改 `ascii_animation.rs` 里默认 `variant_idx` / 去掉随机切换只保留品牌 variant。

无论哪种方式，都要：
1. 在 `brand/patches.manifest` 新增段（如 `[03-brand-frames]`）并列出改动的文件；
2. 改 submodule 内对应文件 → `scripts/make-patches.sh` 导出 `03-brand-frames.patch`。

⚠️ manifest 只声明**已实现**的补丁组（`apply-patches.sh` 前置校验要求每个声明组都有
对应 `.patch`，缺失即报错阻塞）。**新组的 manifest 条目必须与其 `.patch` 同一次提交加入**，
不要提前把未实现的组留在 manifest 里。

（`brand/frames/` 目录当前不存在——若要用「先在 brand 下放素材再拷进 submodule」的
工作流可自行创建，但最终生效的仍是 submodule 内 `codex-rs/tui/frames/` + 一个补丁组。）

---

## 5. 安装器与原生安装包

安装器（脚本安装器 + 原生 `.pkg`/`.msi`）里有大量与品牌绑定的字符串与标识符，
改品牌时需一并处理。下表按「载体」归类，逐项标明所在文件与修改方法。

### 5.1 脚本安装器（裸二进制备选路径）

| 替换点 | 文件 | 说明 / 修改方法 |
|---|---|---|
| PATH 注入标记块 | `installer/install.sh` | `# >>> cx installer >>>` … `# <<< cx installer <<<`，改品牌时连标记文案一起改 |
| 默认安装目录 | `installer/install.sh` | Mac 默认 `$BIN_DIR`；`installer/install.ps1` 默认 `%LOCALAPPDATA%\Programs\cx\bin` |
| 二进制探测名 | `installer/install.sh` / `install.ps1` | `cx-<target>` / `cx-<target>.exe`，**须与 `build.yml` 产物命名对齐** |
| 命令名 | `installer/install.sh` / `install.ps1` | `cx`（与替换点 1 的 `COMMAND_NAME` 保持一致） |

### 5.2 macOS 原生 `.pkg`（`installer/macos-pkg/`）

| 替换点 | 文件 | 说明 / 修改方法 |
|---|---|---|
| **安装器产品名** | `build-pkg.sh` | `productbuild` distribution.xml 里的 `<title>$COMMAND_NAME CLI</title>`（向导标题）、`<choice title>`，由 `COMMAND_NAME` 变量派生 |
| **pkg identifier** | `build-pkg.sh` 顶部 `PKG_IDENTIFIER="com.cx.cli"` | reverse-DNS 包标识（`pkgbuild --identifier` + distribution.xml 的 `<pkg-ref id>`）。改成正式厂商域名如 `com.acme.mycli` |
| **Publisher / 厂商** | `build-pkg.sh` | distribution.xml 的 `<organization>$PKG_IDENTIFIER</organization>`。可改为独立的厂商标识 |
| 命令名 | `build-pkg.sh` 顶部 `COMMAND_NAME="cx"` | payload 里二进制文件名 + 各处文案的单一来源 |
| 安装路径 | `build-pkg.sh` 顶部 `INSTALL_PREFIX="/usr/local/bin"` | payload 铺到系统根的目标目录 |
| **图标** | （当前无） | pkg 当前不含自定义图标。如需：在 distribution.xml 加 `<background>` / 用带图标的 `.app` 载荷，或对 `.pkg` 后处理；属可选增强 |
| 卸载脚本标识符 | `uninstall.sh` 的 `PKG_IDENTIFIER` 默认值 | **必须与 `build-pkg.sh` 的 `PKG_IDENTIFIER` 一致**，否则 `pkgutil --forget` 找不到收据 |

> ⚠️ 改 `PKG_IDENTIFIER` 时 `build-pkg.sh` 与 `uninstall.sh` 两处必须同步，否则卸载
> 脚本无法遗忘安装收据。

### 5.3 Windows 原生 `.msi`（`installer/windows-msi/`）

| 替换点 | 文件 | 说明 / 修改方法 |
|---|---|---|
| **安装器产品名** | `cx.wxs` `<Package Name="cx CLI">` | ARP（应用和功能）里的 DisplayName。改成正式产品名 |
| **Publisher / 厂商** | `cx.wxs` `<Package Manufacturer="cx">` | ARP 里的「发布者」。改成正式厂商名 |
| **UpgradeCode（GUID）** | `cx.wxs` `<Package UpgradeCode="aa574f41-...">` | 跨版本升级的**稳定标识**。**改品牌时不要改它**——旧版靠它被新版自动升级/卸载；改了会导致新旧版本无法互相识别、并存两份。仅当要开一条全新产品线时才换新 GUID |
| **ProductCode** | 无需手改 | `<Package>` 未写 `ProductId`/`Id`，WiX 每次构建**自动生成**新 ProductCode（`Id="*"` 语义）。`MajorUpgrade` 靠稳定的 UpgradeCode 处理升级，ProductCode 逐版本变化是正确行为，无需干预 |
| 安装目录名 | `cx.wxs` `<Directory Id="INSTALLFOLDER" Name="cx">` | 默认目录 `%LOCALAPPDATA%\Programs\cx` 的末段目录名 |
| 注册表 KeyPath | `cx.wxs` `Key="Software\cx\cx-cli"` | PathEnv 组件的 HKCU 标记键，改品牌时同步 |
| ARP 备注 | `cx.wxs` `ARPCOMMENTS` / `SummaryInformation Description` | 展示用描述文案 |
| **图标** | （当前无） | `.msi` 当前未设 `ARPPRODUCTICON`。如需 ARP 图标：加 `<Icon Id="cx.ico" SourceFile="...">` + `<Property Id="ARPPRODUCTICON" Value="cx.ico">`；属可选增强 |
| 产物文件名 | `build-msi.ps1` | `cx-<version>-<arch>.msi` |
| 许可页文本 | `License.rtf` | 安装向导许可页内容 |

### 5.4 图标（当前状态）

**`.pkg` 与 `.msi` 当前均不含自定义品牌图标**（用系统默认）。仓库里也没有图标资源文件。
若要加品牌图标，属可选增强，改法见上面 5.2 / 5.3 的「图标」行；同时需把 `.ico`（Windows）
/ 图标素材加入仓库并在打包脚本里引用。

### 5.5 可选签名 / 公证的 Secret（不改文件，配 CI Secret）

不改任何源文件，只在 CI 配置对应 Secret 即启用签名（未配则产未签名包，用户按各
安装包 README 的 Gatekeeper / SmartScreen 绕过法安装）：

- macOS `.pkg`：`CX_SIGN_IDENTITY`（Developer ID Installer 证书）+ `CX_NOTARIZE_PROFILE`
  （notarytool keychain profile）→ `build-pkg.sh` 自动签名 + 公证。
- Windows `.msi`：`CX_SIGN_PFX_BASE64`（base64 的 `.pfx`）+ `CX_SIGN_PFX_PASSWORD`
  （+ 可选 `CX_SIGN_TIMESTAMP_URL`）→ `build-msi.ps1` 自动 Authenticode 签名。

---

## 补丁工作流

改任何源码（替换点 1、2、4）都走同一套脚本，**从不手改 submodule 后直接提交**：

| 脚本 | 作用 |
|---|---|
| `scripts/reset-src.sh` | 把 `codex/` 还原到基线（`brand/BASE_SHA`） |
| `scripts/apply-patches.sh` | 按 `patches.manifest` 声明顺序把补丁叠加到干净基线（含前后校验） |
| `scripts/make-patches.sh` | 从工作区改动导出补丁到 `brand/patches/`（含非空校验） |
| `scripts/test-patch-roundtrip.sh` | 端到端闭环：改动→导出→还原→重应用→逐字节比对，不编译 |

**改源码的标准循环**：
1. `scripts/apply-patches.sh`（让工作区带上现有补丁改动）；
2. 在 `codex/` 内编辑目标文件；
3. `scripts/make-patches.sh` 重新导出对应补丁；
4. `scripts/reset-src.sh` + `scripts/apply-patches.sh` 验证补丁能干净重应用。

补丁分组清单 `brand/patches.manifest` 是**单一真源**：`[组名]` 段头（组名自带
`NN-` 序号前缀）+ 逐行文件路径。输出文件名直接是 `<组名>.patch`。

---

## 自动更新 / 发布流程

跟随策略：**跟随 `openai/codex` 最新稳定 release tag**（形如 `rust-vX.Y.Z`，
排除 alpha 预发布和历史畸形 tag）。基线锁在 `brand/BASE_SHA`（commit SHA）+
`brand/BASE_TAG`（release tag）双文件。

### 更新脚本 `scripts/update.sh`（可本地跑，CI 也复用）

流程：查上游最新 tag → 与当前 `BASE_TAG` 比对 → 切 tag + 更新
`BASE_SHA`/`BASE_TAG` → 调 `apply-patches.sh` 重放补丁。

- 无参数且已是最新 → 打印「已是最新版本」`exit 0`。
- 补丁干净重放 → `exit 0`，供后续编译发布。
- 补丁冲突 → 诊断（打印冲突补丁名 + 涉及文件 + git 报错）+ **原子回滚**（还原
  `BASE_SHA`/`BASE_TAG`/`codex` HEAD）→ `exit 1`，不继续发布。

**手动触发更新**：
```bash
scripts/update.sh              # 更新到上游最新稳定 tag
scripts/update.sh rust-v0.150.0  # 指定目标 tag（也可用于回滚/复现）
```

### 发布工作流 `.github/workflows/release.yml`

三段流水线：`detect` → `build` → `release`。

- **detect**（ubuntu）：完整克隆 codex → 调 `update.sh` 检测上游最新 release 并更新基线。
  确有基线变化才 commit + push 到 `main`。
- **build**：`if: should_release == 'true'`，复用 `build.yml`（`workflow_call`）编译三平台
  二进制（`x86_64-pc-windows-msvc` / `x86_64-apple-darwin` / `aarch64-apple-darwin`）。
- **release**：定制版本号 = 上游版本 + `-cx.N` 后缀（同上游版本再发则 N 递增）→
  `gh release create`，说明标注对应上游 tag。

**触发方式**：
- 定时：`schedule`（`cron: 37 5 * * *`，每天）自动检测。
- 手动：GitHub Actions 的 **workflow_dispatch**，可指定 `target_tag`（发指定版本）
  与 `force`（同版本强制重发）。

**冲突时如何介入**：`update.sh` 在 detect 阶段报补丁冲突（`exit 1`）时，工作流会
**自动开一个 issue**（body 含完整冲突详情 + 处理办法），随后使 job 失败中止，
build/release 因 `needs` 失败不执行——**不会发布带冲突的版本**。维护者收到 issue 后：

1. 本地 `scripts/update.sh <目标 tag>` 复现冲突，看诊断输出定位冲突补丁组与文件；
2. `scripts/apply-patches.sh` 应用能干净应用的补丁，手动在 `codex/` 内把冲突补丁的
   改动重新做到新基线上；
3. `scripts/make-patches.sh` 重新导出该补丁组 → 覆盖对应 `.patch`；
4. `scripts/test-patch-roundtrip.sh` 验证闭环无损；
5. 提交更新后的补丁 + `BASE_SHA`/`BASE_TAG`，重新触发 release（或让下次 schedule 跑）。

**token 安全**：全程只用 `secrets.GITHUB_TOKEN`；渠道 token 只在编译产物之外经 Secret
注入 `render-config.sh`，纯编译发布裸二进制，token 绝不进 git 或产物。

---

## 相关文档

- `TODO.md` —— 项目计划、决策表、目录结构、里程碑。
- `brand/SECURITY.md` —— 分发前安全清理结论（内置 token 方案、凭据剥离、gitignore 策略）。
- `brand/channel.env.example` —— 渠道真实值示例。
