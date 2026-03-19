import Testing
@testable import DOUGLAS

@Suite("StreamBuffer 스레드 안전성")
struct StreamBufferTests {

    @Test("순차 append 누적")
    func sequentialAppend() {
        let buffer = StreamBuffer()
        let r1 = buffer.append("Hello")
        let r2 = buffer.append(" World")
        #expect(r1 == "Hello")
        #expect(r2 == "Hello World")
        #expect(buffer.current == "Hello World")
    }

    @Test("빈 문자열 append")
    func emptyAppend() {
        let buffer = StreamBuffer()
        let r = buffer.append("")
        #expect(r == "")
        #expect(buffer.current == "")
    }

    @Test("동시 append 데이터 레이스 없음")
    func concurrentAppendNoDataRace() async {
        let buffer = StreamBuffer()
        let iterations = 100

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    _ = buffer.append("\(i),")
                }
            }
        }

        // 모든 iteration의 쉼표가 누적되어야 함
        let commaCount = buffer.current.filter { $0 == "," }.count
        #expect(commaCount == iterations)
    }

    @Test("동시 append + current 읽기 안전")
    func concurrentAppendAndRead() async {
        let buffer = StreamBuffer()

        await withTaskGroup(of: Void.self) { group in
            // Writer
            group.addTask {
                for i in 0..<50 {
                    _ = buffer.append("x\(i)")
                }
            }
            // Reader
            group.addTask {
                for _ in 0..<50 {
                    _ = buffer.current  // 크래시 없이 읽기 가능해야 함
                }
            }
        }

        // 50개 append 모두 반영
        #expect(buffer.current.contains("x49"))
    }
}
