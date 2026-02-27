#!/usr/bin/env python3
"""
Agent Cluster System - 任务编排器
基于 OpenClaw + Claude Code 架构设计
"""

import json
import os
import subprocess
import signal
import time
from datetime import datetime
from typing import Dict, List, Optional
from dataclasses import dataclass, asdict
from pathlib import Path

# 配置
WORKSPACE_ROOT = Path("/workspace/agent")
AGENTS_CONFIG = {
    "codex": {
        "name": "Codex",
        "model": "gpt-5.3-codex",
        "use_case": "后端逻辑、复杂bug、多文件重构、跨代码库推理",
        "priority": 90,
        "command": "claude-code"  # 可替换为实际命令
    },
    "claude": {
        "name": "Claude Code", 
        "model": "claude-opus-4.5",
        "use_case": "前端工作、权限问题少、git操作",
        "priority": 80,
        "command": "claude"
    },
    "glm": {
        "name": "GLM-5",
        "model": "glm-5",
        "use_case": "中文任务、免费替代方案",
        "priority": 70,
        "command": "glm"
    }
}

# 检查 tmux 是否可用
HAS_TMUX = subprocess.run(["which", "tmux"], capture_output=True).returncode == 0

# 存储运行中的 Agent 进程
RUNNING_AGENTS: Dict[str, subprocess.Popen] = {}

@dataclass
class Task:
    id: str
    description: str
    agent_type: str
    branch: str
    status: str = "pending"  # pending, running, completed, failed
    started_at: Optional[str] = None
    completed_at: Optional[str] = None
    error: Optional[str] = None
    pr_url: Optional[str] = None

