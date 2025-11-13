#!/usr/bin/env bash
#
# pr-context - Generate PR context for LLM consumption
# 
# Usage: pr-context branch1 [branch2 ...]
# 
# Setup:
#   1. Set GITHUB_TOKEN: export GITHUB_TOKEN='ghp_...'
#   2. Run from within your git repo: ./pr-context feature/my-branch
#
# Requirements: git, curl, jq

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

OUTPUT_DIR="${OUTPUT_DIR:-.pr_context}"
BASE_BRANCH="${BASE_BRANCH:-main}"

# ============================================================================
# FUNCTIONS
# ============================================================================

print_usage() {
    cat << EOF
Usage: pr-context [OPTIONS] BRANCH [BRANCH...]

Generate PR context files for LLM consumption by fetching PR metadata
and diffs without affecting your local git state.

ARGUMENTS:
    BRANCH              One or more branch names to process

OPTIONS:
    -o, --output PATH   Output file path (default: .pr_context/context_TIMESTAMP.txt)
    -b, --base BRANCH   Base branch for comparison (default: main)
    -h, --help          Show this help message

ENVIRONMENT:
    GITHUB_TOKEN        GitHub personal access token (required)

EXAMPLES:
    pr-context feature/my-branch
    pr-context feature/foo feature/bar -o /tmp/context.txt

EOF
    exit 0
}

error() {
    echo "Error: $1" >&2
    exit 1
}

info() {
    echo "→ $1" >&2
}

parse_git_remote() {
    local remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    
    if [ -z "$remote_url" ]; then
        error "Could not determine git remote. Are you in a git repository with an 'origin' remote?"
    fi
    
    # Parse both SSH and HTTPS formats
    # SSH: git@github.com:owner/repo.git
    # HTTPS: https://github.com/owner/repo.git
    
    local owner repo
    
    if [[ "$remote_url" =~ github\.com[:/]([^/]+)/([^/]+)(\.git)?$ ]]; then
        owner="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
        repo="${repo%.git}"  # Remove .git suffix if present
    else
        error "Could not parse GitHub repository from remote URL: $remote_url"
    fi
    
    echo "$owner:$repo"
}

check_requirements() {
    local missing=()
    
    command -v git >/dev/null 2>&1 || missing+=("git")
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    command -v jq >/dev/null 2>&1 || missing+=("jq")
    
    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing required commands: ${missing[*]}
        
Install jq with:
  macOS:    brew install jq
  Ubuntu:   sudo apt-get install jq
  Fedora:   sudo dnf install jq"
    fi
    
    if [ -z "${GITHUB_TOKEN:-}" ]; then
        error "GITHUB_TOKEN not set. 

Create a token at: https://github.com/settings/tokens
Then set it with: export GITHUB_TOKEN='ghp_your_token_here'

Or add to ~/.bashrc or ~/.zshrc:
  export GITHUB_TOKEN='ghp_your_token_here'"
    fi
}

fetch_remote_branches() {
    local branches=("$@")
    
    info "Fetching latest from remote..."
    
    # Build refspecs for all branches (+ forces update even if non-fast-forward)
    local refspecs=()
    for branch in "${branches[@]}"; do
        refspecs+=("+refs/heads/${branch}:refs/remotes/origin/${branch}")
    done
    refspecs+=("+refs/heads/${BASE_BRANCH}:refs/remotes/origin/${BASE_BRANCH}")
    
    # Capture stderr to see actual errors
    local fetch_output
    if ! fetch_output=$(git fetch origin "${refspecs[@]}" 2>&1); then
        error "Failed to fetch branches from remote. Git output:
$fetch_output"
    fi
} 

get_pr_info() {
    local repo_owner="$1"
    local repo_name="$2"
    local branch="$3"
    local url="https://api.github.com/repos/${repo_owner}/${repo_name}/pulls"
    
    curl -sf \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "${url}?head=${repo_owner}:${branch}&state=open" \
        | jq '.[0] // null'
}

get_diff() {
    local branch="$1"
    
    git diff "origin/${BASE_BRANCH}...origin/${branch}" 2>/dev/null || \
        echo "Error: Could not generate diff for ${branch}"
}

