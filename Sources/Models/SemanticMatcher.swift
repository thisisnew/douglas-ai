import Foundation
import NaturalLanguage

/// NLEmbedding 기반 에이전트 의미 유사도 매칭
/// NLEmbedding.wordEmbedding을 사용하여 작업과 에이전트 간 의미 거리 계산
final class SemanticMatcher {

    // MARK: - 캐시

    /// 에이전트별 문서 벡터 캐시 [agentID: vector]
    private var agentVectorCache: [UUID: [Double]] = [:]

    /// NLEmbedding 인스턴스 (nil이면 시스템에 해당 언어 모델 없음)
    private let koreanEmbedding: NLEmbedding?
    private let englishEmbedding: NLEmbedding?

    /// 임베딩 사용 가능 여부
    var isAvailable: Bool {
        koreanEmbedding != nil || englishEmbedding != nil
    }

    // MARK: - 초기화

    init() {
        self.koreanEmbedding = NLEmbedding.wordEmbedding(for: .korean)
        self.englishEmbedding = NLEmbedding.wordEmbedding(for: .english)
    }

    // MARK: - 캐시 관리

    /// 에이전트의 벡터 표현을 캐시에 업데이트
    func updateCache(for agent: Agent) {
        // 에이전트 이름 단어는 2배 가중치 (이름 반복 = 가중치 효과)
        let combinedText = "\(agent.name) \(agent.name) \(agent.persona)"
        let vector = computeDocumentVector(combinedText)
        if !vector.isEmpty {
            agentVectorCache[agent.id] = vector
        }
    }

    /// 삭제된 에이전트의 캐시 제거
    func removeFromCache(agentID: UUID) {
        agentVectorCache.removeValue(forKey: agentID)
    }

    /// 전체 캐시 재구축
    func rebuildCache(agents: [Agent]) {
        agentVectorCache.removeAll()
        for agent in agents {
            updateCache(for: agent)
        }
    }

    // MARK: - 매칭

    /// 작업 텍스트와 에이전트들 간 의미 유사도 점수 계산
    /// - Returns: 유사도 내림차순 정렬된 (agent, score) 배열. score 범위: -1.0 ~ 1.0
    func computeScores(
        task: String,
        among agents: [Agent]
    ) -> [(agent: Agent, score: Double)] {
        let taskVector = computeDocumentVector(task)
        guard !taskVector.isEmpty else { return [] }

        return agents.compactMap { agent -> (Agent, Double)? in
            guard let agentVector = agentVectorCache[agent.id],
                  !agentVector.isEmpty,
                  agentVector.count == taskVector.count else { return nil }

            let similarity = cosineSimilarity(taskVector, agentVector)
            return (agent, similarity)
        }
        .sorted { $0.1 > $1.1 }
    }

    /// 단일 역할명과 에이전트 간 유사도 (AgentMatcher.findByKeyword 통합용)
    func similarity(roleName: String, agent: Agent) -> Double {
        let roleVector = computeDocumentVector(roleName)
        guard !roleVector.isEmpty,
              let agentVector = agentVectorCache[agent.id],
              !agentVector.isEmpty,
              roleVector.count == agentVector.count else { return 0 }

        return cosineSimilarity(roleVector, agentVector)
    }

    // MARK: - 벡터 연산

    /// 텍스트 → 평균 단어 벡터 (document embedding)
    private func computeDocumentVector(_ text: String) -> [Double] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        // 첫 번째 벡터의 차원을 기준으로 통일 (한국어/영어 차원 불일치 방지)
        var targetDimension: Int?
        var vectors: [[Double]] = []

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range]).lowercased()

            // 한국어 임베딩 시도 → 영어 임베딩 폴백
            var vec: [Double]?
            if let v = koreanEmbedding?.vector(for: word) {
                vec = v
            } else if let v = englishEmbedding?.vector(for: word) {
                vec = v
            }

            if let v = vec {
                if targetDimension == nil {
                    targetDimension = v.count
                }
                if v.count == targetDimension {
                    vectors.append(v)
                }
            }

            return true
        }

        guard !vectors.isEmpty, let dim = targetDimension else { return [] }

        // 평균 벡터 계산
        var avg = [Double](repeating: 0.0, count: dim)
        for vec in vectors {
            for i in 0..<dim { avg[i] += vec[i] }
        }
        let count = Double(vectors.count)
        for i in 0..<dim { avg[i] /= count }
        return avg
    }

    /// 코사인 유사도 계산
    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denominator = sqrt(normA) * sqrt(normB)
        return denominator > 0 ? dot / denominator : 0
    }
}