class AgentOrchestrator:
    """Agent 编排器 - 核心大脑"""
    
    def __init__(self, workspace: Path):
        self.workspace = workspace
        self.tasks_file = workspace / ".agent-cluster" / "tasks.json"
        self.tasks: Dict[str, Task] = {}
        self._ensure_dirs()
        self._load_tasks()
    
    def _ensure_dirs(self):
        """确保目录结构存在"""
        dirs = [
            ".agent-cluster",
            ".agent-cluster/logs",
            ".agent-cluster/worktrees",
            ".agent-cluster/scripts",
            ".agent-cluster/prompts"
        ]
        for d in dirs:
            (self.workspace / d).mkdir(parents=True, exist_ok=True)
    
    def _load_tasks(self):
        """加载任务列表"""
        if self.tasks_file.exists():
            try:
                with open(self.tasks_file, 'r') as f:
                    data = json.load(f)
                    self.tasks = {k: Task(**v) for k, v in data.items()}
            except:
                self.tasks = {}
    
    def _save_tasks(self):
        """保存任务列表"""
        with open(self.tasks_file, 'w') as f:
            json.dump({k: asdict(v) for k, v in self.tasks.items()}, f, indent=2)
    
    def select_agent(self, task_description: str) -> str:
        """根据任务描述选择合适的 Agent"""
        task_lower = task_description.lower()
        
        # 选择策略
        if any(kw in task_lower for kw in ['frontend', 'ui', '界面', '前端', 'react', 'vue']):
            return "claude"
        elif any(kw in task_lower for kw in ['backend', '后端', 'api', 'database', '数据库']):
            return "codex"
        elif any(kw in task_lower for kw in ['cn', '中文', 'china']):
            return "glm"
        else:
            return "codex"  # 默认
    
    def create_task(self, description: str, branch: Optional[str] = None) -> Task:
        """创建新任务"""
        import uuid
        task_id = f"task-{uuid.uuid4().hex[:8]}"
        
        if not branch:
            # 从描述生成分支名
            branch_name = description[:30].replace(" ", "-").lower()
            branch = f"feat/{branch_name}"
        
        agent_type = self.select_agent(description)
        
        task = Task(
            id=task_id,
            description=description,
            agent_type=agent_type,
            branch=branch
        )
        
        self.tasks[task_id] = task
        self._save_tasks()
        
        return task
    
    def start_task(self, task_id: str, base_branch: str = "main") -> bool:
        """启动任务 - 创建 worktree 并运行 Agent"""
        if task_id not in self.tasks:
            print(f"❌ Task {task_id} not found")
            return False
        
        task = self.tasks[task_id]
        
        try:
            # 1. 检查是否需要创建 worktree
            worktree_path = self.workspace / ".agent-cluster" / "worktrees" / task.branch.replace("/", "_")
            
            if not worktree_path.exists():
                # 创建新分支的 worktree (从当前 HEAD)
                result = subprocess.run(
                    ["git", "worktree", "add", str(worktree_path), "-b", task.branch, "HEAD"],
                    cwd=self.workspace,
                    capture_output=True,
                    text=True
                )
                
                if result.returncode != 0:
                    # 可能分支已存在，尝试检出
                    print(f"⚠️ Worktree 创建: {result.stderr}")
            
            # 2. 安装依赖
            self._install_deps(worktree_path)
            
            # 3. 生成 prompt
            prompt = self._generate_prompt(task)
            prompt_file = self.workspace / ".agent-cluster" / "prompts" / f"{task_id}.md"
            prompt_file.write_text(prompt)
            
            # 4. 启动 Agent
            pid = self._start_agent(task, worktree_path, prompt_file)
            
            # 更新任务状态
            task.status = "running"
            task.started_at = datetime.now().isoformat()
            self._save_tasks()
            
            print(f"✅ Task {task_id} started")
            print(f"   Branch: {task.branch}")
            print(f"   Agent: {AGENTS_CONFIG[task.agent_type]['name']}")
            print(f"   Worktree: {worktree_path}")
            print(f"   PID: {pid}")
            
            return True
            
        except Exception as e:
            task.status = "failed"
            task.error = str(e)
            self._save_tasks()
            print(f"❌ Task {task_id} failed to start: {e}")
            return False
    
    def _install_deps(self, worktree_path: Path):
        """根据项目类型安装依赖"""
        if (worktree_path / "package.json").exists():
            subprocess.run(["npm", "install"], cwd=worktree_path, capture_output=True)
        elif (worktree_path / "pom.xml").exists():
            subprocess.run(["mvn", "compile"], cwd=worktree_path, capture_output=True)
        elif (worktree_path / "requirements.txt").exists():
            subprocess.run(["pip", "install", "-r", "requirements.txt"], cwd=worktree_path, capture_output=True)
        elif (worktree_path / "go.mod").exists():
            subprocess.run(["go", "mod", "download"], cwd=worktree_path, capture_output=True)
    
    def _generate_prompt(self, task: Task) -> str:
        """生成 Agent prompt"""
        return f"""# 任务: {task.description}

## 分支
{task.branch}

## 目标
完成以下任务: {task.description}

## 约束
1. 保持代码风格一致
2. 添加必要的测试
3. 确保 CI 通过
4. 不要修改生产数据库相关代码

## 完成标准
- [ ] 代码编写完成
- [ ] 单元测试通过
- [ ] 类型检查通过 (如果有)
- [ ] 创建 PR

完成后请报告状态。
"""
    
    def _start_agent(self, task: Task, worktree_path: Path, prompt_file: Path) -> int:
        """启动 Agent 进程"""
        agent_config = AGENTS_CONFIG[task.agent_type]
        
        # 日志文件
        log_file = self.workspace / ".agent-cluster" / "logs" / f"{task.id}.log"
        
        # 构建 Agent 命令
        # 这里可以替换为实际的 Claude Code / Codex / GLM 调用
        # 暂时使用简单的脚本作为演示
        agent_script = f"""#!/bin/bash
echo "=== Agent started: {task.id} ==="
echo "Agent: {agent_config['name']}"
echo "Model: {agent_config['model']}"
echo ""
echo "=== Task Prompt ==="
cat "{prompt_file}"
echo ""
echo "=== Agent would execute here ==="
echo "In production, this would call: {agent_config['command']}"
echo "For Claude Code: claude --prompt $(cat {prompt_file})"
echo "For Codex: codex --task $(cat {prompt_file})"
echo "For GLM: glm-5 --input $(cat {prompt_file})"
echo ""
echo "Simulating work... (10 seconds)"
sleep 10
echo "=== Task completed ==="
"""
        
        # 写入临时脚本
        script_file = self.workspace / ".agent-cluster" / "scripts" / f"{task.id}.sh"
        script_file.write_text(agent_script)
        script_file.chmod(0o755)
        
        # 启动进程
        with open(log_file, 'w') as f:
            proc = subprocess.Popen(
                [str(script_file)],
                cwd=worktree_path,
                stdout=f,
                stderr=subprocess.STDOUT,
                preexec_fn=os.setsid  # 创建新进程组
            )
        
        RUNNING_AGENTS[task.id] = proc
        return proc.pid
    
    def check_task_status(self, task_id: str) -> Dict:
        """检查任务状态"""
        if task_id not in self.tasks:
            return {"error": "Task not found"}
        
        task = self.tasks[task_id]
        
        if task.status == "running":
            # 检查进程是否还在运行
            if task_id in RUNNING_AGENTS:
                proc = RUNNING_AGENTS[task_id]
                if proc.poll() is not None:
                    # 进程已结束
                    task.status = "completed"
                    task.completed_at = datetime.now().isoformat()
                    del RUNNING_AGENTS[task_id]
                    self._save_tasks()
        
        return {
            "id": task.id,
            "description": task.description,
            "agent": task.agent_type,
            "agent_name": AGENTS_CONFIG[task.agent_type]["name"],
            "branch": task.branch,
            "status": task.status,
            "started_at": task.started_at,
            "completed_at": task.completed_at,
            "error": task.error,
            "pr_url": task.pr_url
        }
    
    def list_tasks(self) -> List[Dict]:
        """列出所有任务"""
        return [self.check_task_status(tid) for tid in self.tasks]
    
    def stop_task(self, task_id: str) -> bool:
        """停止任务"""
        if task_id not in self.tasks:
            return False
        
        task = self.tasks[task_id]
        
        if task_id in RUNNING_AGENTS:
            try:
                proc = RUNNING_AGENTS[task_id]
                # 终止整个进程组
                os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
                task.status = "failed"
                task.error = "Stopped by user"
                del RUNNING_AGENTS[task_id]
                self._save_tasks()
                return True
            except:
                return False
        
        return False
    
    def delete_task(self, task_id: str) -> bool:
        """删除任务"""
        if task_id in self.tasks:
            # 先停止
            self.stop_task(task_id)
            # 删除
            del self.tasks[task_id]
            self._save_tasks()
            return True
        return False


