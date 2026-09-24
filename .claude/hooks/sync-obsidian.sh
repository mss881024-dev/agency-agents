#!/usr/bin/env bash
# 세션 트랜스크립트를 옵시디언 볼트(mss881024-dev/obsidian-vault, private)의 지식 노트로 요약해
# 볼트 main에 커밋+push한다. session-sync.sh가 호출한다(sync.conf의 LOG_HOOK). 실패해도 exit 0.
#
# 2026-09-24 개편:
# - 볼트 전용 캐시 클론($HOME/.cache/claude-obsidian-vault-sync)만 사용한다. 사람이 쓰는 볼트 클론이나
#   다른 세션의 작업 클론(보통 claude/* 브랜치)은 건드리지 않는다. 예전에는 작업 클론이 main이
#   아니면 건너뛰어서, 클라우드 세션(항상 claude/* 브랜치) 로그가 거의 남지 않았다(08-14 이후 0건).
# - Stop은 매 턴 발생하므로 요약은 15분에 한 번만 갱신한다. SessionEnd("end")에서는 항상 갱신한다.
# - push가 거절되면(다른 세션이 먼저 push) rebase 후 최대 4회 재시도한다.
# - 요약본만 볼트로 간다. 트랜스크립트 원문은 어디에도 저장·전송하지 않는다.
# - 이 파일은 first-project·agency-agents에 똑같이 들어 있다. 고칠 때는 두 곳을 함께 고칠 것.
set -uo pipefail

EVENT="${1:-stop}"
INPUT_JSON=$(cat)
TRANSCRIPT_PATH=$(printf '%s' "$INPUT_JSON" | jq -r '.transcript_path // empty' 2>/dev/null)
SESSION_ID=$(printf '%s' "$INPUT_JSON" | jq -r '.session_id // empty' 2>/dev/null)

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  echo '[옵시디언 동기화 건너뜀: transcript 없음]'; exit 0
fi
[ -z "$SESSION_ID" ] && SESSION_ID=$(basename "$TRANSCRIPT_PATH" .jsonl)
command -v claude >/dev/null 2>&1 || { echo '[옵시디언 동기화 건너뜀: claude CLI 없음]'; exit 0; }

REPO_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
REPO_NAME=$(basename "$REPO_DIR")
VAULT_URL="https://github.com/mss881024-dev/obsidian-vault"
VAULT_DIR="${OBSIDIAN_VAULT_SYNC_DIR:-$HOME/.cache/claude-obsidian-vault-sync}"

STATE_DIR="$(git -C "$REPO_DIR" rev-parse --absolute-git-dir 2>/dev/null)/claude-sync"
mkdir -p "$STATE_DIR" 2>/dev/null
STAMP="$STATE_DIR/log-${SESSION_ID}.last"
if [ "$EVENT" != "end" ] && [ -f "$STAMP" ] && [ $(( $(date +%s) - $(cat "$STAMP") )) -lt 900 ]; then
  exit 0
fi

# 전용 캐시 클론 준비 → 항상 origin/main과 동일하게 맞춘다(이 클론에는 사람 작업이 없으므로 안전)
if [ ! -d "$VAULT_DIR/.git" ]; then
  mkdir -p "$(dirname "$VAULT_DIR")"
  if ! git clone -q --depth 20 "$VAULT_URL" "$VAULT_DIR" >/tmp/obsidian-sync-clone.log 2>&1; then
    echo "[옵시디언 볼트 clone 실패 — 이 환경에서 obsidian-vault 접근 권한 확인 필요] $(tail -2 /tmp/obsidian-sync-clone.log)"
    exit 0
  fi
fi
cd "$VAULT_DIR" || exit 0
git fetch -q origin main >/dev/null 2>&1 && git checkout -q -B main origin/main >/dev/null 2>&1 \
  || { echo '[옵시디언 볼트 fetch 실패 — 다음 턴에 재시도]'; exit 0; }

NOTE_DATE=$(date '+%Y-%m-%d')
NOTE_DIR="$VAULT_DIR/Claude 세션 로그/$REPO_NAME"
mkdir -p "$NOTE_DIR"
NOTE_PATH="$NOTE_DIR/${SESSION_ID}.md"
NOTE_EXISTED=0; [ -f "$NOTE_PATH" ] && NOTE_EXISTED=1
MOC_PATH="$VAULT_DIR/00_Claude 세션 로그_MOC.md"

