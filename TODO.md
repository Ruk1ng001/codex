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
    config.template.toml    # 内置渠道模板（占位 base_url/token）✅
    patches/                # 补丁存放目录（含 patches.manifest）
    patches.manifest        # 补丁分组清单 ✅（分段格式，脚本已统一解析）
    frames/                 # 自定义启动动画（可选，暂空）
  scripts/
    common.sh               # 公共变量/函数 ✅
    reset-src.sh            # 还原 codex/ 到基线 ✅
    apply-patches.sh        # 应用补丁到基线 ✅（含前后校验）
    make-patches.sh         # 从工作区导出补丁 ✅（含导出校验）
    test-patch-roundtrip.sh # 端到端闭环测试：改动→导出→还原→重应用，不编译 ✅
  installer/                # 面向终端用户的安装器（暂空）
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

- [ ] **命令改名补丁 `01-rename-cx`**
  - `codex-rs/cli/src/main.rs:103-104`：`bin_name`、`override_usage` 中 "codex" → "cx"
  - `codex-rs/cli/src/main.rs:116 附近`：`/// Codex CLI` 顶层描述
  - `codex-cli/package.json`：npm `bin` key `codex` → `cx`（若走 npm 分发）
- [ ] **品牌层中文化补丁 `02-brand-i18n`**
  - `codex-rs/tui/src/onboarding/welcome.rs:94-99`：欢迎语品牌行
  - `codex-rs/tui/src/onboarding/auth.rs`（~35 处）：只译高频可见登录项
  - `codex-rs/tui/src/onboarding/trust_directory.rs`（~8 处）：全部译
  - `codex-rs/tui/src/chatwidget.rs:2026-2041`：`PLACEHOLDERS`(8) + `SIDE_PLACEHOLDERS`(3)
  - （可选）`codex-rs/core/src/default_client.rs`：`DEFAULT_ORIGINATOR` 改品牌标识
  - ⚠️ 改字符串会波及 `#[cfg(test)]` 快照测试（`.snap`），release 打包不跑这些测试即可

### 🟡 P1 — 内置渠道（方案 A：纯配置注入，不改源码）

- [ ] 确定占位符替换机制：打包时把 `config.template.toml` 里
  `__BASE_URL__` / `__TOKEN__` / `__MODEL__` 替换成真实值
- [ ] 首启动写入逻辑（放在安装器里）：检查 `~/.codex/config.toml`，
  不存在或缺 `[model_providers.newapi]` 则写入；幂等，不覆盖用户修改

### 🟢 P2 — CI 与分发

- [ ] **GitHub Actions CI**（`.github/workflows/`）
  - checkout 官方仓库到锁定 SHA → `apply-patches.sh` → 多平台编译
  - 目标平台：`x86_64-pc-windows-msvc`、`x86_64-apple-darwin`、`aarch64-apple-darwin`
  - token 通过 GitHub Secret 注入，**绝不提交进仓库**
  - 产物：`cx.exe`（Win）、`cx`（Mac x64/arm64）
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
- [ ] **M1 编译验证**：交给 CI（本机不跑重编译）
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
