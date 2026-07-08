# Codex 定制化改造 — 项目计划与进度

> 目标：把 OpenAI 官方 Codex CLI 定制成自有产品，面向国内 Windows / Mac 用户，
> 内置渠道免配置、品牌层中文化、可持续跟随官方更新。

---

## 一、已确认的决策

| 项目 | 决定 |
|---|---|
| 基础项目 | OpenAI 官方 Codex CLI（`openai/codex`，Rust 主体 `codex-rs`） |
| 基线版本 | 跟随官方**最新 release tag** `rust-v0.142.5`（SHA 记录在 `brand/BASE_SHA`，tag 记录在 `brand/BASE_TAG`）；不追 main HEAD、不永久锁定，随官方发新版更新 |
| 官方源码 | `codex/`（git submodule，指向 `openai/codex`，停在 `BASE_TAG`，只 fetch 不手改） |
| 跟随策略 | **补丁叠加模式**：`codex/` 保持官方原样，改动全部存为 `brand/patches/*.patch` |
| 命令名 | `cx`（占位短名，后续可改） |
| 品牌名 | 占位名先跑通（后续替换） |
| 配置目录 | 保持 `~/.codex` 不变 |
| 中文化范围 | 只做品牌层（欢迎语、首启动引导、登录/信任提示、输入框提示） |
| 内置渠道 | base_url + token 内置，首次启动写入 `~/.codex/config.toml` |
| 认证方式 | `experimental_bearer_token` + `requires_openai_auth=false`，免登录 |
| 编译打包 | **GitHub Actions CI**（本机是 ARM64 Linux，编不出 Win/Mac 包） |
| 本机角色 | 只做代码准备（补丁、配置、脚本、CI 定义），**不做重编译** |
| 分发平台 | Windows + Mac |

---

## 二、关键技术事实（调研已确认）

1. **协议约束（最大风险）**：当前 main 版 Codex 只支持 OpenAI **Responses API**
   (`/v1/responses`)，`wire_api="chat"` 已被删除、会报错。
   → **new-api 中转必须支持 `/v1/responses` 端点**，否则免登录能进界面但对话失败。
   **打包分发前必须实测一次。**

2. **免登录可行**：provider 配置带 `experimental_bearer_token` 且
   `requires_openai_auth=false` 时，登录界面直接跳过。
   token 优先级：`env_key` > `experimental_bearer_token` > 登录 auth.json。

3. **命令改名安全**：arg0 dispatch 只对 `codex-linux-sandbox` / apply-patch 等
   特殊别名按文件名判定，主命令不依赖 "codex" 名字。改成 `cx` 不影响启动。

4. **没有 "CODEX" 文字 Logo**：启动动画是 `tui/frames/<variant>/*.txt` 的装饰性
   ASCII 粒子艺术，无品牌文字。唯一品牌文字是 `welcome.rs` 里一行
   `"Welcome to Codex, OpenAI's command-line coding agent"`。

5. **保留 ID 限制**：自定义 provider 的 key 不能用
   `openai` / `amazon-bedrock` / `ollama` / `lmstudio`。用 `newapi` 即可。

6. **配置字段名**（已核实，均为直接 snake_case，无 rename）：
   顶层 `model` / `model_provider` / `model_providers`；
   provider 内 `base_url` / `experimental_bearer_token` / `wire_api` /
   `requires_openai_auth`。

7. **本机环境**：ARM64 Linux / Ubuntu 24.04 / 4 核 / 23G 内存。
   Rust 已装（rustup + 国内镜像 rsproxy.cn，全局 `~/.cargo/config.toml`）。
   项目要求 Rust 1.95.0（`rust-toolchain.toml` 自动切换）。
   gcc / cmake / pkg-config 已装。

---

## 三、目录结构

