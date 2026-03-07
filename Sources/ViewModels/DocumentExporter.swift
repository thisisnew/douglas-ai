import Foundation
import AppKit
import UniformTypeIdentifiers
import WebKit

/// WKWebView HTML 로드 완료 대기
private final class PDFWebViewLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Bool, Never>?

    init(continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
        super.init()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume(returning: true)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(returning: false)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(returning: false)
        continuation = nil
    }
}

/// NSPrintOperation 완료 콜백 (비동기 delegate)
private final class PDFPrintDelegate: NSObject {
    private var continuation: CheckedContinuation<Bool, Never>?

    init(continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
        super.init()
    }

    @objc func printOperationDidRun(_ op: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        continuation?.resume(returning: success)
        continuation = nil
    }
}

/// 문서 산출물을 파일로 내보내기
@MainActor
enum DocumentExporter {

    /// 문서 내용을 파일로 저장
    /// - 고정 경로 설정 시: 해당 폴더에 자동 저장 (NSSavePanel 없음)
    /// - 미설정 시: NSSavePanel으로 위치 선택
    /// - Returns: 저장된 파일 URL (nil = 사용자 취소 또는 오류)
    @discardableResult
    static func saveDocument(
        content: String,
        suggestedName: String,
        defaultExtension: String = "md"
    ) -> URL? {
        let filename = sanitizeFilename(suggestedName, ext: defaultExtension)

        // 고정 경로가 설정되어 있으면 자동 저장
        if let dirURL = resolveDocumentSaveDirectory() {
            let fileURL = uniqueFileURL(directory: dirURL, filename: filename)
            do {
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                return fileURL
            } catch {
                print("[DocumentExporter] 설정 폴더 저장 실패: \(error.localizedDescription) → 기본 폴더로 폴백")
            }
        }

        // 고정 경로 미설정 시 Documents 폴더에 자동 저장 (NSSavePanel 없이)
        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let douglasDir = docsDir.appendingPathComponent("DOUGLAS", isDirectory: true)
        try? FileManager.default.createDirectory(at: douglasDir, withIntermediateDirectories: true)
        let fileURL = uniqueFileURL(directory: douglasDir, filename: filename)
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }

    /// 설정된 경로가 존재하지만 접근 불가한 경우 경고 문자열 반환
    static func checkSaveDirectoryWarning() -> String? {
        let configured = UserDefaults.standard.string(forKey: "documentSaveDirectory")
        guard let configured, !configured.isEmpty else { return nil }
        if resolveDocumentSaveDirectory() == nil {
            return "설정된 저장 경로(\(configured))에 접근할 수 없어 기본 경로에 저장됩니다. 설정에서 경로를 다시 지정해 주세요."
        }
        return nil
    }

