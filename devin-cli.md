# Devin CLI 安装与登录指南

Devin CLI 是 Cognition 出的**本地命令行编码 agent**（与云端的 Devin 是两个工具）。
官方文档：<https://docs.devin.ai/cli>

---

## 1. 安装

### macOS / Linux / WSL（官方脚本）

```bash
curl -fsSL https://cli.devin.ai/install.sh | bash
```

脚本行为（已审阅，安全）：

1. 识别平台（本机为 `x86_64-unknown-linux`）
2. 从 `https://static.devin.ai/cli/current/manifest.json` 取版本与下载地址
3. 下载 tar.gz，**用 sha256 校验**（校验失败会中止）
4. 解压到 `~/.local/share/devin/cli/_versions/<版本>/`
5. 软链 `~/.local/bin/devin` → `current/bin/devin`
6. 运行 `devin setup`（交互式登录，见下）

### 其它方式

| 平台 | 命令 |
|---|---|
| macOS (Homebrew) | `brew install --cask devin-cli` |
| Windows (PowerShell) | `irm https://static.devin.ai/cli/setup.ps1 \| iex` |
| Devin Desktop 用户 | 命令面板执行 **Install Devin CLI** |

### 安装位置（本机实际）

| 项 | 值 |
|---|---|
| 可执行文件 | `~/.local/bin/devin`（软链） |
| 真实文件 | `~/.local/share/devin/cli/_versions/<版本>/bin/devin` |
| 版本 | `devin --version` |
| 安装级别 | **用户级**（不要用 root 装） |

---

## 2. 让 `devin` 进入 PATH

Debian 的 `~/.profile` 默认已包含：

```bash
if [ -d "$HOME/.local/bin" ] ; then
    PATH="$HOME/.local/bin:$PATH"
fi
```

所以**重新登录后**即可直接使用。当前已开的 shell 手动执行：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

---

## 3. 登录 / 初始化

> ⚠️ **登录必须交互式**。在没有 TTY 的环境（脚本、CI、`su -c` 管道）里会报 `Error: Login canceled`，这是正常的。

在你的 SSH 终端里执行任一：

```bash
devin auth login     # 只登录
devin setup          # 交互式初始化向导（含登录，推荐首次使用）
```

常用认证命令：

```bash
devin auth status    # 查看登录状态
devin auth logout    # 登出
```

### 登录流程
1. 命令会给出一个 URL / 打开浏览器
2. 在浏览器完成 Cognition 账号授权
3. 回到终端确认，凭据保存在 `~/.local/share/devin/` 下

### 自检

```bash
devin doctor         # 检查本地配置 / 网络等
```

---

## 4. 代理说明

Devin CLI 是 Rust 程序，其 HTTP 客户端（reqwest）**默认读取以下环境变量**：

```
http_proxy  https_proxy  all_proxy  no_proxy
（大小写均可）
```

本机已通过 [`apply-proxy.sh`](apply-proxy.sh) 全局配置这些变量，因此：

- **登录、联网、拉模型列表会自动走代理**；
- `no_proxy` 已包含私有网段/环回，内网访问不受代理影响；
- 若在 systemd 服务/无环境变量的场景下运行，需要显式传入代理变量。

---

## 5. 常用命令

```bash
devin                              # 在当前目录启动
devin -- "实现 xx 功能"            # 带初始提示（自动化）
devin list                         # 列出当前目录的会话（别名 ls）
devin models                       # 查看可用模型
devin mcp                          # 连接 MCP server
devin skills / devin plugins       # 管理技能/插件
devin cloud                        # 管理 Devin Cloud 资源
devin ssh / devin forward          # 连云端会话 / 端口转发
devin update                       # 升级到最新版
devin uninstall                    # 卸载并清理数据
devin --help                       # 全部命令
```

---

## 6. 故障排查

| 现象 | 处理 |
|---|---|
| `devin: command not found` | 未重登录或 PATH 未含 `~/.local/bin`；执行 `export PATH="$HOME/.local/bin:$PATH"` |
| `Error: Login canceled` | 你不在交互终端；请在 SSH 终端里直接跑 `devin auth login` |
| 网络超时 | 确认 `http_proxy`/`https_proxy` 环境变量存在（`loginctl`/新登录会话） |
| 想重装 | `devin uninstall` 后重新执行官方安装脚本 |
| 升级 | `devin update` |

---

## 7. 快速参考卡

```bash
# 安装
curl -fsSL https://cli.devin.ai/install.sh | bash

# 生效（新登录自动，当前 shell 手动）
export PATH="$HOME/.local/bin:$PATH"

# 登录 + 自检
devin setup
devin doctor

# 用
cd ~/your-project && devin
```

---

*相关：[开发服务器环境搭建](dev-server-setup.md) · [代理配置](proxy-setup.md) · [Node 应用部署](deploy-app.md)*