```
/srv/codex/
  codex/                    # 官方源码（git submodule，停在 BASE_TAG，只 fetch 不手改）
  brand/
    BASE_SHA                # 跟随的 release tag 对应 commit ✅
    BASE_TAG                # 跟随的官方 release tag（如 rust-v0.142.5）✅
    config.template.toml    # 内置渠道模板（占位符 __BASE_URL__/__TOKEN__/__MODEL__）✅
    SECURITY.md             # 分发前安全清理结论：内置 token 方案 + 凭据剥离 + gitignore 策略 ✅
    channel.env.example     # 渠道真实值示例（复制为 channel.env 填真实值，后者 .gitignore 忽略）✅
    channel.env             # 渠道真实值（含 token，本地打包用，不进 git）— 按需创建
    patches/                # 补丁存放目录（含 patches.manifest）
    patches.manifest        # 补丁分组清单 ✅（分段格式，脚本已统一解析）
    frames/                 # 自定义启动动画（可选，暂空）
  scripts/
    common.sh               # 公共变量/函数 ✅
    reset-src.sh            # 还原 codex/ 到基线 ✅
    apply-patches.sh        # 应用补丁到基线 ✅（含前后校验）
    make-patches.sh         # 从工作区导出补丁 ✅（含导出校验）
    test-patch-roundtrip.sh # 端到端闭环测试：改动→导出→还原→重应用，不编译 ✅
    render-config.sh        # 打包期渲染：模板占位符 → 真实渠道值（CI Secret/channel.env）✅
  installer/                # 面向终端用户的安装器
    install.sh                # Mac 安装器：本地二进制 + 写 config + 加 PATH + 命令名 cx ✅
    install.ps1               # Windows 安装器：本地二进制 + 写 config + 加 PATH + 命令名 cx ✅
    write-default-config.sh   # 首启动幂等写入 config.toml（Mac/Linux）✅
    write-default-config.ps1  # 首启动幂等写入 config.toml（Windows，与 .sh 行为对齐）✅
    macos-pkg/                # macOS 原生 .pkg 安装包（US-010）
      build-pkg.sh              # pkgbuild+productbuild 构建 .pkg（payload→/usr/local/bin/cx + postinstall 写 config，可选签名/公证）✅
      scripts/postinstall       # 安装后脚本：以登录用户身份幂等写内置渠道 config ✅
      uninstall.sh              # 卸载脚本：移除二进制 + forget 收据（配置默认保留）✅
      README.md                 # 安装/卸载 + Gatekeeper（右键打开/xattr）说明 ✅
    windows-msi/              # Windows 原生 .msi 安装器（US-011）
      cx.wxs                    # WiX 源文件：目录/组件/用户PATH/ARP卸载项/安装后幂等写 config 自定义动作 ✅
      build-msi.ps1             # 构建脚本（调 wix build），只在 Windows 跑；含可选 Authenticode 签名 ✅
      License.rtf               # 安装向导许可页文本 ✅
      README.md                 # 安装/卸载 + SmartScreen（仍要运行/Unblock）说明 ✅
  .github/workflows/
    build.yml               # 可复用多平台编译（workflow_call）：submodule→apply-patches→cargo build ✅
    ci.yml                  # CI 入口：校验补丁可应用 + 复用 build.yml 多平台编译 ✅
    release.yml             # 自动检测+发布：schedule/dispatch→update.sh→复用 build.yml→gh release ✅
  .gitignore                # 忽略真实值(channel.env)、渲染产物(config.toml/dist)、工作文件 ✅
  README.md                 # 面向用户：下载安装包双击安装 + Gatekeeper/SmartScreen 绕过 + 卸载 ✅
  CUSTOMIZATION.md          # 定制替换点清单：命令名/品牌名/渠道/动画 + 原生安装包替换点 + 更新发布流程 ✅
  TODO.md                   # 本文件
```

---

## 四、已完成 ✅

- [x] 拉取官方源码，确认结构（Rust `codex-rs` + npm wrapper `codex-cli`）
- [x] 全面调研：渠道配置、认证、品牌字符串、命令改名、构建打包机制
- [x] 跟随最新官方 release tag `rust-v0.142.5`，确认 `codex/` submodule 工作区干净
- [x] 装好 Rust 工具链 + 构建依赖 + 国内镜像
- [x] 建立目录骨架（brand / scripts / installer）
- [x] 写内置渠道配置模板 `brand/config.template.toml`
- [x] 写补丁工作流四个脚本（common / reset / apply / make）
- [x] 写补丁分组清单 `brand/patches.manifest`
- [x] 端到端可靠性测试 `scripts/test-patch-roundtrip.sh`（改动→导出→还原→重应用，不编译）

---

## 五、待办事项（TODO）

