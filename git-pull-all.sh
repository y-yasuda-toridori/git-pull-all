#!/bin/bash
#
# git-pull-all.sh
# カレントディレクトリ配下の全gitリポジトリに対して:
#   1. デフォルトブランチを特定
#   2. 未コミットの変更や detached HEAD があれば警告してスキップ
#   3. 変更がなければデフォルトブランチに切替 → git pull --ff-only
#   4. 元のブランチに戻る
#   5. 結果をサマリーで表示（各リポジトリの現在ブランチ付き）
#
# Usage:
#   cd /path/to/parent && ./git-pull-all.sh
#   ./git-pull-all.sh /path/to/parent    # 引数でも指定可
#

set -euo pipefail

# --- 設定 ---
DEV_DIR="${1:-$(pwd)}"

if [[ ! -d "$DEV_DIR" ]]; then
    echo "Error: ${DEV_DIR} is not a directory" >&2
    exit 1
fi

# 相対パスでも安全に動作するよう絶対パスに変換
DEV_DIR="$(cd "$DEV_DIR" && pwd)"

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# --- 結果格納 ---
declare -a RESULTS=()
SUCCESS_COUNT=0
SKIPPED_COUNT=0
FAILED_COUNT=0

# --- デフォルトブランチ検出 ---
detect_default_branch() {
    # 方法1: origin/HEAD のシンボリックref (ローカルのみ、高速)
    local ref
    ref=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||') || true
    if [[ -n "$ref" ]]; then
        echo "$ref"
        return 0
    fi

    # 方法2: よくあるブランチ名をローカルrefから探す (ネットワーク不要)
    for candidate in main master develop; do
        if git show-ref --verify --quiet "refs/remotes/origin/$candidate" 2>/dev/null; then
            echo "$candidate"
            return 0
        fi
    done

    # 方法3: remote show origin から取得 (ネットワーク呼び出し、最終手段)
    ref=$(timeout 10 git remote show origin 2>/dev/null | awk '/HEAD branch/ {print $NF}') || true
    if [[ -n "$ref" && "$ref" != "(unknown)" ]]; then
        echo "$ref"
        return 0
    fi

    return 1
}

# --- ワーキングツリーの差分チェック ---
has_changes() {
    # staged, unstaged, untracked のいずれかがあれば true
    if ! git diff --quiet 2>/dev/null; then
        return 0  # unstaged changes
    fi
    if ! git diff --cached --quiet 2>/dev/null; then
        return 0  # staged changes
    fi
    if [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null | head -1)" ]]; then
        return 0  # untracked files
    fi
    return 1
}

# --- メイン処理 ---
echo -e "${BOLD}========================================${RESET}"
echo -e "${BOLD} Git Pull All Repositories${RESET}"
echo -e "${BOLD} Target: ${DEV_DIR}${RESET}"
echo -e "${BOLD}========================================${RESET}"
echo ""

