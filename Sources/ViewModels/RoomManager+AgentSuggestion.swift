import Foundation

// MARK: - 에이전트 생성 제안 관리 (RoomManager 본체에서 분리)

extension RoomManager {

    // MARK: - 에이전트 생성 제안 관리

    /// 방에 에이전트 생성 제안 추가
    func addAgentSuggestion(_ suggestion: RoomAgentSuggestion, to roomID: UUID) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        rooms[idx].pendingAgentSuggestions.append(suggestion)

        let msg = ChatMessage(
            role: .system,
            content: "\(suggestion.suggestedBy)\(subjectParticle(for: suggestion.suggestedBy)) '\(suggestion.name)' 에이전트 생성을 제안했습니다.\(suggestion.reason.isEmpty ? "" : " 사유: \(suggestion.reason)")",
            messageType: .suggestion
        )
        appendMessage(msg, to: roomID)
        scheduleSave()
    }

    /// 에이전트 생성 제안 승인 → 에이전트 생성 + 방에 초대
    func approveAgentSuggestion(suggestionID: UUID, in roomID: UUID) {
        guard let roomIdx = rooms.firstIndex(where: { $0.id == roomID }),
              let sugIdx = rooms[roomIdx].pendingAgentSuggestions.firstIndex(where: { $0.id == suggestionID }) else { return }

        var suggestion = rooms[roomIdx].pendingAgentSuggestions[sugIdx]
        suggestion.status = .approved
        rooms[roomIdx].pendingAgentSuggestions[sugIdx] = suggestion

        // 에이전트 생성
        let providerName = suggestion.recommendedProvider ?? "Anthropic"
        let modelName = suggestion.recommendedModel ?? "claude-sonnet-4-20250514"

        let newAgent = Agent(
            name: suggestion.name,
            persona: suggestion.persona,
            providerName: providerName,
            modelName: modelName,
            skillTags: suggestion.skillTags ?? [],
            outputStyles: suggestion.outputStyles ?? []
        )
        agentStore?.addAgent(newAgent)
        addAgent(newAgent.id, to: roomID, silent: true)

        let msg = ChatMessage(
            role: .system,
            content: "'\(suggestion.name)' 에이전트가 생성되었습니다."
        )
        appendMessage(msg, to: roomID)
        scheduleSave()
        resumeSuggestionContinuationIfResolved(roomID: roomID)
    }

    /// 에이전트 생성 제안 거부
    func rejectAgentSuggestion(suggestionID: UUID, in roomID: UUID) {
        guard let roomIdx = rooms.firstIndex(where: { $0.id == roomID }),
              let sugIdx = rooms[roomIdx].pendingAgentSuggestions.firstIndex(where: { $0.id == suggestionID }) else { return }

        rooms[roomIdx].pendingAgentSuggestions[sugIdx].status = .rejected

        let name = rooms[roomIdx].pendingAgentSuggestions[sugIdx].name
        let msg = ChatMessage(
            role: .system,
            content: "'\(name)' 에이전트 생성이 취소되었습니다."
        )
        appendMessage(msg, to: roomID)
        scheduleSave()
        resumeSuggestionContinuationIfResolved(roomID: roomID)
    }

    /// 모든 제안이 해결되면 대기 중인 continuation 재개
    func resumeSuggestionContinuationIfResolved(roomID: UUID) {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return }
        let hasPending = room.pendingAgentSuggestions.contains { $0.status == .pending }
        if !hasPending {
            approvalGates.approveSuggestion(roomID: roomID)
        }
    }

    /// 제안 응답 대기 — 사용자가 추가/건너뛰기를 누를 때까지 무한 대기
    func waitForSuggestionResponse(roomID: UUID) async {
        guard let room = rooms.first(where: { $0.id == roomID }),
              room.pendingAgentSuggestions.contains(where: { $0.status == .pending }) else {
            return
        }

        let _ = await approvalGates.waitForSuggestionResponse(roomID: roomID)
    }

    /// 에이전트 제안 취소 후: 기존 에이전트 피커를 표시하거나, 후보가 없으면 워크플로우 완료
    /// 팀 구성 확인 게이트: 자동 매칭된 에이전트를 사용자에게 확인받거나 변경 허용
    /// WORKFLOW_SPEC §6.4: 조건 충족 시 자동 진행 (사용자 확인 스킵)
    func showTeamConfirmation(roomID: UUID, individuallyApproved: Bool = false) async {
        let subAgents = agentStore?.subAgents ?? []
        let roomAgentIDs = rooms.first(where: { $0.id == roomID })?.assignedAgentIDs ?? []
        let specialists = executingAgentIDs(in: roomID)
        let candidates = subAgents.filter { !roomAgentIDs.contains($0.id) }.map(\.id)

        // 에이전트도 없고 후보도 없으면 → 워크플로우 완료
        if specialists.isEmpty && candidates.isEmpty {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].complete()
            }
            syncAgentStatuses()
            scheduleSave()
            return
        }

        // 개별 suggested 에이전트 승인을 이미 거쳤으면 자동 진행 (§6.4 확장)
        if individuallyApproved {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].recordApproval(
                    ApprovalRecord(type: .teamConfirmation, approved: true, feedback: "개별 승인 완료 → 자동 진행")
                )
            }
            scheduleSave()
            return
        }

        // §6.4 자동 진행 판단
        if let room = rooms.first(where: { $0.id == roomID }) {
            let intentConfidence = room.requests.last?.intentClassification?.confidence ?? .medium
            let intent = room.workflowState.intent ?? .task
            let risk = room.taskBrief?.overallRisk ?? .medium
            let suggestedCount = candidates.count - specialists.count  // 미배정 후보 수
            let autoApprove = ApprovalPolicy.shouldAutoApproveTeam(
                intentConfidence: intentConfidence,
                intent: intent,
                overallRisk: risk,
                matchedAgentCount: specialists.count,
                suggestedAgentCount: max(0, suggestedCount)
            )
            if autoApprove {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].recordApproval(
                        ApprovalRecord(type: .teamConfirmation, approved: true, feedback: "자동 진행 (§6.4)")
                    )
                }
                scheduleSave()
                return
            }
        }

        // 팀 확인 카드 표시 → 사용자 응답 대기
        pendingTeamConfirmation[roomID] = TeamConfirmationState(
            selectedAgentIDs: Set(specialists),
            candidateAgentIDs: candidates
        )

        let result = await approvalGates.waitForTeamConfirmation(roomID: roomID)

        guard !Task.isCancelled, rooms.first(where: { $0.id == roomID })?.isActive == true else { return }

        // nil → 건너뛰기
        guard let finalIDs = result else {
            if executingAgentIDs(in: roomID).isEmpty {
                if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                    rooms[i].complete()
                }
                syncAgentStatuses()
                scheduleSave()
            }
            return
        }

        // 차이 적용: 제거할 에이전트 / 추가할 에이전트
        let currentSpecialists = Set(executingAgentIDs(in: roomID))
        let toRemove = currentSpecialists.subtracting(finalIDs)
        let toAdd = finalIDs.subtracting(currentSpecialists)

        if let idx = rooms.firstIndex(where: { $0.id == roomID }) {
            for agentID in toRemove {
                rooms[idx].removeAgent(agentID)
            }
        }
        for agentID in toAdd {
            addAgent(agentID, to: roomID, silent: true)
        }

        // 최종 팀 확정 메시지 (RuntimeRole 포함)
        let masterName = agentStore?.masterAgent?.name ?? "DOUGLAS"
        let room = rooms.first(where: { $0.id == roomID })
        let finalDescs = executingAgentIDs(in: roomID).compactMap { id -> String? in
            guard let name = agentStore?.agents.first(where: { $0.id == id })?.name else { return nil }
            if let role = room?.agentRoles[id] {
                return "\(name)(\(role.displayName))"
            }
            return name
        }
        if !finalDescs.isEmpty {
            let msg = ChatMessage(
                role: .system,
                content: "\(finalDescs.joined(separator: ", "))님이 참여합니다.",
                agentName: masterName
            )
            appendMessage(msg, to: roomID)
        }

        // 최종적으로 에이전트 없으면 완료
        if executingAgentIDs(in: roomID).isEmpty {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].complete()
            }
            syncAgentStatuses()
            scheduleSave()
        }
    }

    // MARK: - 방에 에이전트 추가

    func addAgent(_ agentID: UUID, to roomID: UUID, silent: Bool = false) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        guard !rooms[idx].assignedAgentIDs.contains(agentID) else { return }
        rooms[idx].addAgent(agentID)

        // 에이전트의 참조 프로젝트를 방에 병합
        if let agent = agentStore?.agents.first(where: { $0.id == agentID }) {
            for path in agent.referenceProjectPaths {
                rooms[idx].addProjectPath(path)
            }
        }

        syncAgentStatuses()
        scheduleSave()

        let agentName = agentStore?.agents.first(where: { $0.id == agentID })?.name
        if !silent, let agentName {
            let systemMsg = ChatMessage(role: .system, content: "\(agentName)\(subjectParticle(for: agentName)) 방에 참여했습니다.")
            appendMessage(systemMsg, to: roomID)
        }

        // 플러그인 이벤트
        if let agentName {
            pluginEventDelegate?(.agentInvited(roomID: roomID, agentName: agentName))
        }
    }
}