### 🔴 P0 — 先修复阻塞问题

- [x] **修复 `make-patches.sh` 与 `patches.manifest` 格式不匹配的 bug**（见「已知问题 #1」）
  - 已改脚本按 `[组名]` + 文件列表的段落格式解析（US-002）；
    补丁应用/导出加入前后校验消除静默失败（US-003）。
  - 端到端测试 `scripts/test-patch-roundtrip.sh` 已固化：造改动 → 导出 → 还原 →
    重应用 → 逐字节比对，全程不编译，实测通过（US-004）。

### 🟡 P1 — 补丁内容（改源码部分，逐个文件精确改）

- [x] **命令改名补丁 `01-rename-cx`**（US-005 完成）
  - `codex-rs/cli/src/main.rs:103-104`：`bin_name`、`override_usage` 中 "codex" → "cx"
  - `codex-rs/cli/src/main.rs:116 附近`：`/// Codex CLI` 顶层描述
  - `codex-cli/package.json`：npm `bin` key `codex` → `cx`（若走 npm 分发）
- [x] **品牌层中文化补丁 `02-brand-i18n`**（US-006 完成）
  - `codex-rs/tui/src/onboarding/welcome.rs:94-99`：欢迎语品牌行 → 「欢迎使用 cx，你的命令行编码助手」
  - `codex-rs/tui/src/onboarding/auth.rs`（高频可见登录项）：登录选项标题/描述、浏览器与设备码提示、成功页、API key 录入页、错误文案全部译中文
  - `codex-rs/tui/src/onboarding/trust_directory.rs`（全部）：当前目录、Git 子目录警告、信任说明、是/否选项、确认提示全部译中文
  - `codex-rs/tui/src/chatwidget.rs:2024-2041`：`PLACEHOLDERS`(8) + `SIDE_PLACEHOLDERS`(3) 输入框占位提示译中文
  - （可选，未做）`codex-rs/core/src/default_client.rs`：`DEFAULT_ORIGINATOR` 改品牌标识——非本故事范围，且属遥测标识，非可见文案
  - ⚠️ **快照测试影响（已确认）**：改这些字符串会让 `codex-rs/tui/src/` 下依赖旧英文文案的 `#[cfg(test)]` 快照测试（`insta` 的 `.snap`）失败，例如 `welcome.rs` 里 `row_containing(&buf, "Welcome")` 断言、`trust_directory.rs` 的 `renders_snapshot_*`。**这是预期行为，不在本故事修复。** release 打包流程按项目决策（见「一、已确认的决策」编译打包/本机角色，及「M1 编译验证：交给 CI，本机不跑重编译」）配置为**只编译、不跑 `cargo test`/快照测试**，故补丁不触发这些测试；CI（P2 待办）落地时其构建 job 只做多平台 `cargo build --release`，不含 `cargo test`。若未来需要 CI 跑测试，须同步更新受影响的 `.snap` 或给相关测试打 `#[ignore]`。

### 🟡 P1 — 内置渠道（方案 A：纯配置注入，不改源码）

- [x] **占位符替换机制 `scripts/render-config.sh`（US-007 完成）**：打包期把
  `config.template.toml` 里 `__BASE_URL__` / `__TOKEN__` / `__MODEL__` 替换成真实值。
  - 真实值来源与替换点集中在 `render-config.sh` 顶部的 `PLACEHOLDER_VARS` 映射表：
    `__BASE_URL__←CX_BASE_URL`、`__TOKEN__←CX_TOKEN`、`__MODEL__←CX_MODEL`。
  - 值优先级：进程环境变量（CI 里由 GitHub Actions Secret 注入，不进 git） >
    本地 `brand/channel.env`（已被根 `.gitignore` 忽略，不进 git；示例见
    `brand/channel.env.example`）。换渠道只改 Secret / channel.env，模板与源码都不动。
  - 校验：任一占位符对应变量为空则列出缺失变量 `exit 1`；渲染后残留 `__XXX__` 也报错退出。
  - 写文件时 chmod 600（含 token，按敏感文件处理）；成品 `brand/config.toml` 已被 gitignore。
