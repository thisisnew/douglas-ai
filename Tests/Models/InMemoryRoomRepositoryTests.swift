import Testing
import Foundation
@testable import DOUGLAS

@Suite("InMemoryRoomRepository")
struct InMemoryRoomRepositoryTests {

    private static func makeRoom(title: String = "테스트") -> Room {
        Room(title: title, assignedAgentIDs: [], createdBy: .user)
    }

    @Test("save + findByID — 저장 후 조회")
    @MainActor
    func saveAndFind() {
        let repo = InMemoryRoomRepository()
        let room = Self.makeRoom()

        repo.save(room)

        let found = repo.findByID(room.id)
        #expect(found?.id == room.id)
        #expect(found?.title == "테스트")
    }

    @Test("findByID — 없는 ID는 nil")
    @MainActor
    func findByID_notFound() {
        let repo = InMemoryRoomRepository()
        #expect(repo.findByID(UUID()) == nil)
    }

    @Test("findAll — 전체 조회")
    @MainActor
    func findAll() {
        let repo = InMemoryRoomRepository()
        repo.save(Self.makeRoom(title: "A"))
        repo.save(Self.makeRoom(title: "B"))

        let all = repo.findAll()
        #expect(all.count == 2)
    }

    @Test("update — 방 상태 변경")
    @MainActor
    func update() {
        let repo = InMemoryRoomRepository()
        let room = Self.makeRoom()
        repo.save(room)

        repo.update(room.id) { r in
            r.transitionTo(.inProgress)
        }

        let updated = repo.findByID(room.id)
        #expect(updated?.status == .inProgress)
    }

    @Test("update — 없는 ID는 무시")
    @MainActor
    func update_notFound() {
        let repo = InMemoryRoomRepository()
        // 크래시 없이 무시
        repo.update(UUID()) { _ in }
    }

    @Test("delete — 삭제 후 조회 불가")
    @MainActor
    func delete() {
        let repo = InMemoryRoomRepository()
        let room = Self.makeRoom()
        repo.save(room)

        repo.delete(id: room.id)

        #expect(repo.findByID(room.id) == nil)
        #expect(repo.findAll().isEmpty)
    }

    @Test("delete — 없는 ID는 무시")
    @MainActor
    func delete_notFound() {
        let repo = InMemoryRoomRepository()
        repo.delete(id: UUID())  // 크래시 없이 무시
    }

    @Test("save — 같은 ID로 저장하면 업데이트")
    @MainActor
    func save_upsert() {
        let repo = InMemoryRoomRepository()
        var room = Self.makeRoom(title: "원본")
        repo.save(room)

        room.transitionTo(.inProgress)
        repo.save(room)

        #expect(repo.findAll().count == 1)
        #expect(repo.findByID(room.id)?.status == .inProgress)
    }

    @Test("rooms 프로퍼티 — findAll과 동일")
    @MainActor
    func roomsProperty() {
        let repo = InMemoryRoomRepository()
        repo.save(Self.makeRoom())
        repo.save(Self.makeRoom())

        #expect(repo.rooms.count == 2)
        #expect(repo.rooms.count == repo.findAll().count)
    }
}
