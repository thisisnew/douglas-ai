import Testing
import Foundation
@testable import DOUGLAS

/// 스레드 안전 카운터 (MockURLProtocol 핸들러에서 사용)
final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return _value }
    @discardableResult
    func increment() -> Int { lock.lock(); defer { lock.unlock() }; _value += 1; return _value }
}

@Suite("HTTPRetry Tests")
struct HTTPRetryTests {

    private let testURL = URL(string: "https://api.example.com/test")!

    // MARK: - 성공 케이스

    @Test("200 응답 → 재시도 없이 즉시 반환")
    func success_noRetry() async throws {
        let body = Data("{\"ok\":true}".utf8)
        let counter = AtomicCounter()
        let (session, testID) = makeMockSession { request in
            counter.increment()
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }
        defer { MockURLProtocol.removeHandler(for: testID) }

        let request = URLRequest(url: testURL)
        let (data, response) = try await HTTPRetry.data(for: request, session: session, baseDelay: 0.01)

        #expect(response.statusCode == 200)
        #expect(data == body)
        #expect(counter.value == 1)
    }

    // MARK: - 429 재시도

    @Test("429 → 재시도 후 성공")
    func retry429_thenSuccess() async throws {
        let counter = AtomicCounter()
        let (session, testID) = makeMockSession { request in
            let count = counter.increment()
            if count <= 2 {
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!,
                    Data("rate limited".utf8)
                )
            }
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("{\"ok\":true}".utf8)
            )
        }
        defer { MockURLProtocol.removeHandler(for: testID) }

        let request = URLRequest(url: testURL)
        let (_, response) = try await HTTPRetry.data(for: request, session: session, baseDelay: 0.01)

        #expect(response.statusCode == 200)
        #expect(counter.value == 3)
    }

    @Test("429 → 모든 재시도 소진 → 에러에 body 포함")
    func retry429_exhausted_includesBody() async throws {
        let counter = AtomicCounter()
        let errorBody = "{\"error\":{\"message\":\"quota exceeded\"}}"
        let (session, testID) = makeMockSession { _ in
            counter.increment()
            return (
                HTTPURLResponse(url: self.testURL, statusCode: 429, httpVersion: nil, headerFields: nil)!,
                Data(errorBody.utf8)
            )
        }
        defer { MockURLProtocol.removeHandler(for: testID) }

        let request = URLRequest(url: testURL)

        do {
            _ = try await HTTPRetry.data(for: request, session: session, maxRetries: 2, baseDelay: 0.01)
            Issue.record("Expected error to be thrown")
        } catch let error as AIProviderError {
            if case .httpError(let code, let body) = error {
                #expect(code == 429)
                #expect(body.contains("quota exceeded"))
            } else {
                Issue.record("Wrong error variant: \(error)")
            }
        }
        #expect(counter.value == 3) // 초기 1회 + 재시도 2회
    }

    // MARK: - 404 재시도 불가

    @Test("404 → 재시도 없이 즉시 실패 + body 포함")
    func noRetry404_includesBody() async throws {
        let counter = AtomicCounter()
        let errorBody = "{\"error\":{\"message\":\"models/gemini-2.0-pro is not found\"}}"
        let (session, testID) = makeMockSession { _ in
            counter.increment()
            return (
                HTTPURLResponse(url: self.testURL, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                Data(errorBody.utf8)
            )
        }
        defer { MockURLProtocol.removeHandler(for: testID) }

        let request = URLRequest(url: testURL)

        do {
            _ = try await HTTPRetry.data(for: request, session: session, baseDelay: 0.01)
            Issue.record("Expected error to be thrown")
        } catch let error as AIProviderError {
            if case .httpError(let code, let body) = error {
                #expect(code == 404)
                #expect(body.contains("not found"))
            } else {
                Issue.record("Wrong error variant: \(error)")
            }
        }
        #expect(counter.value == 1) // 재시도 없음
    }

    // MARK: - 503 재시도

    @Test("503 → 재시도 후 성공")
    func retry503_thenSuccess() async throws {
        let counter = AtomicCounter()
        let (session, testID) = makeMockSession { request in
            let count = counter.increment()
            if count == 1 {
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!,
                    Data("service unavailable".utf8)
                )
            }
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("{\"ok\":true}".utf8)
            )
        }
        defer { MockURLProtocol.removeHandler(for: testID) }

        let request = URLRequest(url: testURL)
        let (_, response) = try await HTTPRetry.data(for: request, session: session, baseDelay: 0.01)

        #expect(response.statusCode == 200)
        #expect(counter.value == 2)
    }

    // MARK: - Retry-After 헤더

    @Test("Retry-After 헤더가 있으면 해당 값을 대기 시간으로 사용")
    func retryAfterHeader_respected() async throws {
        let counter = AtomicCounter()
        let (session, testID) = makeMockSession { request in
            let count = counter.increment()
            if count == 1 {
                return (
                    HTTPURLResponse(
                        url: request.url!, statusCode: 429, httpVersion: nil,
                        headerFields: ["Retry-After": "1"]
                    )!,
                    Data("rate limited".utf8)
                )
            }
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("{\"ok\":true}".utf8)
            )
        }
        defer { MockURLProtocol.removeHandler(for: testID) }

        let request = URLRequest(url: testURL)
        let (_, response) = try await HTTPRetry.data(for: request, session: session, baseDelay: 0.01)

        #expect(response.statusCode == 200)
        #expect(counter.value == 2)
    }

    // MARK: - maxRetries: 0

    @Test("maxRetries 0 → 재시도 없이 단일 시도")
    func maxRetriesZero_singleAttempt() async throws {
        let counter = AtomicCounter()
        let (session, testID) = makeMockSession { _ in
            counter.increment()
            return (
                HTTPURLResponse(url: self.testURL, statusCode: 429, httpVersion: nil, headerFields: nil)!,
                Data("rate limited".utf8)
            )
        }
        defer { MockURLProtocol.removeHandler(for: testID) }

        let request = URLRequest(url: testURL)

        do {
            _ = try await HTTPRetry.data(for: request, session: session, maxRetries: 0, baseDelay: 0.01)
            Issue.record("Expected error")
        } catch let error as AIProviderError {
            if case .httpError(let code, _) = error {
                #expect(code == 429)
            }
        }
        #expect(counter.value == 1)
    }

    // MARK: - 401 인증 에러 재시도 불가

    @Test("401 → 재시도 없이 즉시 실패")
    func noRetry401() async throws {
        let counter = AtomicCounter()
        let (session, testID) = makeMockSession { _ in
            counter.increment()
            return (
                HTTPURLResponse(url: self.testURL, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                Data("{\"error\":\"invalid api key\"}".utf8)
            )
        }
        defer { MockURLProtocol.removeHandler(for: testID) }

        let request = URLRequest(url: testURL)

        do {
            _ = try await HTTPRetry.data(for: request, session: session, baseDelay: 0.01)
            Issue.record("Expected error")
        } catch let error as AIProviderError {
            if case .httpError(let code, let body) = error {
                #expect(code == 401)
                #expect(body.contains("invalid api key"))
            }
        }
        #expect(counter.value == 1)
    }

    // MARK: - 응답 body가 비어있을 때 폴백 메시지

    @Test("에러 응답 body가 비어있으면 폴백 메시지 사용")
    func emptyBody_fallbackMessage() async throws {
        let (session, testID) = makeMockSession { _ in
            return (
                HTTPURLResponse(url: self.testURL, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }
        defer { MockURLProtocol.removeHandler(for: testID) }

        let request = URLRequest(url: testURL)

        do {
            _ = try await HTTPRetry.data(for: request, session: session, maxRetries: 0, baseDelay: 0.01)
            Issue.record("Expected error")
        } catch let error as AIProviderError {
            if case .httpError(let code, let body) = error {
                #expect(code == 500)
                #expect(body.contains("500"))
            }
        }
    }

    // MARK: - bytes (스트리밍) 재시도

    @Test("bytes: 200 → 재시도 없이 스트림 반환")
    func bytes_success_noRetry() async throws {
        let counter = AtomicCounter()
        let (session, testID) = makeMockSession { request in
            counter.increment()
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("streaming data".utf8)
            )
        }
        defer { MockURLProtocol.removeHandler(for: testID) }

        let request = URLRequest(url: testURL)
        let (bytes, response) = try await HTTPRetry.bytes(for: request, session: session, baseDelay: 0.01)

        #expect(response.statusCode == 200)
        #expect(counter.value == 1)

        var content = ""
        for try await line in bytes.lines { content += line }
        #expect(content == "streaming data")
    }

    @Test("bytes: 429 → 재시도 후 스트리밍 성공")
    func bytes_retry429_thenSuccess() async throws {
        let counter = AtomicCounter()
        let (session, testID) = makeMockSession { request in
            let count = counter.increment()
            if count <= 2 {
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!,
                    Data("rate limited".utf8)
                )
            }
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("ok stream".utf8)
            )
        }
        defer { MockURLProtocol.removeHandler(for: testID) }

        let request = URLRequest(url: testURL)
        let (bytes, response) = try await HTTPRetry.bytes(for: request, session: session, baseDelay: 0.01)

        #expect(response.statusCode == 200)
        #expect(counter.value == 3)

        var content = ""
        for try await line in bytes.lines { content += line }
        #expect(content == "ok stream")
    }

    @Test("bytes: 429 모든 재시도 소진 → 에러에 body 포함")
    func bytes_retry429_exhausted() async throws {
        let counter = AtomicCounter()
        let (session, testID) = makeMockSession { _ in
            counter.increment()
            return (
                HTTPURLResponse(url: self.testURL, statusCode: 429, httpVersion: nil, headerFields: nil)!,
                Data("{\"error\":\"rate limit\"}".utf8)
            )
        }
        defer { MockURLProtocol.removeHandler(for: testID) }

        let request = URLRequest(url: testURL)

        do {
            _ = try await HTTPRetry.bytes(for: request, session: session, maxRetries: 1, baseDelay: 0.01)
            Issue.record("Expected error")
        } catch let error as AIProviderError {
            if case .httpError(let code, let body) = error {
                #expect(code == 429)
                #expect(body.contains("rate limit"))
            } else {
                Issue.record("Wrong error variant: \(error)")
            }
        }
        #expect(counter.value == 2)
    }

    @Test("bytes: 404 → 재시도 없이 즉시 실패 + body 포함")
    func bytes_noRetry404() async throws {
        let counter = AtomicCounter()
        let (session, testID) = makeMockSession { _ in
            counter.increment()
            return (
                HTTPURLResponse(url: self.testURL, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                Data("model not found".utf8)
            )
        }
        defer { MockURLProtocol.removeHandler(for: testID) }

        let request = URLRequest(url: testURL)

        do {
            _ = try await HTTPRetry.bytes(for: request, session: session, baseDelay: 0.01)
            Issue.record("Expected error")
        } catch let error as AIProviderError {
            if case .httpError(let code, let body) = error {
                #expect(code == 404)
                #expect(body.contains("model not found"))
            }
        }
        #expect(counter.value == 1)
    }
}
