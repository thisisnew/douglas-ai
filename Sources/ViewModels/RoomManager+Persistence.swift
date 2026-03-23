import Foundation

// MARK: - 영속화 + Git Worktree 격리 (RoomPersistenceService로 위임)

extension RoomManager {

    // MARK: - 영속화 (RoomPersistenceService 위임)

    static var roomDirectoryOverride: URL? {
        get { RoomPersistenceService.directoryOverride }
        set { RoomPersistenceService.directoryOverride = newValue }
    }

    static var roomDirectory: URL { RoomPersistenceService.directory }

    func scheduleSave(immediate: Bool = false) {
        if immediate {
            saveTask?.cancel()
            saveRooms()
            return
        }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            saveRooms()
        }
    }

    func saveRooms() { RoomPersistenceService.save(rooms) }

    func loadRooms() {
        rooms = RoomPersistenceService.load()
        cleanupStaleWorktrees()
        let pruned = RoomPersistenceService.pruneCompleted(rooms: rooms, maxKeep: 30)
        if !pruned.isEmpty {
            rooms.removeAll { pruned.contains($0.id) }
        }
        syncAgentStatuses()
    }

    func pruneCompletedRooms(maxKeep: Int) {
        let pruned = RoomPersistenceService.pruneCompleted(rooms: rooms, maxKeep: maxKeep)
        if !pruned.isEmpty {
            rooms.removeAll { pruned.contains($0.id) }
        }
    }

    // MARK: - Git Worktree 격리

    func hasActiveRoomOnPath(_ projectPath: String, excluding roomID: UUID) -> Bool {
        rooms.contains { room in
            room.id != roomID && room.isActive && room.primaryProjectPath == projectPath
        }
    }

    func isGitRepository(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path + "/.git")
    }

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
                rooms[i].setWorktreePath(worktreeDir)
                scheduleSave()
            }
        }
    }

    func cleanupWorktree(roomID: UUID) {
        guard let room = rooms.first(where: { $0.id == roomID }),
              let worktreePath = room.projectContext.worktreePath,
              let projectPath = room.primaryProjectPath else { return }

        let shortID = room.shortID
        if let idx = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[idx].setWorktreePath(nil)
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

    func cleanupStaleWorktrees() {
        for (idx, room) in rooms.enumerated() {
            guard let wt = room.projectContext.worktreePath,
                  let pp = room.primaryProjectPath,
                  !room.isActive else { continue }
            rooms[idx].setWorktreePath(nil)
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
