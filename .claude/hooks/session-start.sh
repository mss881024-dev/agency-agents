#!/usr/bin/env bash
# 세션 시작(SessionStart) 훅 (obsidian-vault·first-project·agency-agents 공통): origin/main 최신 내용을 현재 브랜치로 가져오고,
# Vault 자동점검 브리핑을 Claude 컨텍스트로 주입한다(이 스크립트의 stdout이 컨텍스트가 됨).
# 어떤 실패도 세션을 막지 않는다: 항상 exit 0.
set -uo pipefail

VAULT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$VAULT_DIR" || exit 0
cat >/dev/null 2>&1 || true   # 훅 입력(JSON)은 사용하지 않음

STATE_DIR="$(git rev-parse --git-dir 2>/dev/null)/claude-sync"
mkdir -p "$STATE_DIR" 2>/dev/null
LOG="$STATE_DIR/sync.log"
branch="$(git branch --show-current 2>/dev/null)"

# 1) 최신화: origin/main + (feature 브랜치면) 원격의 자기 브랜치
if [ -n "$branch" ] && git fetch -q origin >>"$LOG" 2>&1; then
  for ref in "origin/$branch" origin/main; do
    git rev-parse -q --verify "$ref" >/dev/null || continue
    if ! git merge --no-edit -q "$ref" >>"$LOG" 2>&1; then
      git merge --abort >/dev/null 2>&1 || true
      echo "⚠ 세션 시작 시 ${ref} 병합 충돌 — 자동 병합을 취소했습니다. 작업 전에 사용자에게 알리고 수동 병합을 제안하세요."
    fi
  done
else
  echo "⚠ 세션 시작 시 원격 fetch 실패 — Vault가 최신이 아닐 수 있습니다."
fi

# 2) 자동점검 브리핑 (리포트 노트도 갱신)
PY="$(command -v python3 || command -v python)"
if [ -n "$PY" ] && [ -f scripts/vault_check.py ]; then
  "$PY" scripts/vault_check.py 2>>"$LOG" || true
fi
exit 0
