import Foundation

/// Room 영속화 추상화 — 테스트 시 MockRoomRepository 주입 가능
@MainActor
protocol RoomRepository: AnyObject {
    /// 특정 방 조회
    func findByID(_ id: UUID) -> Room?
    /// 전체 방 조회
    func findAll() -> [Room]
    /// 방 저장 (upsert: 동일 ID면 교체)
    func save(_ room: Room)
    /// 방 삭제
    func delete(id: UUID)
    /// 방 상태 변경 (in-place mutation)
    func update(_ id: UUID, _ mutate: (inout Room) -> Void)
}
