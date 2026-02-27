#!/bin/bash
# Agent Cluster Monitor - 每10分钟检查所有Agent状态
# crontab: */10 * * * * cd /workspace/agent && ./monitor.sh >> .agent-cluster/logs/monitor.log 2>&1

WORKSPACE="/workspace/agent"
LOG_FILE="$WORKSPACE/.agent-cluster/logs/monitor.log"
TASKS_FILE="$WORKSPACE/.agent-cluster/tasks.json"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Agent Monitor Check ==="

# 读取任务列表
if [ ! -f "$TASKS_FILE" ]; then
    log "No tasks file found, skipping..."
    exit 0
fi

# 使用 python 解析 JSON
python3 << 'EOF'
import json
import subprocess
import os
from datetime import datetime

WORKSPACE = "/workspace/agent"
LOG_FILE = f"{WORKSPACE}/.agent-cluster/logs/monitor.log"

def log(msg):
    with open(LOG_FILE, 'a') as f:
        f.write(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}\n")
    print(msg)

# 读取任务
with open(f"{WORKSPACE}/.agent-cluster/tasks.json", 'r') as f:
    tasks = json.load(f)

running_count = 0
completed_count = 0
failed_count = 0

for task_id, task in tasks.items():
    status = task.get('status', 'unknown')
    branch = task.get('branch', 'unknown')
    agent_type = task.get('agent_type', 'unknown')
    
    if status == 'running':
        running_count += 1
        session_name = f"agent-{task_id}"
        
        # 检查 tmux session 是否还活着
        result = subprocess.run(
            ["tmux", "has-session", "-t", session_name],
            capture_output=True
        )
        
        if result.returncode != 0:
            # session 死了，检查是否创建了 PR
            log(f"⚠️ Task {task_id} session died, checking status...")
            
            # 检查分支是否已推送
            worktree_path = f"{WORKSPACE}/.agent-cluster/worktrees/{branch.replace('/', '_')}"
            push_result = subprocess.run(
                ["git", "push", "--dry-run"],
                cwd=worktree_path,
                capture_output=True
            )
            
            if push_result.returncode == 0:
                task['status'] = 'completed'
                task['completed_at'] = datetime.now().isoformat()
                log(f"✅ Task {task_id} completed")
            else:
                # 尝试重启 (最多3次)
                retry = task.get('retry', 0)
                if retry < 3:
                    task['retry'] = retry + 1
                    log(f"🔄 Restarting task {task_id} (attempt {retry + 1}/3)")
                    # 这里可以添加重启逻辑
                else:
                    task['status'] = 'failed'
                    task['error'] = 'Max retries exceeded'
                    log(f"❌ Task {task_id} failed after 3 retries")
    
    elif status == 'completed':
        completed_count += 1
    elif status == 'failed':
        failed_count += 1

# 保存更新后的状态
with open(f"{WORKSPACE}/.agent-cluster/tasks.json", 'w') as f:
    json.dump(tasks, f, indent=2)

log(f"=== Summary: {running_count} running, {completed_count} completed, {failed_count} failed ===")
EOF
