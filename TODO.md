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
    write-default-config.sh   # 首启动幂等写入 config.toml（Mac/Linux）✅
    write-default-config.ps1  # 首启动幂等写入 config.toml（Windows，与 .sh 行为对齐）✅
  .github/workflows/
    build.yml               # 可复用多平台编译（workflow_call）：submodule→apply-patches→cargo build ✅
    ci.yml                  # CI 入口：校验补丁可应用 + 复用 build.yml 多平台编译 ✅
  .gitignore                # 忽略真实值(channel.env)、渲染产物(config.toml/dist)、工作文件 ✅
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
- [ ] **Mac 安装器** `installer/install.sh`
  - 改自官方 `scripts/install/install.sh`，去掉 GitHub 下载逻辑
  - 本地二进制 + 写 config + 加 PATH + 命令名 `cx`
- [ ] **Windows 安装器** `installer/install.ps1`
  - 改自官方 `install.ps1`，放二进制 + 加 PATH + 写 config
- [ ] **更新跟随流程** `scripts/update.sh`
  - `fetch 官方 → 更新 BASE_SHA → apply-patches → 冲突则手改后 make-patches → 提交`

### 🔵 里程碑验证

- [ ] **M0 验证协议**：确认 new-api 的 `/v1/responses` 可用（占位 token 手测）
      —— **这步不过，后面都白搭**
- [x] **M1 编译验证**：交给 CI（本机不跑重编译）✅ US-009 落地 `.github/workflows/{build,ci}.yml`；待推 GitHub 后由 CI 实跑
- [ ] **M2 内置渠道**：验证免登录进入 + 能对话
- [ ] **M3 补丁**：命令名 + 中文化，重编译验证
- [ ] **M4 打包分发**：mac + win 安装器，端到端走一遍
- [ ] **M5 更新机制**：模拟一次官方更新，验证补丁重放

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

### #2 安全提醒（分发前必处理）

- 内置 token 会随分发包落到每个用户机器，等同公开。
  建议用低权限/限额 key，或做「每用户独立 key」发放方案，**不要用个人主 key**。
- 现有 `.claude/settings.json` 里硬编码的 token 与中转地址，分发前需从产品包剥离。
- CI 里 token 只能走 GitHub Secret 注入，绝不进 git 历史。

---

## 七、待你后续提供 / 确认

- [ ] new-api 的 OpenAI 协议 base_url（`/v1` 层）+ 是否支持 Responses API
- [ ] 默认内置 token（受限额度 key 或每用户发放机制）
- [ ] 正式产品名 + 命令名（替换占位 `cx`）
- [ ] 是否需要自定义启动动画 art
- [ ] GitHub 仓库地址（放代码 + 跑 CI）
