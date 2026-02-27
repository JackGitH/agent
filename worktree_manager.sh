#!/bin/bash
# Git Worktree Manager - 管理多个并行的 git worktree

WORKSPACE="/workspace/agent"
WORKTREES_DIR="$WORKSPACE/.agent-cluster/worktrees"

usage() {
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  list              列出所有 worktree"
    echo "  create <branch>   创建新 worktree"
    echo "  remove <branch>   删除 worktree"
    echo "  cleanup           清理孤立的 worktree"
    echo "  prune             清理无效的 git 引用"
}

list_worktrees() {
    echo "=== 主仓库 Worktrees ==="
    git -C "$WORKSPACE" worktree list
    
    echo ""
    echo "=== Worktree 目录 ==="
    if [ -d "$WORKTREES_DIR" ]; then
        ls -la "$WORKTREES_DIR"
    else
        echo "No worktrees directory"
    fi
}

create_worktree() {
    local branch="$1"
    local base_branch="${2:-main}"
    
    if [ -z "$branch" ]; then
        echo "Error: branch name required"
        exit 1
    fi
    
    local worktree_path="$WORKTREES_DIR/${branch//\//_}"
    
    # 创建 worktree
    echo "Creating worktree for branch: $branch"
    git -C "$WORKSPACE" worktree add "$worktree_path" -b "$branch" "origin/$base_branch"
    
    if [ $? -eq 0 ]; then
        echo "✅ Worktree created: $worktree_path"
        
        # 安装依赖
        if [ -f "$worktree_path/package.json" ]; then
            echo "Installing npm dependencies..."
            cd "$worktree_path" && npm install
        elif [ -f "$worktree_path/requirements.txt" ]; then
            echo "Installing Python dependencies..."
            pip install -r "$worktree_path/requirements.txt"
        elif [ -f "$worktree_path/pom.xml" ]; then
            echo "Building Java project..."
            cd "$worktree_path" && mvn compile
        fi
    else
        echo "❌ Failed to create worktree"
        exit 1
    fi
}

remove_worktree() {
    local branch="$1"
    
    if [ -z "$branch" ]; then
        echo "Error: branch name required"
        exit 1
    fi
    
    local worktree_path="$WORKTREES_DIR/${branch//\//_}"
    
    # 删除 worktree
    echo "Removing worktree: $worktree_path"
    git -C "$WORKSPACE" worktree remove "$worktree_path" --force
    
    if [ $? -eq 0 ]; then
        echo "✅ Worktree removed: $worktree_path"
    else
        echo "❌ Failed to remove worktree"
    fi
}

cleanup() {
    echo "=== Cleaning up worktrees ==="
    
    # 获取所有活跃分支
    local branches=$(git -C "$WORKSPACE" branch --format='%(refname:short)')
    
    # 检查每个 worktree
    for wt in "$WORKTREES_DIR"/*; do
        if [ -d "$wt" ]; then
            branch_name=$(basename "$wt" | sed 's/_/\//g')
            if ! echo "$branches" | grep -q "^${branch_name}$"; then
                echo "Removing orphan worktree: $wt"
                git -C "$WORKSPACE" worktree remove "$wt" --force
            fi
        fi
    done
    
    # 清理无效引用
    git -C "$WORKSPACE" worktree prune
    
    echo "✅ Cleanup complete"
}

case "$1" in
    list)
        list_worktrees
        ;;
    create)
        create_worktree "$2" "$3"
        ;;
    remove)
        remove_worktree "$2"
        ;;
    cleanup)
        cleanup
        ;;
    prune)
        git -C "$WORKSPACE" worktree prune
        ;;
    *)
        usage
        ;;
esac
