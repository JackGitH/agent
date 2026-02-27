#!/bin/bash
# PR Creator - 自动创建 Pull Request

WORKSPACE="/workspace/agent"
GH="${GH:-gh}"

usage() {
    echo "Usage: $0 <branch> [options]"
    echo ""
    echo "Options:"
    echo "  --title <title>      PR 标题"
    echo "  --body <body>        PR 描述"
    echo "  --reviewers <r1,r2>  审核人 (逗号分隔)"
    echo "  --labels <l1,l2>     标签 (逗号分隔)"
    echo ""
    echo "Example:"
    echo "  $0 feat/new-feature --title 'Add new feature' --body 'Description...'"
}

create_pr() {
    local branch="$1"
    shift
    local title=""
    local body=""
    local reviewers=""
    local labels=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --title)
                title="$2"
                shift 2
                ;;
            --body)
                body="$2"
                shift 2
                ;;
            --reviewers)
                reviewers="$2"
                shift 2
                ;;
            --labels)
                labels="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    if [ -z "$branch" ]; then
        usage
        exit 1
    fi
    
    # 默认标题
    if [ -z "$title" ]; then
        title=$(echo "$branch" | sed 's/^feat\///' | sed 's/^fix\///' | sed 's/_/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2));}1')
    fi
    
    # 默认描述
    if [ -z "$body" ]; then
        body="## Summary

<!-- Describe your changes -->

## Changes

- 

## Testing

- [ ] Unit tests passed
- [ ] Type check passed
- [ ] Manual testing completed

## Screenshots (if UI changes)

<!-- Add screenshots here -->
"
    fi
    
    cd "$WORKSPACE"
    
    # 确保分支已推送
    echo "Pushing branch: $branch"
    git push -u origin "$branch" 2>&1
    
    if [ $? -ne 0 ]; then
        echo "❌ Failed to push branch"
        exit 1
    fi
    
    # 构建 gh pr create 命令
    local cmd="$GH pr create --title '$title' --body '$body'"
    
    if [ -n "$reviewers" ]; then
        cmd="$cmd --reviewer '$reviewers'"
    fi
    
    if [ -n "$labels" ]; then
        cmd="$cmd --label '$labels'"
    fi
    
    echo "Creating PR..."
    eval $cmd
    
    if [ $? -eq 0 ]; then
        echo "✅ PR created successfully"
    else
        echo "❌ Failed to create PR"
        exit 1
    fi
}

# 检查 gh CLI
if ! command -v $GH &> /dev/null; then
    echo "Error: gh CLI not found. Install from: https://cli.github.com/"
    exit 1
fi

case "$1" in
    -h|--help|help)
        usage
        ;;
    *)
        create_pr "$@"
        ;;
esac
