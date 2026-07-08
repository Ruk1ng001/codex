# 分发前安全清理 —— 结论与规范（US-014，对应已知问题 #2）

本文件是「内置 token 与敏感凭据如何安全分发」的**决策结论**，也是分发前的核对清单。

---

## 一、内置渠道 token 方案（结论）

**结论：不使用个人主 key，采用「受限额度 / 每用户发放」的独立 key。**

内置 token 会随分发包落到每一台用户机器，等同**公开**——任何用户都能从
`~/.codex/config.toml`（或安装包里的成品 config）读出它。因此内置 token 必须满足：

| 要求 | 说明 |
|---|---|
| **绝不用个人主 key** | 主 key 一旦泄漏波及全部额度与账号，且无法单独吊销某个用户。 |
| **受限额度 key（最低要求）** | 在 new-api 后台为分发单独建一个 key，设**额度上限 / 速率限制 / 模型白名单**，泄漏损失可控、可随时吊销重发。 |
| **每用户独立 key（推荐，需后端支持）** | 首启动时由发放服务给每台机器换一个独立 key；可按用户吊销、审计、限流。当前免登录方案（`experimental_bearer_token`）是**单一内置 key**，要做到每用户独立需后端提供换 key 接口，属后续增强，不在本故事实现。 |

**当前落地**：内置 key 走「受限额度 key」——真实值不写进仓库任何文件，只在**打包期**
由 `render-config.sh` 从 CI Secret / 本地 `brand/channel.env` 注入到成品 config。
换 key / 吊销只改 CI Secret（`CX_TOKEN`）或本地 `channel.env`，模板与源码都不动。

---

## 二、token 绝不进 git（已核实）

- `.claude/settings.json`（agent 运行时凭据，含 `ANTHROPIC_AUTH_TOKEN` 与中转地址）
  **从未进入任何 git 提交**，且 `.claude/` 从未被跟踪——已用全历史 blob 扫描确认（见下方核对命令）。
- 渠道真实 token 只存在于 `.gitignore` 忽略的文件里：`brand/channel.env`（本地）、
  `brand/config.toml` / `dist/` / `installer/config.toml`（渲染产物）。仓库里只有占位符
  （`config.template.toml` 的 `__TOKEN__`）和假值示例（`channel.env.example`）。
- CI 里 token 只经 GitHub Actions **Secret** 以环境变量注入 `render-config.sh`，从不 echo、不落 git。

### 核对命令（分发前跑一遍，应无真实 token 命中）

```sh
# 1. 全历史所有 blob 扫描真实 token / 中转地址（应无输出）
git rev-list --all --objects | awk '{print $1}' | sort -u | \
  git cat-file --batch 2>/dev/null | grep -aiE 'sk-[A-Za-z0-9]{20,}|997269\.xyz' && echo "⚠️ 命中！" || echo "✓ 全历史无真实 token"

# 2. 当前跟踪文件扫描（应无输出）
git grep -nE 'sk-[A-Za-z0-9]{20,}|997269\.xyz' -- . ':!*.example' && echo "⚠️ 命中！" || echo "✓ 跟踪文件无真实 token"

# 3. .claude 是否曾被跟踪（应报「从未被跟踪」）
[ -z "$(git log --all --oneline -- .claude)" ] && echo "✓ .claude 从未被跟踪" || echo "⚠️ .claude 曾被跟踪！"
```

---

## 三、产品包剥离敏感凭据（结论）

- **`.claude/settings.json`** 是本仓 agent 的运行时配置，含 `ANTHROPIC_AUTH_TOKEN`
  与中转地址 `ANTHROPIC_BASE_URL`。它已被 `.gitignore` 忽略，**不在 git、不在产品包**：
  - CI 从 git checkout 构建（`build.yml`/`release.yml`），被忽略文件根本不存在于 checkout 中；
  - 产品包 = 编译出的裸二进制 `cx` + `render-config.sh` 渲染的成品 config（只含渠道 token，
    与 `.claude` 的 Anthropic token 无关）。
  - 结论：**无需从产品包剥离——它本就进不了产品包。** 只需保证 `.claude/` 持续在 `.gitignore` 里。
- 编译产物是裸二进制，不嵌入任何 token；渠道 token 只在成品 config 里，由安装器写入用户
  `~/.codex/config.toml`（US-008 幂等写入）。

---

## 三·五、打包期把成品 config 嵌入安装包（US-016）

原生安装包（`.pkg`/`.msi`）追求「装完即用、无需外部脚本」，因此成品 config 必须
**随包分发**。这带来三条必须守住的安全约定，均已在 `release.yml` 的
`package_macos`/`package_windows`/`release` 三个 job 里落实为 CI 强制守卫：

| 约定 | 落地方式 |
|---|---|
| **渠道值只经 Secret 注入，绝不进 git / CI 日志明文** | 渲染前先 `::add-mask::` 把 `CX_TOKEN`/`CX_BASE_URL`/`CX_MODEL` 登记为 GitHub Actions 掩码——即便后续任何步骤意外回显，日志里也只显示 `***`。`render-config.sh` 本身也从不 echo 值。 |
| **成品 config 只藏在安装包内部，绝不作为独立可下载资产** | 打包完成后、上传 artifact **之前**删除渲染出的裸 `dist/config.toml` 并断言其不存在；`upload-artifact` 的 `path` 只匹配 `cx-*.pkg`/`cx-*.msi`；`release` job 归置资产后再兜底断言 `release-assets/` 无任何 `*.toml`。三道守卫任一触发即 `exit 1` 中止发布。 |
| **换渠道零改脚本** | 复用 US-007 的 `render-config.sh` + `PLACEHOLDER_VARS`，换 key 只改 CI Secret（`CX_TOKEN` 等），打包脚本本体（`build-pkg.sh`/`build-msi.ps1`）与模板都不动。 |

> 成品 config 含 token 是敏感文件：`build-pkg.sh` 用 `install -m 0600` 复制进 pkg
> scripts 段，`.msi` 装到用户 `%LOCALAPPDATA%`（NTFS 默认仅该用户可读）。安装后由
> `write-default-config.*`（US-008）幂等写入用户 `~/.codex/config.toml`，不覆盖已有配置。

---

## 四、`.gitignore` 覆盖的含密文件（本故事补全）

| 规则 | 覆盖对象 |
|---|---|
| `/brand/channel.env` | 渠道真实值（本地打包用） |
| `/brand/config.toml`、`/dist/`、`/installer/config.toml` | 渲染产物（本地 config 实例，含真实 token） |
| `auth.json` | codex 登录后写的凭据文件（access token / API key） |
| `.env`、`*.env` | 通用环境变量文件（`*.env` 不匹配 `*.env.example`，示例仍跟踪） |
| `*.pem`、`*.key`、`id_rsa*` | 私钥 / 证书 |
| `.chief/`、`.claude/` | 本地工作文件 / agent 运行时凭据 |

验证：`git check-ignore <file>` 命中含密文件、不命中 `*.example` 与源码。
