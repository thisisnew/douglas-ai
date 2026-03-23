import Foundation

/// Room 영속화 서비스 — JSON 파일 기반 저장/로드
/// RoomManager에서 추출된 인프라 서비스
enum RoomPersistenceService {

    /// 테스트에서 임시 디렉토리로 교체 가능
    static var directoryOverride: URL?

    static var directory: URL {
        if let override = directoryOverride {
            try? FileManager.default.createDirectory(at: override, withIntermediateDirectories: true)
            return override
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agentmanager")
        let dir = appSupport.appendingPathComponent("DOUGLAS/rooms", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static let encoder = JSONEncoder()

    /// 모든 방을 JSON 파일로 저장
    static func save(_ rooms: [Room]) {
        let dir = directory
        for room in rooms {
            let file = dir.appendingPathComponent("\(room.id.uuidString).json")
            if let data = try? encoder.encode(room) {
                try? data.write(to: file)
            }
        }
    }

    /// JSON 파일에서 방 목록 로드 (디코드 실패한 파일은 삭제)
    static func load() -> [Room] {
        let dir = directory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
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
        for file in failedFiles {
            try? FileManager.default.removeItem(at: file)
        }
        return loaded.sorted { $0.createdAt > $1.createdAt }
    }

    /// 완료된 방 프루닝 — maxKeep 개 초과 시 오래된 순서대로 삭제
    /// 반환: 삭제된 방 ID 세트
    @discardableResult
    static func pruneCompleted(rooms: [Room], maxKeep: Int) -> Set<UUID> {
        let completed = rooms
            .filter { !$0.isActive }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
        guard completed.count > maxKeep else { return [] }
        let toRemove = completed.suffix(from: maxKeep)
        let dir = directory
        for room in toRemove {
            for msg in room.messages {
                msg.attachments?.forEach { $0.delete() }
            }
            let file = dir.appendingPathComponent("\(room.id.uuidString).json")
            try? FileManager.default.removeItem(at: file)
        }
        return Set(toRemove.map { $0.id })
    }
}