# 트랜스크립트(JSONL)에서 사람이 읽는 텍스트 turn만 추출 (도구 출력·첨부 제외)
PLAIN_TEXT=$(jq -r '
  select(.type=="user" or .type=="assistant")
  | .message as $m | ($m.content) as $c
  | if ($c|type) == "string" then "\($m.role // .type | ascii_upcase): \($c)"
    else ($c[]? | select(.type=="text") | "\($m.role // "assistant" | ascii_upcase): \(.text)") end
' "$TRANSCRIPT_PATH" 2>/dev/null)
if [ ${#PLAIN_TEXT} -gt 150000 ]; then
  PLAIN_TEXT="$(printf '%s' "$PLAIN_TEXT" | head -c 20000)

...(중략: 세션이 길어 중간 내용 생략)...

$(printf '%s' "$PLAIN_TEXT" | tail -c 130000)"
fi
[ -z "$PLAIN_TEXT" ] && { echo '[옵시디언 동기화 건너뜀: 추출된 텍스트 없음]'; exit 0; }

PROMPT="다음은 '$REPO_NAME' 저장소에서 진행 중인 Claude Code 세션의 대화 내용이다(도구 호출 결과는 제외하고 사람이 읽는 텍스트만 추출됨).
이 볼트(AI-POS)의 노트 형식 규칙(AI-POS/OBSIDIAN_GUIDE.md)을 따라 지식 노트로 정리하라.

반드시 아래 헤더 블록으로 시작하고 그대로 출력하라 (Project 필드는 생략):

### Title
<세션 핵심 주제를 담은 한 줄 제목>
### Type
Claude 세션로그
### Date
$NOTE_DATE
### Tags
claude-session,$REPO_NAME
### Status
완료
### Related
[[00_Claude 세션 로그_MOC]]

그다음 '# <제목>' 아래 본문에 포함할 것:
- 결론 먼저(BLUF): 무엇을 요청받았고 무엇을 했는지 한두 문장
- 주요 결정사항과 그 이유
- 변경/생성된 파일이나 산출물 목록
- 사용자가 AI 판단을 바로잡은 내용(있으면) — 같은 오해 반복 방지용
- 후속 확인 필요 사항: '- [ ] 내용 (요청일: $NOTE_DATE, 기한: YYYY-MM-DD 또는 미정)' 형식. 없으면 생략

대화 원문을 그대로 옮기지 말고 지식으로 요약하라. 개인정보나 계약금액 등
민감정보가 우연히 포함되어 있어도 그대로 인용하지 말고 요약에서 제외하라.
마크다운 노트 본문만 출력하고, 그 외 설명·인사말·코드펜스는 절대 붙이지 마라."

# --tools "": 도구 비활성화(재귀 호출 방지) / --setting-sources "": 훅·플러그인 미로드
printf '%s' "$PLAIN_TEXT" | timeout 150 claude -p "$PROMPT" \
  --tools "" --setting-sources "" --no-session-persistence --max-budget-usd 2 \
  > "$NOTE_PATH.tmp" 2>/tmp/obsidian-sync-summarize.log

if [ ! -s "$NOTE_PATH.tmp" ] || ! head -1 "$NOTE_PATH.tmp" | grep -q '^### Title'; then
  echo "[옵시디언 노트 생성 실패] $(tail -3 /tmp/obsidian-sync-summarize.log 2>/dev/null)"
  rm -f "$NOTE_PATH.tmp"; exit 0
fi
mv "$NOTE_PATH.tmp" "$NOTE_PATH"

NOTE_BASENAME=$(basename "$NOTE_PATH" .md)
if [ -f "$MOC_PATH" ] && ! grep -qF "$NOTE_BASENAME" "$MOC_PATH"; then
  echo "- [[$NOTE_BASENAME]] ($NOTE_DATE, $REPO_NAME)" >> "$MOC_PATH"
fi

git add "Claude 세션 로그" "00_Claude 세션 로그_MOC.md" 2>/dev/null
if git diff --cached --quiet; then date +%s > "$STAMP"; exit 0; fi
if [ "$NOTE_EXISTED" -eq 1 ]; then VERB="갱신"; else VERB="추가"; fi
git commit -q -m "$REPO_NAME 세션 로그: $NOTE_DATE 세션 노트 $VERB ($SESSION_ID)" >/dev/null 2>&1

n=0; delay=2
until git push -q origin main >/dev/null 2>&1; do
  n=$((n + 1))
  if [ $n -ge 4 ]; then echo '[옵시디언 push 실패 — 다음 턴에 재시도]'; exit 0; fi
  sleep $delay; delay=$((delay * 2))
  git pull -q --rebase origin main >/dev/null 2>&1 || { git rebase --abort >/dev/null 2>&1; git reset -q --hard origin/main; echo '[옵시디언 rebase 충돌 — 다음 턴에 재생성]'; exit 0; }
done
date +%s > "$STAMP"
echo "[옵시디언 세션 로그 $VERB 완료: $REPO_NAME/$SESSION_ID]"
exit 0
