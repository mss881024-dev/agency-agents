#!/usr/bin/env bash
# Stop 훅: 세션 트랜스크립트를 옵시디언 볼트(mss881024-dev/obsidian-vault)의
# 지식 노트로 정리해 자동 커밋+push한다. 실패해도 세션 종료를 막지 않는다
# (모든 실패 경로는 echo 후 exit 0).
set -uo pipefail

INPUT_JSON=$(cat)
TRANSCRIPT_PATH=$(printf '%s' "$INPUT_JSON" | jq -r '.transcript_path // empty' 2>/dev/null)

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  echo '[옵시디언 동기화 건너뜀: transcript 없음]'
  exit 0
fi

REPO_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
REPO_NAME=$(basename "$REPO_DIR")
VAULT_URL="https://github.com/mss881024-dev/obsidian-vault"

VAULT_DIR="${OBSIDIAN_VAULT_DIR:-}"
if [ -z "$VAULT_DIR" ]; then
  for cand in "$HOME/obsidian-vault" "/workspace/obsidian-vault" "$REPO_DIR/../obsidian-vault"; do
    if [ -d "$cand/.git" ]; then
      VAULT_DIR="$cand"
      break
    fi
  done
fi
if [ -z "$VAULT_DIR" ]; then
  VAULT_DIR="$HOME/obsidian-vault"
  if ! git clone --depth 1 "$VAULT_URL" "$VAULT_DIR" >/tmp/obsidian-sync-clone.log 2>&1; then
    echo "[옵시디언 볼트 clone 실패 - 수동 확인 필요] $(tail -3 /tmp/obsidian-sync-clone.log)"
    exit 0
  fi
fi

(cd "$VAULT_DIR" && git pull --rebase --autostash >/tmp/obsidian-sync-pull.log 2>&1) \
  || echo "[옵시디언 볼트 pull 실패 - 계속 진행] $(tail -3 /tmp/obsidian-sync-pull.log)"

NOTE_DATE=$(date '+%Y-%m-%d')
NOTE_STAMP=$(date '+%Y-%m-%d_%H%M%S')
NOTE_DIR="$VAULT_DIR/Claude 세션 로그/$REPO_NAME"
mkdir -p "$NOTE_DIR"
NOTE_PATH="$NOTE_DIR/${NOTE_STAMP}.md"
MOC_PATH="$VAULT_DIR/00_Claude 세션 로그_MOC.md"

if ! command -v claude >/dev/null 2>&1; then
  echo '[옵시디언 동기화 건너뜀: claude CLI 없음]'
  exit 0
fi

PROMPT="다음은 '$REPO_NAME' 저장소에서 진행된 Claude Code 세션의 트랜스크립트다.
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
- 후속으로 확인이 필요한 사항이 있으면 명시, 없으면 생략

대화 원문을 그대로 옮기지 말고 지식으로 요약하라. 트랜스크립트에 개인정보나
계약금액 등 민감정보가 우연히 포함되어 있어도 그대로 인용하지 말고 요약에서 제외하라.
마크다운 노트 본문만 출력하고 다른 설명은 붙이지 마라."

claude -p "$PROMPT" < "$TRANSCRIPT_PATH" > "$NOTE_PATH" 2>/tmp/obsidian-sync-summarize.log

if [ ! -s "$NOTE_PATH" ]; then
  echo "[옵시디언 노트 생성 실패 - 수동 확인 필요] $(tail -3 /tmp/obsidian-sync-summarize.log)"
  rm -f "$NOTE_PATH"
  exit 0
fi

if [ ! -f "$MOC_PATH" ]; then
  echo "[옵시디언 MOC 없음 - 수동 확인 필요: $MOC_PATH]"
fi

NOTE_BASENAME=$(basename "$NOTE_PATH" .md)
if [ -f "$MOC_PATH" ] && ! grep -qF "$NOTE_BASENAME" "$MOC_PATH" 2>/dev/null; then
  echo "- [[$NOTE_BASENAME]] ($NOTE_DATE, $REPO_NAME)" >> "$MOC_PATH"
fi

cd "$VAULT_DIR" || exit 0
git add -A
if git diff --cached --quiet; then
  echo '[옵시디언: 커밋할 변경사항 없음]'
  exit 0
fi
git commit -m "$REPO_NAME 세션 로그: $NOTE_DATE 자동 세션 노트 추가" >/dev/null 2>&1
git push origin main 2>&1 || echo '[옵시디언 push 실패 - 수동 확인 필요]'
