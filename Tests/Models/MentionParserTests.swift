import Testing
import Foundation
@testable import DOUGLAS

@Suite("MentionParser Tests")
struct MentionParserTests {

    private let agents = [
        makeTestAgent(name: "번역가"),
        makeTestAgent(name: "백엔드 개발자"),
        makeTestAgent(name: "프론트엔드 개발자"),
        makeTestAgent(name: "QA 전문가"),
    ]

    // MARK: - 정확 매칭

    @Test("정확 매칭 — @번역가 이거 뭐야")
    func exactMatch() {
        let result = MentionParser.parse("@번역가 이거 뭐야", agents: agents)
        #expect(result.mentions.count == 1)
        #expect(result.mentions[0].name == "번역가")
        #expect(result.cleanText == "이거 뭐야")
    }

    // MARK: - 접두어 매칭

    @Test("접두어 매칭 — @번역 → 번역가")
    func prefixMatch() {
        let result = MentionParser.parse("@번역 이거 뭐야", agents: agents)
        #expect(result.mentions.count == 1)
        #expect(result.mentions[0].name == "번역가")
        #expect(result.cleanText == "이거 뭐야")
    }

    // MARK: - 복수 멘션

    @Test("복수 멘션 — @번역가 @QA 이거 봐줘")
    func multipleMentions() {
        let result = MentionParser.parse("@번역가 @QA 이거 봐줘", agents: agents)
        #expect(result.mentions.count == 2)
        let names = Set(result.mentions.map { $0.name })
        #expect(names.contains("번역가"))
        #expect(names.contains("QA 전문가"))
        #expect(result.cleanText == "이거 봐줘")
    }

    // MARK: - 미매칭

    @Test("미매칭 — @없는사람 원문 유지")
    func noMatch() {
        let result = MentionParser.parse("@없는사람 이거 뭐야", agents: agents)
        #expect(result.mentions.isEmpty)
        #expect(result.cleanText == "@없는사람 이거 뭐야")
    }

    // MARK: - 멘션 없음

    @Test("멘션 없음 — 일반 텍스트")
    func noMention() {
        let result = MentionParser.parse("그냥 질문입니다", agents: agents)
        #expect(result.mentions.isEmpty)
        #expect(result.cleanText == "그냥 질문입니다")
    }

    // MARK: - 빈 텍스트

    @Test("빈 텍스트")
    func emptyText() {
        let result = MentionParser.parse("", agents: agents)
        #expect(result.mentions.isEmpty)
        #expect(result.cleanText == "")
    }

    // MARK: - 에이전트 없음

    @Test("에이전트 목록 빈 경우")
    func noAgents() {
        let result = MentionParser.parse("@번역가 이거 뭐야", agents: [])
        #expect(result.mentions.isEmpty)
        #expect(result.cleanText == "@번역가 이거 뭐야")
    }

    // MARK: - 접두어 모호 (복수 후보)

    @Test("접두어 매칭 — @프론트엔드")
    func ambiguousPrefix() {
        let result = MentionParser.parse("@프론트엔드 이거 봐줘", agents: agents)
        #expect(result.mentions.count == 1)
        #expect(result.mentions[0].name == "프론트엔드 개발자")
    }

    // MARK: - 멘션 + 일반 텍스트 혼합

    @Test("중간 위치 멘션")
    func mentionInMiddle() {
        let result = MentionParser.parse("이거 @번역가 번역해줘", agents: agents)
        #expect(result.mentions.count == 1)
        #expect(result.mentions[0].name == "번역가")
        #expect(result.cleanText == "이거 번역해줘")
    }

    // MARK: - 중복 멘션

    @Test("같은 에이전트 중복 멘션 → 1명만")
    func duplicateMention() {
        let result = MentionParser.parse("@번역가 @번역가 이거 뭐야", agents: agents)
        #expect(result.mentions.count == 1)
        #expect(result.mentions[0].name == "번역가")
    }

    // MARK: - 대소문자

    @Test("대소문자 무시 매칭 — @qa → QA 전문가")
    func caseInsensitive() {
        let result = MentionParser.parse("@qa 이거 테스트해줘", agents: agents)
        #expect(result.mentions.count == 1)
        #expect(result.mentions[0].name == "QA 전문가")
    }

    // MARK: - 이메일 오탐 방지

    @Test("이메일 주소는 멘션 아님")
    func emailNotMention() {
        let result = MentionParser.parse("user@domain.com 보내줘", agents: agents)
        #expect(result.mentions.isEmpty)
    }
}
