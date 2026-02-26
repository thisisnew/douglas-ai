import Foundation

struct ChangeRecord: Identifiable, Codable {
    let id: UUID
    let date: Date
    let description: String
    let commitHash: String
    var status: ChangeStatus
    let filesChanged: [String]
    let requestText: String

    enum ChangeStatus: String, Codable {
        case applied
        case rolledBack
        case failed
    }

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        description: String,
        commitHash: String,
        status: ChangeStatus = .applied,
        filesChanged: [String] = [],
        requestText: String = ""
    ) {
        self.id = id
        self.date = date
        self.description = description
        self.commitHash = commitHash
        self.status = status
        self.filesChanged = filesChanged
        self.requestText = requestText
    }
}
