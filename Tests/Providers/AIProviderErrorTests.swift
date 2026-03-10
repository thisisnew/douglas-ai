import Testing
import Foundation
@testable import DOUGLAS

@Suite("AIProviderError Tests")
struct AIProviderErrorTests {

    // MARK: - Basic error cases

    @Test("noAPIKey → contains API 키")
    func noAPIKey_message() {
        let error: Error = AIProviderError.noAPIKey
        #expect(error.userFacingMessage.contains("API 키"))
    }

    @Test("invalidURL → contains 연결 설정")
    func invalidURL_message() {
        let error: Error = AIProviderError.invalidURL
        #expect(error.userFacingMessage.contains("연결 설정"))
    }

    @Test("invalidResponse → contains 응답")
    func invalidResponse_message() {
        let error: Error = AIProviderError.invalidResponse
        #expect(error.userFacingMessage.contains("응답"))
    }

    @Test("networkError → contains 네트워크")
    func networkError_message() {
        let error: Error = AIProviderError.networkError("something failed")
        #expect(error.userFacingMessage.contains("네트워크"))
    }

    // MARK: - HTTP error classification by status code

    @Test("httpError 401 → contains 인증")
    func httpError401_message() {
        let error: Error = AIProviderError.httpError(statusCode: 401, body: "")
        #expect(error.userFacingMessage.contains("인증"))
    }

    @Test("httpError 403 → contains 인증")
    func httpError403_message() {
        let error: Error = AIProviderError.httpError(statusCode: 403, body: "")
        #expect(error.userFacingMessage.contains("인증"))
    }

    @Test("httpError 429 → contains 요청 한도")
    func httpError429_message() {
        let error: Error = AIProviderError.httpError(statusCode: 429, body: "")
        #expect(error.userFacingMessage.contains("요청 한도"))
    }

    @Test("httpError 500 → contains 서버")
    func httpError500_message() {
        let error: Error = AIProviderError.httpError(statusCode: 500, body: "")
        #expect(error.userFacingMessage.contains("서버"))
    }

    @Test("httpError 503 → contains 서버")
    func httpError503_message() {
        let error: Error = AIProviderError.httpError(statusCode: 503, body: "")
        #expect(error.userFacingMessage.contains("서버"))
    }

    // MARK: - HTTP error: body classification takes priority

    @Test("httpError with context_length_exceeded body → contains 토큰")
    func httpError_bodyContextLength_message() {
        let error: Error = AIProviderError.httpError(statusCode: 200, body: "context_length_exceeded")
        #expect(error.userFacingMessage.contains("토큰"))
    }

    @Test("httpError with too many input tokens body → contains 토큰")
    func httpError_bodyTooManyTokens_message() {
        let error: Error = AIProviderError.httpError(statusCode: 200, body: "too many input tokens")
        #expect(error.userFacingMessage.contains("토큰"))
    }

    @Test("httpError 429 with context_length_exceeded → 429는 항상 요청 한도 (rate limit)")
    func httpError429_bodyOverride_message() {
        let error: Error = AIProviderError.httpError(statusCode: 429, body: "context_length_exceeded")
        #expect(error.userFacingMessage.contains("요청 한도"))
    }

    // MARK: - Google 429 quota exceeded (토큰 분당 할당량 초과 = rate limit)

    @Test("apiError quota exceeded tokens_per_minute → 요청 한도 (rate limit, NOT token limit)")
    func apiError_quotaTokensPerMinute_isRateLimit() {
        let googleBody = "Quota exceeded for aiplatform.googleapis.com/generate_content_input_tokens_per_minute_per_project"
        let error: Error = AIProviderError.apiError(googleBody)
        #expect(error.userFacingMessage.contains("요청 한도"))
    }

    @Test("httpError 429 + Google RESOURCE_EXHAUSTED → 요청 한도")
    func httpError429_resourceExhausted_isRateLimit() {
        let body = "{\"error\":{\"code\":429,\"message\":\"Resource has been exhausted (e.g. check quota).\",\"status\":\"RESOURCE_EXHAUSTED\"}}"
        let error: Error = AIProviderError.httpError(statusCode: 429, body: body)
        #expect(error.userFacingMessage.contains("요청 한도"))
    }

    // MARK: - apiError keyword classification: rate limit

    @Test("apiError rate limit reached → contains 요청 한도")
    func apiError_rateLimit_message() {
        let error: Error = AIProviderError.apiError("rate limit reached")
        #expect(error.userFacingMessage.contains("요청 한도"))
    }

    @Test("apiError quota exceeded → contains 요청 한도")
    func apiError_quotaExceeded_message() {
        let error: Error = AIProviderError.apiError("quota exceeded")
        #expect(error.userFacingMessage.contains("요청 한도"))
    }

    @Test("apiError too many requests → contains 요청 한도")
    func apiError_tooManyRequests_message() {
        let error: Error = AIProviderError.apiError("too many requests")
        #expect(error.userFacingMessage.contains("요청 한도"))
    }

