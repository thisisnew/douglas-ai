# 워크플로우 불일치 수정 실행 계획

## 컨텍스트

3자 교차 검증으로 확인된 7개 불일치 사항을 수정한다.
모든 수정은 `Sources/ViewModels/RoomManager.swift` 중심, 일부 `WorkflowIntent.swift` 수정 포함.

---

## Step 1: 계획 승인/요건 추가 루프 복원 [C1]

**파일**: `Sources/ViewModels/RoomManager.swift`

**현황**: 3곳에서 `// 승인 게이트 제거 — 라이브 협업` 주석과 함께 계획 생성 후 바로 Build 진입
- `executeSoloDesign` L3606
- `executeDesignPhase` (multi-agent) L3228
- `executePlanPhase` L4329

**수정 내용**:

계획 승인 루프를 별도 함수로 추출:

```swift
/// 계획 승인 루프: 사용자가 승인할 때까지 계획 재수립 반복
private func awaitPlanApproval(roomID: UUID, task: String, designOutput: String? = nil) async -> Bool {
    while true {
        guard !Task.isCancelled,
              let room = rooms.first(where: { $0.id == roomID }),
              room.isActive, room.plan != nil else { return false }

        // 계획 표시 + 승인 요청
        let plan = room.plan!
        let stepsDesc = plan.steps.enumerated().map { i, s in
            let risk = s.riskLevel == .low ? "" : " [\(s.riskLevel.displayName)]"
            return "\(i + 1). \(s.text)\(risk)"
        }.joined(separator: "\n")

        let approvalMsg = ChatMessage(
            role: .system,
            content: "실행 계획:\n\n\(stepsDesc)\n\n승인하시면 실행을 시작합니다. 수정이 필요하면 요건을 말씀해주세요.",
            messageType: .approvalRequest
        )
        appendMessage(approvalMsg, to: roomID)

        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].transitionTo(.awaitingApproval)
        }
        syncAgentStatuses()
        scheduleSave()

        let approved = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            approvalContinuations[roomID] = cont
        }
        approvalContinuations.removeValue(forKey: roomID)

        if approved {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.inProgress)
            }
            return true
        } else {
            // 거부: 사용자 피드백을 반영하여 계획 재수립
            let feedback = rooms.first(where: { $0.id == roomID })?
                .messages.last(where: { $0.role == .user })?.content ?? ""

            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.planning)
            }

            let retryMsg = ChatMessage(
                role: .system,
                content: "요건을 반영하여 계획을 재수립합니다.",
                messageType: .progress
            )
            appendMessage(retryMsg, to: roomID)

            // 계획 재생성
            let newPlan = await requestPlan(
                roomID: roomID, task: task,
                designOutput: designOutput,
                previousPlan: rooms.first(where: { $0.id == roomID })?.plan,
                feedback: feedback
            )
            if let newPlan, let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].plan = newPlan
            } else {
                return false // 재생성 실패
            }
            // 루프 → 새 계획으로 다시 승인 요청
        }
    }
}
```

**적용 위치 3곳**:

### 1-A. `executeSoloDesign` (L3606 부근)
```swift
// 기존: 계획 표시 후 바로 Build 진입 (승인 게이트 제거)
// 변경: awaitPlanApproval 호출
let _ = await awaitPlanApproval(roomID: roomID, task: task)
scheduleSave()
```

### 1-B. `executeDesignPhase` multi-agent (L3228 부근)
```swift
// 기존: 계획 표시 후 바로 Build 진입
// 변경:
let _ = await awaitPlanApproval(roomID: roomID, task: task, designOutput: finalDesignText)
scheduleSave()
```

### 1-C. `executePlanPhase` (L4329 부근)
```swift
// 기존: 계획 표시 후 바로 실행 진입
// 변경:
let _ = await awaitPlanApproval(roomID: roomID, task: task)
scheduleSave()
```

**requestPlan 시그니처 확장**: `previousPlan`과 `feedback` 파라미터 추가하여 재수립 시 이전 계획 + 피드백을 LLM 컨텍스트에 포함.

---

## Step 2: 마지막 단계 직전 승인 [C2]

**파일**: `Sources/ViewModels/RoomManager.swift`

**현황**: `executeBuildPhase`와 `executeRoomWork`의 step 루프에서 마지막 단계도 자동 실행

**수정 내용**:

### 2-A. `executeBuildPhase` (L3705 루프 내)

step 루프에서 마지막 단계 직전 승인 게이트 추가:

