# 🤖 Agent Cluster System

基于 [OpenClaw + Claude Code](https://mp.weixin.qq.com/s/gtxM1f3JmfXqDuxGIa3-ng) 架构设计的 AI Agent 集群系统。

## 📊 核心能力

- **多 Agent 编排** - 自动选择合适的 Agent (Codex / Claude / GLM)
- **并行开发** - 通过 Git Worktree 实现多任务并行
- **自动监控** - Cron 定时检查任务状态，失败自动重试
- **完整工作流** - 需求 → 代码 → 测试 → PR → Review → 合并

## 🏗 架构

```
用户 → 编排器 (Orchestrator) → 多个 Agent
                                   ↓
                            Git Worktree
                                   ↓
                              写代码 → PR
```

### 双层设计

| 层级 | 职责 |
|------|------|
| **编排层** | 理解需求、拆解任务、选择 Agent、监控进度 |
| **执行层** | 读写代码、运行测试、提交 PR |

## 🚀 快速开始

### 1. 初始化

```bash
chmod +x setup.sh
./setup.sh
```

### 2. 创建任务

```bash
python3 agent_orchestrator.py create "实现用户登录功能"
```

系统会自动：
- 选择合适的 Agent
- 生成分支名
- 创建任务记录

### 3. 启动任务

```bash
python3 agent_orchestrator.py start <task_id>
```

系统会：
- 创建 Git Worktree
- 安装依赖
- 启动 Agent (tmux session)
- 开始执行任务

### 4. 监控状态

```bash
# 手动检查
python3 agent_orchestrator.py list

# 或自动监控 (已配置 cron)
./monitor.sh
```

### 5. 与 Agent 交互

```bash
# 发送消息给运行中的 Agent
python3 agent_orchestrator.py send <task_id> "先做 API 层,别管 UI"
```

### 6. 创建 PR

```bash
./pr_create.sh feat/login --title "实现用户登录" --labels "feature"
```

## 📁 文件说明

| 文件 | 说明 |
|------|------|
| `agent_orchestrator.py` | 核心任务编排器 |
| `monitor.sh` | 状态监控脚本 (cron) |
| `worktree_manager.sh` | Git Worktree 管理 |
| `pr_create.sh` | Pull Request 创建 |
| `agent-config.yaml` | 系统配置 |
| `setup.sh` | 初始化脚本 |

## ⚙️ 配置

编辑 `agent-config.yaml` 自定义：

```yaml
AGENTS:
  codex:
    model: gpt-5.3-codex
    priority: 90
    
  glm:
    model: glm-5
    priority: 70
    
TASK:
  max_parallel_tasks: 4
  max_retries: 3
```

## 🔧 Agent 选择策略

| 任务类型 | 推荐 Agent |
|----------|-----------|
| 后端逻辑、复杂 bug | Codex |
| 前端、UI、React | Claude Code |
| 中文任务 | GLM-5 |

## 📈 工作流

```
1. 需求 → 编排器理解并拆解
2. 创建 Worktree + 启动 Agent
3. Agent 写代码 + 提交
4. 自动监控 (每10分钟)
5. 创建 PR
6. AI Code Review
7. 人工 Review + 合并
```

## 🔐 安全

- 执行层 Agent 不接触生产数据库
- 只获取"最小必要上下文"
- 敏感操作需要人工确认

## 📝 任务状态

```bash
# 查看所有任务
python3 agent_orchestrator.py list

# 查看具体任务
python3 agent_orchestrator.py status <task_id>
```

状态: `pending` → `running` → `completed` / `failed`

## 🤝 集成外部 Agent

修改 `_build_agent_command()` 方法，集成：

- Claude Code
- Codex
- GLM-5
- 自定义 Agent

## 📄 License

MIT
