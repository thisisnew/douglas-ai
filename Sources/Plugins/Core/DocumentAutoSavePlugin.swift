import Foundation

/// 에이전트가 생성한 문서 파일을 자동으로 저장 폴더에 복사하는 내장 플러그인
/// PluginEvent.fileWritten을 감지하여 문서 확장자면 저장 폴더로 복사
/// 기존 ToolExecutor, RoomManager 코드 변경 없이 이벤트 리스너만 추가
@MainActor
final class DocumentAutoSavePlugin: DougPlugin {

    let info = PluginInfo(
        id: "document-auto-save",
        name: "문서 자동 저장",
        description: "에이전트가 생성한 문서 파일(pptx, pdf, docx 등)을 문서 저장 폴더에 자동 복사합니다.",
        version: "1.0.0",
        iconSystemName: "doc.on.doc"
    )

    private(set) var isActive = true  // 기본 활성화
    private var context: PluginContext?

    var configFields: [PluginConfigField] { [] }
    var agentConfigFields: [PluginConfigField] { [] }
    var agentCapabilities: PluginAgentCapabilities { .empty }

    /// 문서 파일 확장자
    static let documentExtensions: Set<String> = [
        "pptx", "pdf", "docx", "xlsx", "csv", "html", "hwp", "key", "pages", "numbers"
    ]

    func configure(context: PluginContext) {
        self.context = context
    }

    func activate() async -> Bool { isActive = true; return true }
    func deactivate() async { isActive = false }

    func handle(event: PluginEvent) {
        guard isActive else { return }

        switch event {
        case .fileWritten(let path, _):
            handleFileWritten(path: path)

        case .toolExecutionCompleted(_, let toolName, let result, _):
            if toolName == "shell_exec" {
                detectDocumentPathsInOutput(result)
            }

        default:
            break
        }
    }

    func interceptToolExecution(toolName: String, arguments: [String: String]) -> ToolInterceptResult {
        .passthrough
    }

    // MARK: - Private

    private func handleFileWritten(path: String) {
        let ext = (path as NSString).pathExtension.lowercased()
        guard Self.documentExtensions.contains(ext) else { return }
        copyToDocumentFolder(sourcePath: path)
    }

    private func detectDocumentPathsInOutput(_ output: String) {
        // /path/to/file.pptx 패턴 감지
        let pattern = #"(/[^\s"']+\.(?:pptx|pdf|docx|xlsx|csv|html|hwp))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return }
        let range = NSRange(output.startIndex..., in: output)
        let matches = regex.matches(in: output, range: range)

        for match in matches {
            guard let r = Range(match.range(at: 1), in: output) else { continue }
            let path = String(output[r])
            if FileManager.default.fileExists(atPath: path) {
                copyToDocumentFolder(sourcePath: path)
            }
        }
    }

    private func copyToDocumentFolder(sourcePath: String) {
        guard let saveDir = resolveSaveDirectory() else { return }
        let fileName = (sourcePath as NSString).lastPathComponent
        var destURL = saveDir.appendingPathComponent(fileName)

        // 같은 이름 파일 존재 시 번호 붙이기
        let fm = FileManager.default
        if fm.fileExists(atPath: destURL.path) {
            let nameWithoutExt = (fileName as NSString).deletingPathExtension
            let ext = (fileName as NSString).pathExtension
            var counter = 1
            while fm.fileExists(atPath: destURL.path) {
                destURL = saveDir.appendingPathComponent("\(nameWithoutExt)_\(counter).\(ext)")
                counter += 1
            }
        }

        // 이미 저장 폴더에 있으면 스킵
        let sourceDir = (sourcePath as NSString).deletingLastPathComponent
        if sourceDir == saveDir.path { return }

        do {
            try fm.copyItem(atPath: sourcePath, toPath: destURL.path)
            // 복사 성공 로그
            print("[DocumentAutoSave] 문서 복사 완료: \(destURL.path)")
        } catch {
            print("[DocumentAutoSave] 문서 복사 실패: \(error.localizedDescription)")
        }
    }

    /// 문서 저장 폴더 해석 — DocumentExporter와 동일 로직 (UserDefaults 기반)
    private func resolveSaveDirectory() -> URL? {
        // 1. Security Bookmark
        if let bookmarkData = UserDefaults.standard.data(forKey: "documentSaveDirectoryBookmark") {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if FileManager.default.isWritableFile(atPath: url.path) {
                    return url
                }
            }
        }

        // 2. 문자열 경로 (레거시)
        if let path = UserDefaults.standard.string(forKey: "documentSaveDirectory") {
            let expanded = NSString(string: path).expandingTildeInPath
            if FileManager.default.isWritableFile(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }

        // 3. 기본값: ~/Downloads
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        if FileManager.default.isWritableFile(atPath: downloads.path) {
            return downloads
        }

        return nil
    }
}
