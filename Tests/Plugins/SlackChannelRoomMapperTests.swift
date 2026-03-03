import Testing
import Foundation
@testable import DOUGLAS

@Suite("SlackChannelRoomMapper Tests")
struct SlackChannelRoomMapperTests {

    @Test("매핑 설정 및 조회")
    func setAndRetrieve() {
        let mapper = SlackChannelRoomMapper()
        let roomID = UUID()

        mapper.setMapping(channelID: "C123", roomID: roomID, threadTS: "1234.5678")

        #expect(mapper.roomID(for: "C123") == roomID)
        #expect(mapper.mapping(for: roomID)?.channelID == "C123")
        #expect(mapper.mapping(for: roomID)?.threadTS == "1234.5678")
    }

    @Test("존재하지 않는 매핑 조회 시 nil")
    func notFound() {
        let mapper = SlackChannelRoomMapper()

        #expect(mapper.roomID(for: "C999") == nil)
        #expect(mapper.mapping(for: UUID()) == nil)
    }

    @Test("매핑 제거")
    func removeMapping() {
        let mapper = SlackChannelRoomMapper()
        let roomID = UUID()

        mapper.setMapping(channelID: "C123", roomID: roomID, threadTS: nil)
        mapper.removeMapping(for: roomID)

        #expect(mapper.roomID(for: "C123") == nil)
        #expect(mapper.mapping(for: roomID) == nil)
    }

    @Test("매핑 덮어쓰기")
    func overwriteMapping() {
        let mapper = SlackChannelRoomMapper()
        let roomID1 = UUID()
        let roomID2 = UUID()

        mapper.setMapping(channelID: "C123", roomID: roomID1, threadTS: nil)
        mapper.setMapping(channelID: "C123", roomID: roomID2, threadTS: "new.ts")

        #expect(mapper.roomID(for: "C123") == roomID2)
        #expect(mapper.mapping(for: roomID2)?.threadTS == "new.ts")
    }

    @Test("영속화 round-trip")
    func persistenceRoundTrip() {
        let mapper1 = SlackChannelRoomMapper()
        let roomID = UUID()
        let pluginID = "test-slack-\(UUID().uuidString)"

        mapper1.setMapping(channelID: "C456", roomID: roomID, threadTS: "ts123")
        mapper1.saveMappings(pluginID: pluginID)

        let mapper2 = SlackChannelRoomMapper()
        mapper2.loadMappings(pluginID: pluginID)

        #expect(mapper2.roomID(for: "C456") == roomID)
        #expect(mapper2.mapping(for: roomID)?.threadTS == "ts123")

        // 정리
        UserDefaults.standard.removeObject(forKey: "pluginMappings_\(pluginID)")
    }
}
