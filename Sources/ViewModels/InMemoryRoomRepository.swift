import Foundation
import Combine

/// 인메모리 Room 저장소 — RoomManager에서 rooms 배열 관리를 위임받음
@MainActor
final class InMemoryRoomRepository: RoomRepository, ObservableObject {

    @Published private(set) var rooms: [Room] = []

    func findByID(_ id: UUID) -> Room? {
        rooms.first(where: { $0.id == id })
    }

    func findAll() -> [Room] {
        rooms
    }

    func save(_ room: Room) {
        if let idx = rooms.firstIndex(where: { $0.id == room.id }) {
            rooms[idx] = room
        } else {
            rooms.append(room)
        }
    }

    func delete(id: UUID) {
        rooms.removeAll(where: { $0.id == id })
    }

    func update(_ id: UUID, _ mutate: (inout Room) -> Void) {
        guard let idx = rooms.firstIndex(where: { $0.id == id }) else { return }
        mutate(&rooms[idx])
    }
}