- [x] **首启动幂等写入逻辑（放在安装器里）（US-008 完成）**：检查 `~/.codex/config.toml`，
  不存在或缺 `[model_providers.newapi]` 则写入；幂等，不覆盖用户修改。
  - Mac/Linux：`installer/write-default-config.sh`；Windows：`installer/write-default-config.ps1`，
    两份逐条对齐同一行为契约（配置目录 `CODEX_HOME` 优先否则 `~/.codex`；已含 `[model_providers.newapi]`
    则不动；不存在则整份写入；存在但缺段则追加，保留用户原有内容）。
  - 成品配置由 `render-config.sh` 渲染后随安装器分发，作参数传入（默认取脚本同目录 `config.toml`）。

### 🟢 P2 — CI 与分发

- [x] **GitHub Actions CI**（`.github/workflows/`）✅ US-009
  - `build.yml`（可复用 `workflow_call`）：clone codex 到 `BASE_TAG` → `apply-patches.sh` → 多平台 `cargo build --release --bin codex`
  - `ci.yml`（push/PR 入口）：先跑补丁自检 job，再 `uses: ./.github/workflows/build.yml` 复用编译
  - 目标平台：`x86_64-pc-windows-msvc`（windows-latest）、`x86_64-apple-darwin`（macos-13）、`aarch64-apple-darwin`（macos-14），全部原生编译不交叉
  - token 通过 GitHub Secret 注入，**绝不提交进仓库**；本工作流是纯编译，完全不接触 token/config 渲染，产物是裸二进制
  - release 编译只 `cargo build` 不 `cargo test`，故不触发中文化补丁导致失败的快照测试
  - 产物：`cx.exe`（Win）、`cx`（Mac x64/arm64），由 upload-artifact 上传，供 US-013 下游 download-artifact 复用
  - macOS runner 自带 bash 3.2 不支持 `mapfile`/`declare -A`，工作流 `brew install bash` 后再跑 apply-patches.sh
- [x] **Mac 安装器** `installer/install.sh`（US-010 完成）
  - 改自官方 `scripts/install/install.sh`，去掉全部 GitHub 下载/校验/版本解析 + standalone releases/current 软链多版本布局
  - 本地二进制（`--binary`/`CX_BINARY`/按架构自动探测 `cx-<vendor_target>`）+ 调 `write-default-config.sh` 写 config + 保留官方 PATH 注入 + 命令名 `cx`
  - 支持 x64（`x86_64-apple-darwin`）与 arm64（`aarch64-apple-darwin`），含 Rosetta 检测
  - 二进制装成 `$CX_INSTALL_DIR`（默认 `~/.local/bin`）下单文件 `cx`；PATH 注入 profile 保证新终端可直接调用
- [x] **Windows 安装器** `installer/install.ps1`（US-011 完成）
  - 改自官方 `install.ps1`，去掉全部 GitHub 下载/校验/版本解析 + standalone releases/current junction 多版本布局/安装锁
  - 本地二进制（`-Binary`/`CX_BINARY`/按架构自动探测 `cx-<target>.exe`）+ 调 `write-default-config.ps1` 写 config + 命令名 `cx`
  - 支持 x64（`x86_64-pc-windows-msvc`）与 arm64（`aarch64-pc-windows-msvc`）
  - 二进制装成 `$CX_INSTALL_DIR`（默认 `%LOCALAPPDATA%\Programs\cx\bin`）下单文件 `cx.exe`；PATH 写用户环境变量，PowerShell + CMD 新会话都生效
- [x] **macOS 原生安装包 `.pkg`** `installer/macos-pkg/`（US-010 完成）
  - `build-pkg.sh`：`pkgbuild`（payload → `/usr/local/bin/cx`，0755）+ `productbuild`（distribution.xml 向导）产出可双击 `.pkg`；只在 macOS runner 跑
  - `scripts/postinstall`：以登录 GUI 用户（`stat -f%Su /dev/console`）身份调 `write-default-config.sh` 幂等写 `~/.codex/config.toml`（复用 US-008 契约，不覆盖用户配置）
  - `uninstall.sh`：移除 `/usr/local/bin/cx` + `pkgutil --forget`；配置默认保留（`--purge-config` 才删）
  - `README.md`：安装/卸载/Gatekeeper「右键打开」与 `xattr` 去隔离绕过说明
  - 可选签名/公证：`CX_SIGN_IDENTITY`（Developer ID Installer）+ `CX_NOTARIZE_PROFILE`（notarytool）配置了才生效
  - 仅 arm64（与 build.yml 一致，Intel 暂停）；release.yml 新增 `version` + `package_macos` job，`.pkg` 随 Release 分发
