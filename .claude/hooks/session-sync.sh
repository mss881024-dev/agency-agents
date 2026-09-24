#!/usr/bin/env bash
# 세션 종료(Stop/SessionEnd) 시 저장소 변경사항을 무조건 git에 올리고 main까지 최신화하는 훅.
#
# 순서: (1) 세션 로그 요약 → (2) 전체 변경 커밋 → (3) origin/main 병합 → (4) 현재 브랜치 push
#       → (5) feature 브랜치면 main에도 push (fast-forward)
#
# 설계 원칙
# - 어떤 실패도 세션을 막지 않는다: 항상 exit 0. 실패 사유는 .git/claude-sync/last_status 에 남기고,
#   다음 세션 시작 브리핑(session-start.sh → vault_check.py)이 이를 Claude에게 알린다.
# - 병합 충돌이 나면 병합을 취소하고 현재 브랜치만 push한다(작업물은 절대 잃지 않음). main 반영은 보류.
# - 동시 실행 방지: flock.
# - main 자동 반영을 끄려면 .claude/sync.conf 에 AUTO_PUSH_MAIN=0
# - obsidian-vault / first-project / agency-agents 세 저장소가 이 파일을 똑같이 쓴다(원본: obsidian-vault).
#   고칠 때는 세 곳을 함께 고칠 것.
set -uo pipefail

VAULT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$VAULT_DIR" || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

STATE_DIR="$(git rev-parse --git-dir)/claude-sync"
mkdir -p "$STATE_DIR"
LOG="$STATE_DIR/sync.log"
STATUS_FILE="$STATE_DIR/last_status"
EVENT="${1:-stop}"

AUTO_PUSH_MAIN=1
LOG_HOOK=.claude/hooks/sync-self-session.sh   # 세션 로그 요약 스크립트 (저장소별로 sync.conf에서 지정)
[ -f .claude/sync.conf ] && . ./.claude/sync.conf

input="$(cat 2>/dev/null || true)"

exec 9>"$STATE_DIR/lock"
flock -w 60 9 || { echo "$(date '+%F %T') lock timeout" >>"$LOG"; exit 0; }

log() { echo "$(date '+%F %T') [$EVENT] $*" >>"$LOG"; }
status() { echo "$1 ($(date '+%F %T'), $branch)" >"$STATUS_FILE"; log "$1"; }

retry() { # 네트워크 오류 대비 최대 4회 재시도 (2,4,8,16초)
  local n=0 delay=2
  until "$@" >>"$LOG" 2>&1; do
    n=$((n + 1)); [ $n -ge 4 ] && return 1
    sleep $delay; delay=$((delay * 2))
  done
}

branch="$(git branch --show-current 2>/dev/null)"
if [ -z "$branch" ]; then
  echo "detached HEAD — 자동 동기화 건너뜀 ($(date '+%F %T'))" >"$STATUS_FILE"
  exit 0
fi

# 진행 중인 merge/rebase가 있으면 건드리지 않는다
gd="$(git rev-parse --git-dir)"
if [ -e "$gd/MERGE_HEAD" ] || [ -d "$gd/rebase-merge" ] || [ -d "$gd/rebase-apply" ]; then
  status "FAIL: 진행 중인 merge/rebase가 있어 자동 동기화 보류 — 수동 정리 필요"
  exit 0
fi

# (1) 세션 로그 요약 (실패해도 계속)
[ -f "$LOG_HOOK" ] && { printf '%s' "$input" | bash "$LOG_HOOK" "$EVENT" >>"$LOG" 2>&1 || true; }

# (2) 전체 변경 커밋 (.gitignore 대상 제외)
git add -A >>"$LOG" 2>&1
if ! git diff --cached --quiet; then
  n="$(git diff --cached --name-only | wc -l | tr -d ' ')"
  files="$(git diff --cached --name-only | head -8 | sed 's|.*/||' | paste -sd ',' - | sed 's/,/, /g')"
  [ "$n" -gt 8 ] && files="$files 외 $((n - 8))개"
  git commit -q -m "자동동기화: 세션 종료 시 미커밋 변경 ${n}건 저장 ($(date '+%F %H:%M'))" \
    -m "변경 파일: ${files}" -m "브랜치: ${branch} / 훅: .claude/hooks/session-sync.sh" >>"$LOG" 2>&1 \
    || { status "FAIL: 자동 커밋 실패 — git 설정(user.name/email) 확인 필요"; exit 0; }
fi

# (3) origin/main 최신 내용 병합
merge_ok=1
if retry git fetch origin main; then
  if ! git merge --no-edit -q origin/main >>"$LOG" 2>&1; then
    git merge --abort >>"$LOG" 2>&1 || true
    merge_ok=0
  fi
else
  merge_ok=0
  log "fetch 실패"
fi

# (4) 현재 브랜치 push
if ! retry git push -u origin "HEAD:$branch"; then
  status "FAIL: '$branch' push 실패(네트워크/권한) — 변경은 로컬 커밋에만 있음, 다음 세션에서 재시도"
  exit 0
fi

# (5) main 최신화
if [ "$branch" = "main" ]; then
  if [ $merge_ok = 1 ]; then status "OK: main 커밋·push 완료"; else status "WARN: main push는 했으나 origin/main 병합 실패(충돌 또는 fetch 실패) — 수동 확인 필요"; fi
  exit 0
fi
if [ "${AUTO_PUSH_MAIN:-1}" != "1" ]; then
  status "OK: '$branch' push 완료 (main 자동 반영 꺼짐)"
  exit 0
fi
if [ $merge_ok = 0 ]; then
  status "WARN: '$branch'는 push했으나 main과 충돌(또는 fetch 실패)해 main 반영 보류 — 수동 병합 필요"
  exit 0
fi
if retry git push origin HEAD:main; then
  status "OK: '$branch' push 및 main 반영 완료"
else
  # 그사이 main이 움직였을 수 있음 → 한 번 더 병합 후 재시도
  if retry git fetch origin main && git merge --no-edit -q origin/main >>"$LOG" 2>&1 \
     && retry git push -u origin "HEAD:$branch" && retry git push origin HEAD:main; then
    status "OK: '$branch' push 및 main 반영 완료 (재시도)"
  else
    git merge --abort >/dev/null 2>&1 || true
    status "WARN: '$branch'는 push했으나 main 반영 실패(보호 브랜치/충돌/권한) — 수동 병합 필요"
  fi
fi
exit 0