    /// 설정된 문서 저장 폴더 URL 해석 (Bookmark → 경로 문자열 순서)
    private static func resolveDocumentSaveDirectory() -> URL? {
        // 1. Security Bookmark으로 해석 시도 (앱 재시작 후에도 접근 권한 유지)
        if let bookmarkData = UserDefaults.standard.data(forKey: "documentSaveDirectoryBookmark") {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
                   FileManager.default.isWritableFile(atPath: url.path) {
                    // Stale bookmark → 갱신
                    if isStale, let newData = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                        UserDefaults.standard.set(newData, forKey: "documentSaveDirectoryBookmark")
                    }
                    return url
                }
            }
        }

        // 2. 경로 문자열로 폴백
        if let fixedDir = UserDefaults.standard.string(forKey: "documentSaveDirectory"),
           !fixedDir.isEmpty {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: fixedDir, isDirectory: &isDir), isDir.boolValue,
               FileManager.default.isWritableFile(atPath: fixedDir) {
                return URL(fileURLWithPath: fixedDir)
            }
        }

        return nil
    }

    /// 날짜_번호 형식으로 고유 파일명 생성 (20260307_001.md, 20260307_002.md, ...)
    private static func uniqueFileURL(directory: URL, filename: String) -> URL {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var counter = 1
        while true {
            let name = ext.isEmpty
                ? String(format: "%@_%03d", base, counter)
                : String(format: "%@_%03d.%@", base, counter, ext)
            let candidate = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }

    /// 방에서 문서 내용 추출 (artifact 우선, fallback: 마지막 assistant 메시지)
    static func extractDocumentContent(from room: Room) -> String? {
        // 1차: artifact type == .document (최신 버전 우선)
        if let docArtifact = room.discussion.artifacts
            .filter({ $0.type == .document })
            .sorted(by: { $0.version > $1.version })
            .first {
            return ArtifactParser.stripArtifactBlocks(from: docArtifact.content)
        }

        // 2차: 마지막 assistant .text 메시지 (최소 200자 이상이어야 문서로 간주)
        if let lastMsg = room.messages
            .reversed()
            .first(where: { $0.role == .assistant && $0.messageType == .text }) {
            let content = ArtifactParser.stripArtifactBlocks(from: lastMsg.content)
            if content.count >= 200 { return content }
        }

        return nil
    }

    /// 방의 메시지에서 에이전트가 실제 생성한 문서 파일 경로 추출
    /// - 1차: toolActivity의 file_write/Write 기록
    /// - 2차: 어시스턴트 텍스트에서 절대 경로 언급 탐색 (backtick 감싸진 패턴)
    static func findActualDocumentFile(from room: Room) -> URL? {
        let docExtensions: Set<String> = ["pdf", "docx", "xlsx", "html", "pptx", "csv", "txt"]

        // 1차: toolActivity에서 file_write/Write 경로 (최신 순)
        for msg in room.messages.reversed() where msg.messageType == .toolActivity {
            guard let detail = msg.toolDetail,
                  ["file_write", "Write"].contains(detail.toolName),
                  let path = detail.subject else { continue }
            let ext = (path as NSString).pathExtension.lowercased()
            if docExtensions.contains(ext),
               FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        // 2차: 어시스턴트 메시지에서 backtick 감싸진 절대 경로 추출
        guard let regex = try? NSRegularExpression(
            pattern: "`(/[^`\\n]+\\.(?:pdf|docx|xlsx|html|pptx|csv))`",
            options: []
        ) else { return nil }

        for msg in room.messages.reversed() where msg.role == .assistant && msg.messageType == .text {
            let nsStr = msg.content as NSString
            let matches = regex.matches(in: msg.content, options: [], range: NSRange(location: 0, length: nsStr.length))
            for match in matches.reversed() {
                let path = nsStr.substring(with: match.range(at: 1))
                if FileManager.default.fileExists(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
            }
        }

        return nil
    }

    /// 바이너리 포맷 (LLM이 file_write로 직접 생성해야 하는 형식)
    static let binaryFormats: Set<String> = ["xlsx", "pptx", "docx"]

    /// 사용자 요청에서 파일 포맷 감지
    static func detectRequestedFormat(_ task: String) -> String {
        let lower = task.lowercased()
        if lower.contains("xlsx") || lower.contains("엑셀") || lower.contains("excel") { return "xlsx" }
        if lower.contains("pptx") || lower.contains("파워포인트") || lower.contains("ppt") { return "pptx" }
        if lower.contains("docx") || lower.contains("워드") || lower.contains("word") { return "docx" }
        if lower.contains("csv") { return "csv" }
        if lower.contains("json") { return "json" }
        if lower.contains("txt") { return "txt" }
        if lower.contains("pdf") { return "pdf" }
        return "md"
    }

    /// 저장 디렉토리 경로 문자열 반환 (설정 경로 우선, 폴백: ~/Documents/DOUGLAS)
    static func resolvedSaveDirectoryPath() -> String {
        if let dirURL = resolveDocumentSaveDirectory() {
            return dirURL.path
        }
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let douglasDir = docsDir.appendingPathComponent("DOUGLAS", isDirectory: true)
        try? FileManager.default.createDirectory(at: douglasDir, withIntermediateDirectories: true)
        return douglasDir.path
    }

    /// 날짜 기반 파일명 생성 (yyyyMMdd)
    static func suggestedFilename(room: Room, content: String? = nil) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }

    // MARK: - PDF 변환

    /// Markdown → PDF 변환 후 파일 저장
    static func exportToPDF(markdownContent: String, suggestedName: String) async -> URL? {
        let html = markdownToStyledHTML(markdownContent)

        // printOperation으로 A4 페이지 분할 PDF 생성
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 595, height: 842))

        let loaded = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let loader = PDFWebViewLoader(continuation: cont)
            webView.navigationDelegate = loader
            objc_setAssociatedObject(webView, "pdfLoader", loader, .OBJC_ASSOCIATION_RETAIN)
            webView.loadHTMLString(html, baseURL: nil)
        }
        guard loaded else { return nil }

        // 임시 파일 경로 준비
        let filename = sanitizeFilename(suggestedName, ext: "pdf")
        let targetURL: URL
        if let dirURL = resolveDocumentSaveDirectory() {
            targetURL = uniqueFileURL(directory: dirURL, filename: filename)
        } else {
            guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
            let douglasDir = docsDir.appendingPathComponent("DOUGLAS", isDirectory: true)
            try? FileManager.default.createDirectory(at: douglasDir, withIntermediateDirectories: true)
            targetURL = uniqueFileURL(directory: douglasDir, filename: filename)
        }

        // NSPrintOperation으로 A4 페이지네이션 PDF 생성
        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: 595.28, height: 841.89)
        printInfo.topMargin = 56
        printInfo.bottomMargin = 56
        printInfo.leftMargin = 56
        printInfo.rightMargin = 56
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = targetURL

        let printOp = webView.printOperation(with: printInfo)
        printOp.showsPrintPanel = false
        printOp.showsProgressPanel = false

        // 비동기 실행: delegate 콜백으로 완료 통보 (메인 스레드 블로킹 방지)
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        let success = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let delegate = PDFPrintDelegate(continuation: cont)
            objc_setAssociatedObject(printOp, "printDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
            printOp.runModal(
                for: window,
                delegate: delegate,
                didRun: #selector(PDFPrintDelegate.printOperationDidRun(_:success:contextInfo:)),
                contextInfo: nil
            )
        }

        guard success, FileManager.default.fileExists(atPath: targetURL.path) else { return nil }
        return targetURL
    }

    /// Binary 데이터를 파일로 저장 (PDF 등)
    @discardableResult
    static func saveData(_ data: Data, suggestedName: String, ext: String) -> URL? {
        let filename = sanitizeFilename(suggestedName, ext: ext)

        if let dirURL = resolveDocumentSaveDirectory() {
            let fileURL = uniqueFileURL(directory: dirURL, filename: filename)
            if (try? data.write(to: fileURL)) != nil { return fileURL }
        }

        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let douglasDir = docsDir.appendingPathComponent("DOUGLAS", isDirectory: true)
        try? FileManager.default.createDirectory(at: douglasDir, withIntermediateDirectories: true)
        let fileURL = uniqueFileURL(directory: douglasDir, filename: filename)
        return (try? data.write(to: fileURL)) != nil ? fileURL : nil
    }

    // MARK: - Markdown → HTML 변환

    /// Markdown을 스타일 적용된 HTML 문서로 변환
    private static func markdownToStyledHTML(_ md: String) -> String {
        let lines = md.components(separatedBy: "\n")
        var html = ""
        var i = 0

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

            // 코드 블록
            if trimmed.hasPrefix("```") {
                i += 1
                var code = ""
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code += escapeHTML(lines[i]) + "\n"
                    i += 1
                }
                html += "<pre><code>\(code)</code></pre>\n"
                i += 1
                continue
            }

            // 헤더
            if trimmed.hasPrefix("### ") {
                html += "<h3>\(inlineFormat(String(trimmed.dropFirst(4))))</h3>\n"
            } else if trimmed.hasPrefix("## ") {
                html += "<h2>\(inlineFormat(String(trimmed.dropFirst(3))))</h2>\n"
            } else if trimmed.hasPrefix("# ") {
                html += "<h1>\(inlineFormat(String(trimmed.dropFirst(2))))</h1>\n"
            }
            // 수평선
            else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                html += "<hr>\n"
            }
            // 인용
            else if trimmed.hasPrefix("> ") {
                html += "<blockquote><p>\(inlineFormat(String(trimmed.dropFirst(2))))</p></blockquote>\n"
            }
            // 테이블
            else if trimmed.hasPrefix("|") {
                html += "<table>\n"
                var isHeader = true
                while i < lines.count {
                    let tLine = lines[i].trimmingCharacters(in: .whitespaces)
                    guard tLine.hasPrefix("|") else { break }
                    if tLine.contains("---") {
                        isHeader = false
                        i += 1
                        continue
                    }
                    let cells = tLine.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
                    let tag = isHeader ? "th" : "td"
                    html += "<tr>" + cells.map { "<\(tag)>\(inlineFormat($0))</\(tag)>" }.joined() + "</tr>\n"
                    if isHeader { isHeader = false }
                    i += 1
                }
                html += "</table>\n"
                continue
            }
            // 비순서 목록
            else if trimmed.hasPrefix("- ") {
                html += "<ul>\n"
                while i < lines.count {
                    let lLine = lines[i].trimmingCharacters(in: .whitespaces)
                    guard lLine.hasPrefix("- ") else { break }
                    html += "<li>\(inlineFormat(String(lLine.dropFirst(2))))</li>\n"
                    i += 1
                }
                html += "</ul>\n"
                continue
            }
            // 순서 목록
            else if trimmed.first?.isNumber == true && trimmed.contains(". ") {
                html += "<ol>\n"
                while i < lines.count {
                    let lLine = lines[i].trimmingCharacters(in: .whitespaces)
                    guard lLine.first?.isNumber == true,
                          let dotIdx = lLine.firstIndex(of: ".") else { break }
                    let afterDot = String(lLine[lLine.index(after: dotIdx)...]).trimmingCharacters(in: .whitespaces)
                    html += "<li>\(inlineFormat(afterDot))</li>\n"
                    i += 1
                }
                html += "</ol>\n"
                continue
            }
            // 빈 줄
            else if trimmed.isEmpty {
                // skip
            }
            // 일반 단락
            else {
                html += "<p>\(inlineFormat(trimmed))</p>\n"
            }

            i += 1
        }

        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <style>
        body { font-family: -apple-system, 'Apple SD Gothic Neo', sans-serif; font-size: 13px; line-height: 1.7; padding: 40px; max-width: 720px; margin: 0 auto; color: #222; }
        h1 { font-size: 22px; border-bottom: 2px solid #eee; padding-bottom: 8px; }
        h2 { font-size: 18px; border-bottom: 1px solid #eee; padding-bottom: 6px; margin-top: 28px; }
        h3 { font-size: 15px; margin-top: 22px; }
        table { border-collapse: collapse; width: 100%; margin: 12px 0; }
        th, td { border: 1px solid #d0d0d0; padding: 8px 12px; text-align: left; font-size: 12px; }
        th { background: #f5f5f5; font-weight: 600; }
        blockquote { border-left: 3px solid #ccc; margin: 12px 0; padding: 8px 16px; color: #555; background: #fafafa; }
        pre { background: #f5f5f5; padding: 12px; border-radius: 4px; overflow-x: auto; font-size: 12px; }
        code { font-family: 'SF Mono', Menlo, monospace; font-size: 12px; }
        hr { border: none; border-top: 1px solid #ddd; margin: 24px 0; }
        a { color: #0066cc; text-decoration: none; }
        ul, ol { padding-left: 24px; }
        li { margin-bottom: 4px; }
        @page { size: A4; margin: 2cm; }
        </style>
        </head><body>
        \(html)
        </body></html>
        """
    }

    /// 인라인 Markdown 서식 → HTML 변환
    private static func inlineFormat(_ text: String) -> String {
        var result = escapeHTML(text)
        result = result.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\*(.+?)\\*", with: "<em>$1</em>", options: .regularExpression)
        result = result.replacingOccurrences(of: "`(.+?)`", with: "<code>$1</code>", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\[(.+?)\\]\\((.+?)\\)", with: "<a href=\"$2\">$1</a>", options: .regularExpression)
        return result
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// 파일명에서 특수문자 제거
    static func sanitizeFilename(_ name: String, ext: String) -> String {
        let cleaned = name
            .components(separatedBy: CharacterSet.alphanumerics
                .union(.init(charactersIn: " _-"))
                .union(CharacterSet(charactersIn: "\u{AC00}"..."\u{D7A3}"))  // 완성형 한글
                .union(CharacterSet(charactersIn: "\u{3131}"..."\u{3163}"))  // 한글 자모
                .inverted)
            .joined()
            .trimmingCharacters(in: .whitespaces)
        let base = cleaned.isEmpty ? "document" : cleaned
        let truncated = String(base.prefix(80))
        return "\(truncated).\(ext)"
    }
}