def main():
    import sys
    
    orchestrator = AgentOrchestrator(WORKSPACE_ROOT)
    
    if len(sys.argv) < 2:
        print("""
🤖 Agent Cluster System

用法:
  python3 agent_orchestrator.py create "<任务描述>"     # 创建任务
  python3 agent_orchestrator.py start <task_id>        # 启动任务
  python3 agent_orchestrator.py status <task_id>       # 查看状态
  python3 agent_orchestrator.py list                  # 列出所有任务
  python3 agent_orchestrator.py stop <task_id>         # 停止任务
  python3 agent_orchestrator.py delete <task_id>        # 删除任务
        """)
        return
    
    command = sys.argv[1]
    
    if command == "create":
        description = " ".join(sys.argv[2:])
        task = orchestrator.create_task(description)
        print(f"✅ Task created: {task.id}")
        print(f"   Agent: {task.agent_type}")
        print(f"   Branch: {task.branch}")
        print(f"\nRun: python3 agent_orchestrator.py start {task.id}")
    
    elif command == "start":
        if len(sys.argv) < 3:
            print("Usage: start <task_id>")
            return
        task_id = sys.argv[2]
        orchestrator.start_task(task_id)
    
    elif command == "status":
        if len(sys.argv) < 3:
            print("Usage: status <task_id>")
            return
        task_id = sys.argv[2]
        status = orchestrator.check_task_status(task_id)
        print(json.dumps(status, indent=2, ensure_ascii=False))
    
    elif command == "list":
        tasks = orchestrator.list_tasks()
        print("\n📋 Tasks:")
        print("-" * 60)
        for t in tasks:
            status_icon = {
                "pending": "⏳",
                "running": "🔄",
                "completed": "✅",
                "failed": "❌"
            }.get(t.get("status", "?"), "?")
            print(f"{status_icon} [{t.get('status', '?')}] {t['id']}")
            print(f"   {t['description'][:50]}...")
            print(f"   Agent: {t.get('agent_name', '?')} | Branch: {t.get('branch', '?')}")
            print()
    
    elif command == "stop":
        if len(sys.argv) < 3:
            print("Usage: stop <task_id>")
            return
        task_id = sys.argv[2]
        if orchestrator.stop_task(task_id):
            print(f"✅ Task {task_id} stopped")
        else:
            print(f"❌ Failed to stop {task_id}")
    
    elif command == "delete":
        if len(sys.argv) < 3:
            print("Usage: delete <task_id>")
            return
        task_id = sys.argv[2]
        if orchestrator.delete_task(task_id):
            print(f"✅ Task {task_id} deleted")
        else:
            print(f"❌ Failed to delete {task_id}")


if __name__ == "__main__":
    main()
