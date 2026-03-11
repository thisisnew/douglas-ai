import Foundation

/// CJK 인지 토큰 수 추정 유틸리티
/// - CJK (한/중/일): ~2자/토큰
/// - ASCII/Latin: ~4자/토큰
/// 과대 추정 허용, 과소 추정 방지 (보수적 추정)
enum TokenEstimator {

    /// 텍스트의 대략적 토큰 수 추정
    static func estimate(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        var cjkCount = 0
        var otherCount = 0

        for scalar in text.unicodeScalars {
            if isCJK(scalar) {
                cjkCount += 1
            } else {
                otherCount += 1
            }
        }

        // CJK: ~2자/토큰, 기타: ~4자/토큰
        // 소수점 이하 올림 (보수적)
        return (cjkCount + 1) / 2 + (otherCount + 3) / 4
    }

    /// 여러 텍스트의 합산 토큰 추정
    static func estimate(_ texts: [String]) -> Int {
        texts.reduce(0) { $0 + estimate($1) }
    }

    /// CJK 문자 판별 (한국어, 중국어, 일본어)
    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (0xAC00...0xD7AF).contains(v) ||  // 한글 음절
               (0x1100...0x11FF).contains(v) ||  // 한글 자모
               (0x3130...0x318F).contains(v) ||  // 한글 호환 자모
               (0x3000...0x303F).contains(v) ||  // CJK 기호/구두점
               (0x3040...0x309F).contains(v) ||  // 히라가나
               (0x30A0...0x30FF).contains(v) ||  // 카타카나
               (0x4E00...0x9FFF).contains(v) ||  // CJK 통합 한자
               (0xF900...0xFAFF).contains(v)     // CJK 호환 한자
    }
}