# gitリポジトリの一覧を取得
REPOS=()
for dir in "$DEV_DIR"/*/; do
    [[ -d "$dir/.git" ]] && REPOS+=("$dir")
done

TOTAL=${#REPOS[@]}

if [[ $TOTAL -eq 0 ]]; then
    echo -e "${RED}Error: No git repositories found in ${DEV_DIR}${RESET}" >&2
    exit 1
fi

echo -e "${CYAN}Found ${BOLD}${TOTAL}${RESET}${CYAN} git repositories${RESET}"
echo ""

for i in "${!REPOS[@]}"; do
    repo="${REPOS[$i]}"
    repo_name=$(basename "$repo")
    num=$((i + 1))

    echo -e "${BOLD}[${num}/${TOTAL}] ${repo_name}${RESET}"

    cd "$repo"

    # デフォルトブランチの検出
    default_branch=$(detect_default_branch) || true
    if [[ -z "$default_branch" ]]; then
        echo -e "  ${RED}FAIL: Could not detect default branch${RESET}"
        fb=$(git branch --show-current 2>/dev/null) || fb="unknown"
        RESULTS+=("${RED}FAIL${RESET}    ${repo_name} [${fb}] -- default branch not found")
        FAILED_COUNT=$((FAILED_COUNT + 1))
        echo ""
        continue
    fi

    # 現在のブランチ (detached HEAD の場合は空文字)
    current_branch=$(git branch --show-current 2>/dev/null) || true
    if [[ -z "$current_branch" ]]; then
        echo -e "  Default branch: ${CYAN}${default_branch}${RESET}  (current: ${YELLOW}detached HEAD${RESET})"
        echo -e "  ${YELLOW}WARNING: Detached HEAD -- skipping${RESET}"
        RESULTS+=("${YELLOW}SKIP${RESET}    ${repo_name} [detached] -- detached HEAD")
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        echo ""
        continue
    fi

    echo -e "  Default branch: ${CYAN}${default_branch}${RESET}  (current: ${current_branch})"

    # 差分チェック
    if has_changes; then
        echo -e "  ${YELLOW}WARNING: Uncommitted changes detected -- skipping${RESET}"
        # 差分の概要を表示
        staged=$(git diff --cached --stat 2>/dev/null | tail -1)
        unstaged=$(git diff --stat 2>/dev/null | tail -1)
        untracked=$(git ls-files --others --exclude-standard 2>/dev/null | head -1)
        [[ -n "$staged" ]]    && echo -e "    Staged:    ${staged}"
        [[ -n "$unstaged" ]]  && echo -e "    Unstaged:  ${unstaged}"
        [[ -n "$untracked" ]] && echo -e "    Untracked: files exist"
        RESULTS+=("${YELLOW}SKIP${RESET}    ${repo_name} [${current_branch}] -- uncommitted changes")
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        echo ""
        continue
    fi

    # デフォルトブランチへ切替
    if [[ "$current_branch" != "$default_branch" ]]; then
        checkout_output=$(git checkout "$default_branch" 2>&1) && checkout_exit=0 || checkout_exit=$?
        if [[ $checkout_exit -ne 0 ]]; then
            echo -e "  ${RED}FAIL: Could not checkout ${default_branch}${RESET}"
            echo "$checkout_output" | sed 's/^/  /'
            RESULTS+=("${RED}FAIL${RESET}    ${repo_name} [${current_branch}] -- checkout to ${default_branch} failed")
            FAILED_COUNT=$((FAILED_COUNT + 1))
            echo ""
            continue
        fi
    fi

    # git pull (--ff-only で非対話的に安全に実行)
    pull_output=$(git pull --ff-only 2>&1) && pull_exit=0 || pull_exit=$?

    if [[ $pull_exit -eq 0 ]]; then
        if echo "$pull_output" | grep -q "Already up to date"; then
            echo -e "  ${GREEN}OK: Already up to date${RESET}"
            pull_status="already up to date"
        else
            echo -e "  ${GREEN}OK: Updated${RESET}"
            echo "$pull_output" | sed 's/^/  /'
            pull_status="updated"
        fi
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo -e "  ${RED}FAIL: git pull failed${RESET}"
        echo "$pull_output" | sed 's/^/  /'
        pull_status="pull failed"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi

    # 元のブランチに戻る
    if [[ "$current_branch" != "$default_branch" ]]; then
        restore_output=$(git checkout "$current_branch" 2>&1) && restore_exit=0 || restore_exit=$?
        if [[ $restore_exit -eq 0 ]]; then
            echo -e "  Restored branch: ${CYAN}${current_branch}${RESET}"
        else
            echo -e "  ${YELLOW}WARNING: Could not restore branch ${current_branch}${RESET}"
            echo "$restore_output" | sed 's/^/  /'
        fi
    fi

    # 結果を格納（現在ブランチ情報付き）
    final_branch=$(git branch --show-current 2>/dev/null) || final_branch="unknown"
    if [[ "$pull_status" == "pull failed" ]]; then
        RESULTS+=("${RED}FAIL${RESET}    ${repo_name} (${default_branch}) [${final_branch}] -- ${pull_status}")
    else
        RESULTS+=("${GREEN}OK${RESET}      ${repo_name} (${default_branch}) [${final_branch}] -- ${pull_status}")
    fi

    echo ""
done

# --- サマリー ---
echo -e "${BOLD}========================================${RESET}"
echo -e "${BOLD} Summary${RESET}"
echo -e "${BOLD}========================================${RESET}"
echo -e " Total:   ${TOTAL}"
echo -e " ${GREEN}Success: ${SUCCESS_COUNT}${RESET}"
echo -e " ${YELLOW}Skipped: ${SKIPPED_COUNT}${RESET}"
echo -e " ${RED}Failed:  ${FAILED_COUNT}${RESET}"
echo ""

for result in "${RESULTS[@]}"; do
    echo -e "  $result"
done

echo ""
echo -e "${BOLD}Done.${RESET}"
