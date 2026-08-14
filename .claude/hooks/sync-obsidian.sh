#!/usr/bin/env bash
# Stop 훅: 세션 트랜스크립트를 옵시디언 볼트(mss881024-dev/obsidian-vault)의
# 지식 노트로 정리해 자동 커밋+push한다. 실패해도 세션 종료를 막지 않는다
# (모든 실패 경로는 echo 후 exit 0). Stop은 세션 전체가 아니라 매 턴 종료마다
# 발생하므로, session_id 기준으로 노트 파일을 고정해 매번 새 파일을 만들지
# 않고 같은 파일을 갱신한다.
set -uo pipefail

INPUT_JSON=$(cat)
TRANSCRIPT_PATH=$(printf '%s' "$INPUT_JSON" | jq -r '.transcript_path // empty' 2>/dev/null)
SESSION_ID=$(printf '%s' "$INPUT_JSON" | jq -r '.session_id // empty' 2>/dev/null)

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  echo '[옵시디언 동기화 건너뜀: transcript 없음]'
  exit 0
fi
if [ -z "$SESSION_ID" ]; then
  SESSION_ID=$(basename "$TRANSCRIPT_PATH" .jsonl)
fi
if ! command -v claude >/dev/null 2>&1; then
  echo '[옵시디언 동기화 건너뜀: claude CLI 없음]'
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

# 이 스크립트는 항상 main에 커밋+push한다. VAULT_DIR가 다른 브랜치를
# 체크아웃한 상태(예: 사람이나 다른 세션이 같은 클론에서 별도 작업 중)면
# 절대 손대지 않고 조용히 건너뛴다 — 엉뚱한 브랜치에 커밋되거나 남의
# 진행 중인 작업을 건드리는 사고를 막기 위함 (실제로 한 번 발생했었음).
CURRENT_BRANCH=$(git -C "$VAULT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ "$CURRENT_BRANCH" != "main" ]; then
  echo "[옵시디언 동기화 건너뜀: $VAULT_DIR 가 main이 아니라 '$CURRENT_BRANCH' 브랜치 상태]"
  exit 0
fi

(cd "$VAULT_DIR" && git pull --rebase --autostash >/tmp/obsidian-sync-pull.log 2>&1) \
  || echo "[옵시디언 볼트 pull 실패 - 계속 진행] $(tail -3 /tmp/obsidian-sync-pull.log)"

NOTE_DATE=$(date '+%Y-%m-%d')
NOTE_DIR="$VAULT_DIR/Claude 세션 로그/$REPO_NAME"
mkdir -p "$NOTE_DIR"
NOTE_PATH="$NOTE_DIR/${SESSION_ID}.md"
NOTE_EXISTED=0
[ -f "$NOTE_PATH" ] && NOTE_EXISTED=1
MOC_PATH="$VAULT_DIR/00_Claude 세션 로그_MOC.md"

# 트랜스크립트(JSONL)에서 tool_use/tool_result/thinking/이미지 등을 제외한
# 순수 텍스트 turn만 추출한다 — 원문 그대로 옮기지 않기 위함이자, 큰 첨부/툴
# 출력이 그대로 노트나 프롬프트에 섞여 들어가는 것을 막기 위함이다.
PLAIN_TEXT=$(jq -r '
  select(.type=="user" or .type=="assistant")
  | .message as $m
  | ($m.content) as $c
  | if ($c|type) == "string" then
      "\($m.role // .type | ascii_upcase): \($c)"
    else
      ($c[]? | select(.type=="text") | "\($m.role // "assistant" | ascii_upcase): \(.text)")
    end
' "$TRANSCRIPT_PATH" 2>/dev/null)

TEXT_LEN=${#PLAIN_TEXT}
MAX_LEN=150000
if [ "$TEXT_LEN" -gt "$MAX_LEN" ]; then
  HEAD_PART=$(printf '%s' "$PLAIN_TEXT" | head -c 20000)
  TAIL_PART=$(printf '%s' "$PLAIN_TEXT" | tail -c 130000)
  PLAIN_TEXT="${HEAD_PART}

...(중략: 세션이 길어 중간 내용 생략)...

${TAIL_PART}"
fi

if [ -z "$PLAIN_TEXT" ]; then
  echo '[옵시디언 동기화 건너뜀: 추출된 텍스트 없음]'
  exit 0
fi

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
- 후속으로 확인이 필요한 사항이 있으면 명시, 없으면 생략

대화 원문을 그대로 옮기지 말고 지식으로 요약하라. 대화에 개인정보나 계약금액 등
민감정보가 우연히 포함되어 있어도 그대로 인용하지 말고 요약에서 제외하라.
마크다운 노트 본문만 출력하고, 그 외 설명·인사말·코드펜스는 절대 붙이지 마라."

# --tools "": 모든 도구 비활성화(순수 텍스트 생성만, Bash 등으로 재귀 호출 불가)
# --setting-sources "": 어떤 settings.json/hooks/plugin도 로드하지 않음
#   (재귀적으로 Stop 훅이 다시 걸리는 것을 방지 — --bare는 OAuth 인증을
#   차단해 이 환경에서 쓸 수 없으므로 대신 이 조합을 쓴다)
# --no-session-persistence: 요약용 세션을 디스크에 남기지 않음
printf '%s' "$PLAIN_TEXT" | claude -p "$PROMPT" \
  --tools "" \
  --setting-sources "" \
  --no-session-persistence \
  --max-budget-usd 2 \
  > "$NOTE_PATH.tmp" 2>/tmp/obsidian-sync-summarize.log

if [ ! -s "$NOTE_PATH.tmp" ] || ! head -1 "$NOTE_PATH.tmp" | grep -q '^### Title'; then
  echo "[옵시디언 노트 생성 실패 - 수동 확인 필요] $(tail -3 /tmp/obsidian-sync-summarize.log 2>/dev/null) $(head -c 200 "$NOTE_PATH.tmp" 2>/dev/null)"
  rm -f "$NOTE_PATH.tmp"
  exit 0
fi
mv "$NOTE_PATH.tmp" "$NOTE_PATH"

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
if [ "$NOTE_EXISTED" -eq 1 ]; then
  COMMIT_MSG="$REPO_NAME 세션 로그: $NOTE_DATE 세션 노트 갱신 ($SESSION_ID)"
else
  COMMIT_MSG="$REPO_NAME 세션 로그: $NOTE_DATE 세션 노트 추가 ($SESSION_ID)"
fi
git commit -m "$COMMIT_MSG" >/dev/null 2>&1
git push origin main 2>&1 || echo '[옵시디언 push 실패 - 수동 확인 필요]'