```swift
for (stepIndex, step) in plan.steps.enumerated() {
    // ... 기존 코드 ...

    // 마지막 단계 직전 확인 (step이 2개 이상일 때만)
    if stepIndex == plan.steps.count - 1 && plan.steps.count > 1 {
        let confirmMsg = ChatMessage(
            role: .system,
            content: "마지막 단계입니다. 여기까지 진행된 내용이 괜찮으시면 승인해주세요. 수정이 필요하면 되돌아갈 단계와 요건을 말씀해주세요.",
            messageType: .approvalRequest
        )
        appendMessage(confirmMsg, to: roomID)

        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].transitionTo(.awaitingApproval)
        }
        syncAgentStatuses()
        scheduleSave()

        let approved = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            approvalContinuations[roomID] = cont
        }
        approvalContinuations.removeValue(forKey: roomID)

        if approved {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].transitionTo(.inProgress)
            }
        } else {
            // 거부 → Step 3(롤백) 로직으로 처리
            let feedback = rooms.first(where: { $0.id == roomID })?
                .messages.last(where: { $0.role == .user })?.content ?? ""
            let rollbackIndex = parseRollbackStepIndex(from: feedback, totalSteps: plan.steps.count)
            // rollbackIndex로 점프 (Step 3에서 구현)
        }
    }

    // ... 기존 step 실행 코드 ...
}
```

### 2-B. `executeRoomWork` (L5000 루프 내)

동일한 마지막 단계 확인 게이트를 `executeRoomWork`에도 추가. 기존 `requiresApproval` 게이트 패턴을 재사용.

---

## Step 3: 단계 롤백 기능 [H2]

**파일**: `Sources/ViewModels/RoomManager.swift`

**현황**: for 루프 단방향 진행만 가능

**수정 내용**:

### 3-A. for 루프를 while 루프로 변환

```swift
// 기존:
for (stepIndex, step) in plan.steps.enumerated() { ... }

// 변경:
var stepIndex = 0
while stepIndex < plan.steps.count {
    let step = plan.steps[stepIndex]

    // ... 기존 step 실행 코드 ...

    // 마지막 단계 거부 시 롤백
    if shouldRollback {
        stepIndex = rollbackIndex  // 사용자 지정 단계로 복귀
        continue
    }

    stepIndex += 1
}
```

### 3-B. 롤백 인덱스 파싱 함수

```swift
/// 사용자 피드백에서 롤백 대상 단계 번호 추출
private func parseRollbackStepIndex(from feedback: String, totalSteps: Int) -> Int {
    // "3단계로 돌아가줘", "step 2부터 다시" 등에서 숫자 추출
    let pattern = /(\d+)\s*(단계|step)/
    if let match = feedback.firstMatch(of: pattern),
       let num = Int(match.1),
       num >= 1 && num <= totalSteps {
        return num - 1  // 0-indexed
    }
    // 숫자 없으면 직전 단계로
    return max(0, totalSteps - 2)
}
```

### 3-C. `executeBuildPhase`와 `executeRoomWork` 모두 적용

---

## Step 4: 토론 라운드별 사용자 체크포인트 [H1]

**파일**: `Sources/ViewModels/RoomManager.swift`

**현황**: `executeDiscussionDesign` (L3282)이 Turn1→Turn2→종합까지 사용자 참여 없이 자동 진행

**수정 내용**:

Turn1 (의견 제시) 후, Turn2 (피드백) 전에 사용자 체크포인트 삽입:

```swift
// Turn 1 완료 후 (L3370 이후)
guard !Task.isCancelled, rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

// 사용자 체크포인트: 의견을 듣고 피드백할 기회
let checkpointMsg = ChatMessage(
    role: .system,
    content: "전문가 의견이 나왔습니다. 의견이 있으시면 입력해주세요. 없으면 그대로 진행합니다.",
    messageType: .userQuestion
)
appendMessage(checkpointMsg, to: roomID)

if let i = rooms.firstIndex(where: { $0.id == roomID }) {
    rooms[i].isDiscussionCheckpoint = true
    rooms[i].transitionTo(.awaitingUserInput)
}
syncAgentStatuses()
scheduleSave()

let userFeedback: String = await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
    userInputContinuations[roomID] = cont
}

if let i = rooms.firstIndex(where: { $0.id == roomID }) {
    rooms[i].isDiscussionCheckpoint = false
    rooms[i].transitionTo(.inProgress)
}

// 사용자 피드백이 있으면 Turn2 컨텍스트에 포함
if !userFeedback.isEmpty {
    opinions.append(("사용자", userFeedback))
}

// Turn 2 진행 ...
```

Turn2 완료 후, 종합 전에도 동일한 체크포인트 추가.

---

## Step 5: 이중 계획 생성 방지 [H3]

