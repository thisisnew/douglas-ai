import Foundation

/// Slack 채널 ↔ DOUGLAS Room 매핑 정보
struct SlackChannelMapping: Codable {
    let channelID: String
    let roomID: UUID
    let threadTS: String?
    let createdAt: Date
}

/// 양방향 매핑 관리 + UserDefaults 영속화
final class SlackChannelRoomMapper {
    private var channelToRoom: [String: SlackChannelMapping] = [:]
    private var roomToChannel: [UUID: SlackChannelMapping] = [:]

    func roomID(for channelID: String) -> UUID? {
        channelToRoom[channelID]?.roomID
    }

    func mapping(for roomID: UUID) -> SlackChannelMapping? {
        roomToChannel[roomID]
    }

    func setMapping(channelID: String, roomID: UUID, threadTS: String?) {
        let mapping = SlackChannelMapping(
            channelID: channelID,
            roomID: roomID,
            threadTS: threadTS,
            createdAt: Date()
        )
        channelToRoom[channelID] = mapping
        roomToChannel[roomID] = mapping
    }

    func removeMapping(for roomID: UUID) {
        if let mapping = roomToChannel.removeValue(forKey: roomID) {
            channelToRoom.removeValue(forKey: mapping.channelID)
        }
    }

    // MARK: - 영속화

    func saveMappings(pluginID: String) {
        let mappings = Array(channelToRoom.values)
        if let data = try? JSONEncoder().encode(mappings) {
            UserDefaults.standard.set(data, forKey: "pluginMappings_\(pluginID)")
        }
    }

    func loadMappings(pluginID: String) {
        guard let data = UserDefaults.standard.data(forKey: "pluginMappings_\(pluginID)"),
              let mappings = try? JSONDecoder().decode([SlackChannelMapping].self, from: data) else { return }
        for mapping in mappings {
            channelToRoom[mapping.channelID] = mapping
            roomToChannel[mapping.roomID] = mapping
        }
    }
}
