#!/bin/bash
# Agent Cluster System Initializer

echo "🤖 Agent Cluster System Setup"
echo "================================"
echo ""

# 检查依赖
check_deps() {
    echo "Checking dependencies..."
    
    local deps=("git" "tmux" "python3")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v $dep &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo "❌ Missing dependencies: ${missing[*]}"
        echo "Please install them first."
        exit 1
    fi
    
    echo "✅ All dependencies found"
}

# 创建目录结构
setup_dirs() {
    echo ""
    echo "Creating directory structure..."
    
    mkdir -p .agent-cluster/{logs,worktrees,prompts,scripts}
    
    echo "✅ Directories created"
}

# 初始化 git hooks
setup_hooks() {
    echo ""
    echo "Setting up git hooks..."
    
    # 创建 pre-push hook (可选: 运行测试)
    cat > .git/hooks/pre-push << 'HOOK'
#!/bin/bash
# Pre-push hook: Run quick checks before pushing

echo "Running pre-push checks..."

# 检查是否有敏感信息泄露
if git diff --cached | grep -E "(password|secret|token|api_key)" > /dev/null 2>&1; then
    echo "❌ Warning: Possible sensitive data in commit"
    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "✅ Pre-push checks passed"
HOOK

    chmod +x .git/hooks/pre-push
    echo "✅ Git hooks installed"
}

# 配置 cron 监控
setup_cron() {
    echo ""
    echo "Setting up cron monitoring..."
    
    # 添加到 crontab
    local cron_entry="*/10 * * * * cd $(pwd) && ./monitor.sh >> .agent-cluster/logs/monitor.log 2>&1"
    
    # 检查是否已存在
    if crontab -l 2>/dev/null | grep -q "monitor.sh"; then
        echo "⚠️ Cron job already exists"
    else
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
        echo "✅ Cron job added (every 10 minutes)"
    fi
    
    echo ""
    echo "Current crontab:"
    crontab -l 2>/dev/null | grep -E "monitor|agent" || echo "  (none)"
}

# 显示使用说明
show_usage() {
    echo ""
    echo "================================"
    echo "✅ Setup Complete!"
    echo "================================"
    echo ""
    echo "📖 Quick Start:"
    echo ""
    echo "1. 创建新任务:"
    echo "   python3 agent_orchestrator.py create \"修复登录bug\""
    echo ""
    echo "2. 启动任务:"
    echo "   python3 agent_orchestrator.py start <task_id>"
    echo ""
    echo "3. 查看状态:"
    echo "   python3 agent_orchestrator.py list"
    echo ""
    echo "4. 管理 worktree:"
    echo "   ./worktree_manager.sh list"
    echo ""
    echo "5. 创建 PR:"
    echo "   ./pr_create.sh <branch> --title \"My PR\""
    echo ""
    echo "📁 文件结构:"
    echo "   agent_orchestrator.py   - 任务编排器"
    echo "   monitor.sh              - 状态监控脚本"
    echo "   worktree_manager.sh     - Worktree 管理"
    echo "   pr_create.sh            - PR 创建脚本"
    echo "   agent-config.yaml       - 配置文件"
    echo ""
}

# 主程序
main() {
    check_deps
    setup_dirs
    setup_hooks
    setup_cron
    show_usage
    
    # 设置脚本执行权限
    chmod +x monitor.sh worktree_manager.sh pr_create.sh
}

main
