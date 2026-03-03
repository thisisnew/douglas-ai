import Foundation

class MockURLProtocol: URLProtocol {
    // MARK: - Per-session 격리 (thread-safe, 병렬 테스트 안전)

    private static let lock = NSLock()
    private static var handlers: [String: (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]
    private static var bodies: [String: Data] = [:]

    static func setHandler(for testID: String, _ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock(); defer { lock.unlock() }
        handlers[testID] = handler
    }

    static func removeHandler(for testID: String) {
        lock.lock(); defer { lock.unlock() }
        handlers.removeValue(forKey: testID)
        bodies.removeValue(forKey: testID)
    }

    static func lastBody(for testID: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return bodies[testID]
    }

    // MARK: - Legacy 글로벌 핸들러 (ProviderDetectorTests 등 비병렬 테스트용)

    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequestBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // httpBody 또는 httpBodyStream에서 body 읽기
        let capturedBody: Data?
        if let body = request.httpBody {
            capturedBody = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let bufferSize = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read > 0 { data.append(buffer, count: read) }
                else { break }
            }
            stream.close()
            capturedBody = data
        } else {
            capturedBody = nil
        }

        // Per-session 핸들러 (X-Mock-ID 헤더로 조회)
        if let testID = request.value(forHTTPHeaderField: "X-Mock-ID") {
            Self.lock.lock()
            if let body = capturedBody { Self.bodies[testID] = body }
            let handler = Self.handlers[testID]
            Self.lock.unlock()

            if let handler {
                do {
                    let (response, data) = try handler(request)
                    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocol(self, didLoad: data)
                    client?.urlProtocolDidFinishLoading(self)
                } catch {
                    client?.urlProtocol(self, didFailWithError: error)
                }
            } else {
                client?.urlProtocolDidFinishLoading(self)
            }
            return
        }

        // Legacy 글로벌 핸들러 폴백
        Self.lastRequestBody = capturedBody

        guard let handler = Self.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// Legacy: MockURLProtocol을 사용하는 URLSession 생성 (글로벌 핸들러용)
func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

/// 격리된 MockURLProtocol 세션 생성 (병렬 테스트 안전)
/// - Returns: (session, testID) — defer { MockURLProtocol.removeHandler(for: testID) } 로 정리
func makeMockSession(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> (URLSession, String) {
    let testID = UUID().uuidString
    MockURLProtocol.setHandler(for: testID, handler)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    config.httpAdditionalHeaders = ["X-Mock-ID": testID]
    return (URLSession(configuration: config), testID)
}
