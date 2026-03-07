#!/bin/bash
# check-workflow.sh
# PreToolCall hook: 워크플로우 관련 파일 수정 시 리마인더 출력
#
# 입력: stdin으로 JSON (tool_name, tool_input)
# 출력: stdout 메시지가 Claude context에 주입됨

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; inp=json.load(sys.stdin).get('tool_input',{}); print(inp.get('file_path','') or inp.get('command',''))" 2>/dev/null)

# Edit/Write 도구가 워크플로우 관련 파일을 수정할 때만 체크
if [[ "$TOOL_NAME" != "Edit" && "$TOOL_NAME" != "Write" ]]; then
  exit 0
fi

# 워크플로우 핵심 파일 패턴
WORKFLOW_FILES=(
  "RoomManager.swift"
  "IntentClassifier.swift"
  "WorkflowIntent.swift"
  "WorkflowPhase.swift"
  "DocumentRequestDetector.swift"
  "Room.swift"
  "RoomStatus.swift"
)

MATCHED=false
for pattern in "${WORKFLOW_FILES[@]}"; do
  if [[ "$FILE_PATH" == *"$pattern"* ]]; then
    MATCHED=true
    break
  fi
done

if [[ "$MATCHED" == "true" ]]; then
  echo "[WORKFLOW CHECK] 워크플로우 핵심 파일을 수정하고 있습니다."
  echo "반드시 WORKFLOW_SPEC.md의 플로우(케이스 A~H)와 상태 전이가 깨지지 않는지 확인하세요."
  echo "특히: 승인 게이트, 후속 입력 처리, 예외 흐름(14장)을 점검하세요."
fi