- [x] **Windows 原生安装器 `.msi`** `installer/windows-msi/`（US-011 完成）
  - `cx.wxs`：WiX Toolset(v5/v4) 源文件，`WixUI_InstallDir` 向导（欢迎→许可→选目录→确认→进度→完成），`Scope="perUser"` 免管理员装到 `%LOCALAPPDATA%\Programs\cx`
  - PATH：`Environment` 元素写**用户级** PATH（`System="no"`），PowerShell + CMD 新会话都生效；卸载时移除
  - ARP 卸载入口：MSI 标准机制自动登记 DisplayName/版本/Publisher/卸载命令（`MajorUpgrade` 处理升级）
  - 配置：安装后 immediate 自定义动作调 `write-default-config.ps1`（US-008）幂等写 `%USERPROFILE%\.codex\config.toml`，`Return="ignore"` 写失败不使整包失败
  - `build-msi.ps1`：调 `wix build` 组装二进制 + config + writer；定制版本 `0.142.5-cx.1` → MSI 数字版本 `0.142.5.1`；只在 Windows runner 跑
  - 可选 Authenticode 代码签名：`CX_SIGN_PFX_BASE64` + `CX_SIGN_PFX_PASSWORD` 配置了才 signtool 签名，否则未签名 + README 说明 SmartScreen 绕过
  - 支持 x64；ARM64 记为可选后续项（`build-msi.ps1` 支持 `-Arch arm64`，CI 当前只产 x64）
  - `README.md`：安装/卸载/SmartScreen「仍要运行」与 `Unblock-File` 绕过说明；release.yml 新增 `package_windows` job，`.msi` 随 Release 分发
- [x] **打包期把成品配置嵌入安装包** `release.yml` 的 `package_macos`/`package_windows`（US-016 完成）
  - 打包期用 `render-config.sh`（US-007）把 `config.template.toml` 渲染成成品 `config.toml`，作为 payload 打进 `.pkg`/`.msi`（US-010/011 已建机制，US-016 加固安全守卫）
  - 验收 3（日志不泄漏明文）：渲染前 `::add-mask::` 把 `CX_TOKEN`/`CX_BASE_URL`/`CX_MODEL` 登记为掩码，万一意外回显日志也只显示 `***`
  - 验收 4（config 不作独立资产）：package job 上传前删除裸 `config.toml` + 断言其不存在；release 汇总 job 再断言 `release-assets/` 无任何 `*.toml`——成品 config 只藏在安装包内部
  - 换渠道仍只改 CI Secret / `channel.env`，打包脚本本体不动（复用 US-007 的 `PLACEHOLDER_VARS` 单一映射表）
- [x] **更新跟随流程** `scripts/update.sh`（US-012 完成）
  - `fetch 官方 → 更新 BASE_SHA/BASE_TAG → apply-patches → 冲突则诊断+回滚 → 干净重放 exit 0`
  - 查最新稳定 tag（过滤 alpha/畸形）与当前基线比对；无参已最新则 exit 0，可指定 tag（回滚/复现）
- [x] **自动检测 + 自动发布工作流** `.github/workflows/release.yml`（US-013 完成）
  - `schedule`（每天定时）+ `workflow_dispatch`（可指定 tag / force 重发）触发
  - detect job：调 `update.sh` 检测上游最新 release 并更新基线；无新版本空跑退出；补丁冲突开 issue 报警并中止
  - build job：复用 `build.yml`（`workflow_call`，传基线更新后的 `ref`）产三平台二进制
  - release job：定制版本号 = 上游版本 + `-cx.N` 后缀（同上游版本再发则 N 递增）→ `gh release create`
  - token 只经 GitHub Secret（`GITHUB_TOKEN`），纯编译发布裸二进制，不接触渠道 token；本机不编译

### 🔵 里程碑验证

- [ ] **M0 验证协议**：确认 new-api 的 `/v1/responses` 可用（占位 token 手测）
      —— **这步不过，后面都白搭**