**파일**: `Sources/ViewModels/RoomManager.swift`

**현황**: `executePlanPhase`에서 plan 생성 → `executeDesignPhase`에서 다시 plan 생성 (덮어쓰기)

**수정 내용**:

### 5-A. `executeDesignPhase`에서 기존 plan 존재 시 재생성 스킵

```swift
// executeDesignPhase 3턴 프로토콜 마지막 (L3220 부근)
// 기존:
let plan = await requestPlan(roomID: roomID, task: task, designOutput: finalDesignText)
if let plan, let i = rooms.firstIndex(where: { $0.id == roomID }) {
    rooms[i].plan = plan
}

// 변경: 이미 Plan phase에서 plan이 생성됐으면 Design 결과를 기존 plan에 merge
if let existingPlan = rooms.first(where: { $0.id == roomID })?.plan {
    // Plan phase에서 이미 생성됨 → Design 결과는 briefing으로만 저장
    if let i = rooms.firstIndex(where: { $0.id == roomID }) {
        rooms[i].clarifySummary = (rooms[i].clarifySummary ?? "") + "\n\n[설계 토론 결과]\n" + finalDesignText
    }
} else {
    let plan = await requestPlan(roomID: roomID, task: task, designOutput: finalDesignText)
    if let plan, let i = rooms.firstIndex(where: { $0.id == roomID }) {
        rooms[i].plan = plan
    }
}
```

---

## Step 6: quickAnswer 팀 확인 [M1]

**파일**: `Sources/ViewModels/RoomManager.swift`

**현황**: L2167-2188에서 QA 에이전트 자동 배정 + return (팀 확인 없음)

**수정 내용**:

```swift
// 기존 L2188:
// return  ← 팀 확인 없이 리턴

// 변경: return 제거 → 폴스루하여 showTeamConfirmation 호출
// quickAnswer도 팀 확인 게이트를 거치도록

if rooms[idx].intent == .quickAnswer {
    let qaNameKWs: Set<String> = ["질의응답", "q&a", "qa"]
    let allSubAgents = agentStore?.subAgents ?? []
    if let qaAgent = allSubAgents.first(where: { ... }) {
        if !rooms[idx].assignedAgentIDs.contains(qaAgent.id) {
            addAgent(qaAgent.id, to: roomID, silent: true)
        }
        if let i = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[i].agentRoles[qaAgent.name] = .creator
        }
        // return 제거 → 아래 showTeamConfirmation으로 폴스루
    }
    // QA 에이전트 없어도 LLM 매칭으로 폴스루
}

// ... (LLM 매칭 로직은 quickAnswer가 아닌 경우에만 실행되도록 조건 추가)

// 6) 팀 구성 확인 게이트 — 모든 intent에서 실행
await showTeamConfirmation(roomID: roomID)
```

단, quickAnswer의 경우 LLM 역할 분석(2318-2451)은 스킵해야 하므로, QA 에이전트 배정 후 바로 showTeamConfirmation으로 점프하는 분기 필요.

---

## Step 7: Clarify phase 재활성화 [M2/M3]

**파일**: `Sources/Models/WorkflowIntent.swift`, `Sources/ViewModels/RoomManager.swift`

**현황**:
- `executeClarifyPhase` 함수 존재하지만 requiredPhases에 .clarify 없음
- Understand 내장 clarify는 max 2회 제한

**수정 방안 (A안: Understand 내장 강화)**:

requiredPhases 변경 없이, Understand의 내장 clarify 루프를 강화:

```swift
// 기존 L2802:
let maxQuestions = 2

// 변경:
let maxQuestions = 5  // 충분한 여유
// + 조건 강화: needsClarification이 false가 될 때까지 반복
// (현재도 needsClarification=false이면 break하므로, maxQuestions만 늘리면 됨)
```

이 방안이 가장 간단하고 기존 아키텍처 변경 최소화.

---

## 빌드/검증

- 각 Step 완료 후 `swift build -c release` 확인
- 모든 Step 완료 후 통합 빌드 + 커밋

## 커밋 계획

각 Step을 개별 커밋 또는 관련 Step을 묶어 커밋:
- `[DG] feat: 계획 승인/요건 추가 루프 복원` (Step 1)
- `[DG] feat: 마지막 단계 직전 승인 + 단계 롤백` (Step 2 + 3)
- `[DG] feat: 토론 라운드별 사용자 체크포인트` (Step 4)
- `[DG] fix: 이중 계획 생성 방지` (Step 5)
- `[DG] fix: quickAnswer 팀 확인 게이트 + clarify 루프 강화` (Step 6 + 7)
