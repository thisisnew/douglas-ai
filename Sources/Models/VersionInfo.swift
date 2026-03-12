import Foundation

/// 자동 업데이트용 버전 정보 (Public Gist에서 제공)
struct VersionInfo: Codable, Sendable {
    /// 버전 번호 (예: "1.2.0")
    let version: String

    /// 릴리스 이름 (예: "버전 1.2.0")
    let name: String

    /// 릴리스 노트 (Markdown 형식)
    let releaseNotes: String

    /// DMG 다운로드 URL
    let downloadURL: String

    /// 릴리스 일시
    let publishedAt: Date

    /// v 접두사 제거한 버전 번호
    var normalizedVersion: String {
        version.hasPrefix("v") ? String(version.dropFirst()) : version
    }
}