get_changed_files() {
    local branch="$1"
    
    git diff --name-only "origin/${BASE_BRANCH}...origin/${branch}" 2>/dev/null || \
        echo ""
}

format_pr_section() {
    local branch="$1"
    local pr_json="$2"
    local diff="$3"
    local files="$4"
    
    echo "================================================================================"
    echo "BRANCH: ${branch}"
    echo "================================================================================"
    echo
    
    if [ "$pr_json" != "null" ] && [ -n "$pr_json" ]; then
        local pr_number=$(echo "$pr_json" | jq -r '.number')
        local pr_title=$(echo "$pr_json" | jq -r '.title')
        local pr_author=$(echo "$pr_json" | jq -r '.user.login')
        local pr_state=$(echo "$pr_json" | jq -r '.state')
        local pr_url=$(echo "$pr_json" | jq -r '.html_url')
        local pr_body=$(echo "$pr_json" | jq -r '.body // "No description provided"')
        
        echo "PR #${pr_number}: ${pr_title}"
        echo "Author: ${pr_author}"
        echo "Status: ${pr_state}"
        echo "URL: ${pr_url}"
        echo
        echo "DESCRIPTION:"
        echo "--------------------------------------------------------------------------------"
        echo "$pr_body"
        echo "--------------------------------------------------------------------------------"
    else
        echo "⚠ No open PR found for branch '${branch}'"
        echo "This may be a local-only branch or a closed PR"
        echo "--------------------------------------------------------------------------------"
    fi
    
    echo
    
    local file_count=$(echo "$files" | grep -c "." || echo "0")
    echo "CHANGED FILES (${file_count}):"
    echo "--------------------------------------------------------------------------------"
    if [ -n "$files" ]; then
        echo "$files" | while read -r file; do
            [ -n "$file" ] && echo "  • ${file}"
        done
    fi
    echo "--------------------------------------------------------------------------------"
    echo
    
    echo "DIFF:"
    echo "--------------------------------------------------------------------------------"
    echo "$diff"
    echo "--------------------------------------------------------------------------------"
    echo
    echo
}

generate_context() {
    local repo_owner="$1"
    local repo_name="$2"
    shift 2
    local branches=("$@")
    local output_file="${OUTPUT_FILE:-${OUTPUT_DIR}/context_$(date +%Y%m%d_%H%M%S).txt}"
    
    # Create output directory
    mkdir -p "$(dirname "$output_file")"
    
    # Write header
    {
        echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo "Repository: ${repo_owner}/${repo_name}"
        echo "Base Branch: ${BASE_BRANCH}"
        echo "Branches: ${branches[*]}"
        echo "================================================================================"
        echo
    } > "$output_file"
    
    # Process each branch
    for branch in "${branches[@]}"; do
        info "Processing branch: ${branch}"
        
        local pr_json=$(get_pr_info "$repo_owner" "$repo_name" "$branch")
        local diff=$(get_diff "$branch")
        local files=$(get_changed_files "$branch")
        
        format_pr_section "$branch" "$pr_json" "$diff" "$files" >> "$output_file"
    done
    
    local file_size=$(du -h "$output_file" | cut -f1)
    info "✓ Context written to: ${output_file}"
    info "  Total size: ${file_size}"
    
    echo "$output_file"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local branches=()
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                print_usage
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -b|--base)
                BASE_BRANCH="$2"
                shift 2
                ;;
            -*)
                error "Unknown option: $1"
                ;;
            *)
                branches+=("$1")
                shift
                ;;
        esac
    done
    
    # Validate
    if [ ${#branches[@]} -eq 0 ]; then
        error "No branches specified. Use --help for usage."
    fi
    
    check_requirements
    
    # Check we're in a git repo
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        error "Not in a git repository"
    fi
    
    # Auto-detect repository from git remote
    local repo_info=$(parse_git_remote)
    local repo_owner="${repo_info%%:*}"
    local repo_name="${repo_info##*:}"
    
    info "Detected repository: ${repo_owner}/${repo_name}"
    
    # Generate context
    fetch_remote_branches "${branches[@]}"
    generate_context "$repo_owner" "$repo_name" "${branches[@]}"
}

main "$@"

