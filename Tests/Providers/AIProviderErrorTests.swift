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

    @Test("httpError 429 with context_length_exceeded → body wins over HTTP code (토큰)")
    func httpError429_bodyOverride_message() {
        let error: Error = AIProviderError.httpError(statusCode: 429, body: "context_length_exceeded")
        #expect(error.userFacingMessage.contains("토큰"))
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
}