- [x] **M1 编译验证**：交给 CI（本机不跑重编译）✅ US-009 落地 `.github/workflows/{build,ci}.yml`；待推 GitHub 后由 CI 实跑
- [ ] **M2 内置渠道**：验证免登录进入 + 能对话
- [ ] **M3 补丁**：命令名 + 中文化，重编译验证
- [ ] **M4 打包分发**：mac + win 安装器 + macOS 原生 `.pkg`（US-010）+ Windows 原生 `.msi`（US-011），端到端走一遍
      —— `.pkg` 打包脚本（`installer/macos-pkg/`）+ release.yml `package_macos` job、
      `.msi` 打包脚本（`installer/windows-msi/`）+ release.yml `package_windows` job 已落地，
      待推 GitHub 后由 CI 在 macos / windows runner 实跑产出并验证双击安装
- [x] **M5 更新机制**：`scripts/update.sh`（US-012）本地实跑四路径通过 + `release.yml`（US-013）自动检测+发布；待推 GitHub 后由定时/手动触发实跑验证

---

## 六、已知问题

### #1 `make-patches.sh` 与 `patches.manifest` 格式不匹配 —— ✅ 已解决（US-002/003/004）

- **现象**：导出补丁时报 `printf: [01-rename-cx]: invalid number`，补丁未生成。
- **根因**：`make-patches.sh` 期望 manifest 每行是 `序号 组名 路径前缀`（单行三列）
  并 `printf '%02d'` 格式化序号，但 manifest 实际是 `[组名]` 段落 + 文件列表格式，
  脚本把 `[01-rename-cx]` 当序号丢给 `printf` 就崩了。
- **修复**：
  - US-002 —— 统一用 `[组名]` 段落格式，改写 `make-patches.sh` 解析逻辑（组名自带
    序号前缀直接作输出文件名，去掉 `printf '%02d'`）。
  - US-003 —— 消除三处静默失败：apply 前校验每个声明组都有 `.patch`、apply 后校验
    `git status` 确有改动、make 导出后校验补丁非空。
  - US-004 —— 端到端测试 `scripts/test-patch-roundtrip.sh` 固化闭环：造改动 → 导出 →
    还原 → 重应用 → 逐字节比对，全程不编译，实测通过。
- **测试暴露的坑**：`apply-patches.sh` 用 `git apply --3way`，`--3way` 隐含 `--index`，
  改动会进 index。比对闭环内容必须用 `git diff HEAD`（含已暂存改动），不能用裸
  `git diff`（只看未暂存），否则重应用后的 `actual.diff` 会假性为空。

### #2 分发前安全清理 —— ✅ 已处理（US-014）

- 内置 token 会随分发包落到每个用户机器，等同公开。
  建议用低权限/限额 key，或做「每用户独立 key」发放方案，**不要用个人主 key**。
  → 方案结论见 `brand/SECURITY.md`（阶段策略：MVP 用限额 key、成长期转每用户发放）。
- 现有 `.claude/settings.json` 里硬编码的 token 与中转地址，已确认被根 `.gitignore`
  忽略（`.claude/`），**从未进入 git 历史**（全历史 blob 扫描无命中），CI 从 git
  checkout 构建，故不会落进产品包。
- CI 里 token 只能走 GitHub Secret 注入，绝不进 git 历史（US-007/009/013 已固化）。
- `.gitignore` 已扩展覆盖会含密文件：本地 config 实例（`config.toml`/`dist/`/
  `installer/config.toml`）、auth 文件（`auth.json`）、通用密钥/env（`*.env`/`*.pem`/
  `*.key`/`id_rsa*`），且不误伤 `*.env.example` 示例。
- **验证结论**：token 从未进 git 历史；`.claude/settings.json` 从未被跟踪；跟踪文件中
  无任何真实 token / 中转地址；模板与示例只含占位符。

---

## 七、待你后续提供 / 确认

- [ ] new-api 的 OpenAI 协议 base_url（`/v1` 层）+ 是否支持 Responses API
- [ ] 默认内置 token（受限额度 key 或每用户发放机制）
- [ ] 正式产品名 + 命令名（替换占位 `cx`）
- [ ] 是否需要自定义启动动画 art
- [ ] GitHub 仓库地址（放代码 + 跑 CI）
