import Foundation

// MARK: - 영속화 + Git Worktree 격리 (RoomManager 본체에서 분리)

extension RoomManager {

    // MARK: - 영속화

    /// 테스트에서 임시 디렉토리로 교체 가능 (프로덕션에서는 nil)
    static var roomDirectoryOverride: URL?

    static var roomDirectory: URL {
        if let override = roomDirectoryOverride {
            try? FileManager.default.createDirectory(at: override, withIntermediateDirectories: true)
            return override
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agentmanager")
        let dir = appSupport.appendingPathComponent("DOUGLAS/rooms", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            saveRooms()
        }
    }

    private static let roomEncoder = JSONEncoder()

    func saveRooms() {
        let dir = Self.roomDirectory
        for room in rooms {
            let file = dir.appendingPathComponent("\(room.id.uuidString).json")
            if let data = try? Self.roomEncoder.encode(room) {
                try? data.write(to: file)
            }
        }
    }

    func loadRooms() {
        let dir = Self.roomDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        var loaded: [Room] = []
        var failedFiles: [URL] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let room = try? JSONDecoder().decode(Room.self, from: data) {
                loaded.append(room)
            } else {
                failedFiles.append(file)
            }
        }
        // 디코드 실패한 고아 JSON 파일 삭제
        for file in failedFiles {
            try? FileManager.default.removeItem(at: file)
        }
        rooms = loaded.sorted { $0.createdAt > $1.createdAt }
        // 비활성 방의 잔여 worktree 정리
        cleanupStaleWorktrees()
        // 완료된 방 프루닝 — 최근 30개만 유지
        pruneCompletedRooms(maxKeep: 30)
        syncAgentStatuses()
    }

    /// 완료된 방이 maxKeep 개를 초과하면 오래된 순서대로 삭제
    func pruneCompletedRooms(maxKeep: Int) {
        let completed = rooms
            .filter { !$0.isActive }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
        guard completed.count > maxKeep else { return }
        let toRemove = completed.suffix(from: maxKeep)
        let dir = Self.roomDirectory
        for room in toRemove {
            // 첨부 이미지 파일 삭제
            for msg in room.messages {
                msg.attachments?.forEach { $0.delete() }
            }
            // JSON 파일 삭제
            let file = dir.appendingPathComponent("\(room.id.uuidString).json")
            try? FileManager.default.removeItem(at: file)
        }
        let removeIDs = Set(toRemove.map { $0.id })
        rooms.removeAll { removeIDs.contains($0.id) }
    }

    // MARK: - Git Worktree 격리

    /// 같은 projectPath에 다른 활성 방이 있는지 확인
    func hasActiveRoomOnPath(_ projectPath: String, excluding roomID: UUID) -> Bool {
        rooms.contains { room in
            room.id != roomID && room.isActive && room.primaryProjectPath == projectPath
        }
    }

    /// projectPath가 git 저장소인지 확인
    func isGitRepository(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path + "/.git")
    }

    /// 동일 projectPath 충돌 시 worktree 생성 (lazy)
    func createWorktreeIfNeeded(roomID: UUID) async {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }),
              let projectPath = rooms[idx].primaryProjectPath,
              rooms[idx].projectContext.worktreePath == nil,
              isGitRepository(projectPath),
              hasActiveRoomOnPath(projectPath, excluding: roomID) else { return }

        let shortID = rooms[idx].shortID
        let worktreeDir = projectPath + "/.douglas/worktrees/" + shortID
        let branchName = "douglas/room-" + shortID

        try? FileManager.default.createDirectory(
            atPath: projectPath + "/.douglas/worktrees",
            withIntermediateDirectories: true, attributes: nil
        )

        let result = await ProcessRunner.run(
            executable: "/usr/bin/git",
            args: ["worktree", "add", worktreeDir, "-b", branchName],
            workDir: projectPath
        )

        if result.exitCode == 0 {
            if let i = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[i].projectContext.setWorktreePath(worktreeDir)
                scheduleSave()
            }
        }
        // 실패 시 원본 디렉토리 사용 (graceful degradation)
    }

    /// worktree 정리 (fire-and-forget)
    func cleanupWorktree(roomID: UUID) {
        guard let room = rooms.first(where: { $0.id == roomID }),
              let worktreePath = room.projectContext.worktreePath,
              let projectPath = room.primaryProjectPath else { return }

        let shortID = room.shortID
        if let idx = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[idx].projectContext.setWorktreePath(nil)
        }

        Task.detached {
            let _ = await ProcessRunner.run(
                executable: "/usr/bin/git",
                args: ["worktree", "remove", worktreePath, "--force"],
                workDir: projectPath
            )
            let _ = await ProcessRunner.run(
                executable: "/usr/bin/git",
                args: ["branch", "-D", "douglas/room-" + shortID],
                workDir: projectPath
            )
        }
    }

    /// 앱 재시작 시 비활성 방의 잔여 worktree 정리
    func cleanupStaleWorktrees() {
        for (idx, room) in rooms.enumerated() {
            guard let wt = room.projectContext.worktreePath,
                  let pp = room.primaryProjectPath,
                  !room.isActive else { continue }
            rooms[idx].projectContext.setWorktreePath(nil)
            Task.detached {
                let _ = await ProcessRunner.run(
                    executable: "/usr/bin/git",
                    args: ["worktree", "remove", wt, "--force"],
                    workDir: pp
                )
            }
        }
    }
}