    // MARK: - apiError keyword classification: auth

    @Test("apiError unauthorized access → contains 인증")
    func apiError_unauthorized_message() {
        let error: Error = AIProviderError.apiError("unauthorized access")
        #expect(error.userFacingMessage.contains("인증"))
    }

    @Test("apiError invalid key provided → contains 인증")
    func apiError_invalidKey_message() {
        let error: Error = AIProviderError.apiError("invalid key provided")
        #expect(error.userFacingMessage.contains("인증"))
    }

    // MARK: - apiError keyword classification: overload, timeout, network

    @Test("apiError server overloaded → contains 과부하")
    func apiError_overloaded_message() {
        let error: Error = AIProviderError.apiError("server overloaded")
        #expect(error.userFacingMessage.contains("과부하"))
    }

    @Test("apiError request timed out → contains 시간 초과")
    func apiError_timedOut_message() {
        let error: Error = AIProviderError.apiError("request timed out")
        #expect(error.userFacingMessage.contains("시간이 초과"))
    }

    @Test("apiError network connection failed → contains 네트워크")
    func apiError_networkFailed_message() {
        let error: Error = AIProviderError.apiError("network connection failed")
        #expect(error.userFacingMessage.contains("네트워크"))
    }

    // MARK: - apiError fallback cases

    @Test("apiError empty string → contains 일시적인 오류")
    func apiError_empty_message() {
        let error: Error = AIProviderError.apiError("")
        #expect(error.userFacingMessage.contains("일시적인 오류"))
    }

    @Test("apiError long message → truncated with …")
    func apiError_longMessage_truncated() {
        let longMsg = String(repeating: "x", count: 250)
        let error: Error = AIProviderError.apiError(longMsg)
        #expect(error.userFacingMessage.contains("…"))
    }

    // MARK: - HTTP error: unknown status code fallback

    @Test("httpError 999 → contains 999")
    func httpError999_fallback_message() {
        let error: Error = AIProviderError.httpError(statusCode: 999, body: "")
        #expect(error.userFacingMessage.contains("999"))
    }

    // MARK: - validateHTTPResponse with data (body 포함)

    @Test("validateHTTPResponse: 200 → 에러 없음")
    func validateHTTPResponse_200_noError() throws {
        let provider = MockAIProvider()
        let response = HTTPURLResponse(
            url: URL(string: "https://test.com")!, statusCode: 200,
            httpVersion: nil, headerFields: nil
        )!
        try provider.validateHTTPResponse(response, data: Data("ok".utf8))
    }

    @Test("validateHTTPResponse: 404 + data → 에러에 실제 body 포함")
    func validateHTTPResponse_404_includesBody() {
        let provider = MockAIProvider()
        let response = HTTPURLResponse(
            url: URL(string: "https://test.com")!, statusCode: 404,
            httpVersion: nil, headerFields: nil
        )!
        let data = Data("{\"error\":{\"message\":\"Model not found\"}}".utf8)

        do {
            try provider.validateHTTPResponse(response, data: data)
            Issue.record("Expected error")
        } catch let error as AIProviderError {
            if case .httpError(let code, let body) = error {
                #expect(code == 404)
                #expect(body.contains("Model not found"))
            } else {
                Issue.record("Wrong error variant: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("validateHTTPResponse: 429 + data → 에러에 실제 body 포함")
    func validateHTTPResponse_429_includesBody() {
        let provider = MockAIProvider()
        let response = HTTPURLResponse(
            url: URL(string: "https://test.com")!, statusCode: 429,
            httpVersion: nil, headerFields: nil
        )!
        let data = Data("{\"error\":\"rate limit exceeded\"}".utf8)

        do {
            try provider.validateHTTPResponse(response, data: data)
            Issue.record("Expected error")
        } catch let error as AIProviderError {
            if case .httpError(_, let body) = error {
                #expect(body.contains("rate limit exceeded"))
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("validateHTTPResponse: data 없음 → 기본 폴백 메시지")
    func validateHTTPResponse_noData_fallbackMessage() {
        let provider = MockAIProvider()
        let response = HTTPURLResponse(
            url: URL(string: "https://test.com")!, statusCode: 500,
            httpVersion: nil, headerFields: nil
        )!

        do {
            try provider.validateHTTPResponse(response)
            Issue.record("Expected error")
        } catch let error as AIProviderError {
            if case .httpError(let code, let body) = error {
                #expect(code == 500)
                #expect(body.contains("500"))
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("validateHTTPResponse: 빈 data → 폴백 메시지")
    func validateHTTPResponse_emptyData_fallbackMessage() {
        let provider = MockAIProvider()
        let response = HTTPURLResponse(
            url: URL(string: "https://test.com")!, statusCode: 502,
            httpVersion: nil, headerFields: nil
        )!

        do {
            try provider.validateHTTPResponse(response, data: Data())
            Issue.record("Expected error")
        } catch let error as AIProviderError {
            if case .httpError(let code, let body) = error {
                #expect(code == 502)
                #expect(body.contains("502"))
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
