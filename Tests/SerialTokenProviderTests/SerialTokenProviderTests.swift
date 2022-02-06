import XCTest
@testable import SerialTokenProvider
import Combine

final class SerialTokenProviderTests: XCTestCase {
    
    func testAsyncLet8() async throws {
        let provider = tokenProvider
        async let t1 = provider.value
        async let t2 = provider.value
        async let t3 = provider.value
        async let t4 = provider.value
        async let t5 = provider.value
        async let t6 = provider.value
        async let t7 = provider.value
        async let t8 = provider.value
        _ = try await (t1, t2, t3, t4, t5, t6, t7, t8)
        XCTAssertEqual(fetchAttempts, 1)
    }
    
    func testTaskGroup100() async throws {
        let tokens = await withTaskGroup(of: Token?.self) { group -> [Token] in
            let provider = tokenProvider
            for _ in 1...100 {
                group.addTask(priority: TaskPriority?.none) {
                    try? await provider.value
                }
            }
            var result: [Token] = []
            while let optional = await group.next(), let value = optional {
                result.append(value)
            }
            return result
        }
        XCTAssertEqual(tokens.count, 100)
        XCTAssertEqual(fetchAttempts, 1)
    }
    
    func testMessy1() async {
        let provider = tokenProvider
        let exp = runExample(provider: provider)
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(fetchAttempts, 1)
    }

    func testMessyLots() async {
        let provider = tokenProvider
        let exps = (1...100).map { _ in runExample(provider: provider) }
        wait(for: exps, timeout: 10_000)
        XCTAssertEqual(fetchAttempts, 1)
    }
    
    func testMessyExample() async {
        let provider = tokenProvider

        let exps1: [XCTestExpectation] = [
            runExample(provider: provider),
            runExample(provider: provider),
        ]

        sleep(seconds: 0.1)

        let exps2: [XCTestExpectation] = [
            runExample(provider: provider),
            runExample(provider: provider),
        ]

        sleep(seconds: FETCH_TIMEINTERVAL)

        let exps3: [XCTestExpectation] = [
            runExample(provider: provider),
            runExample(provider: provider),
        ]

        XCTAssertEqual(fetchAttempts, 1)
        sleep(seconds: TOKEN_TIMEOUT_TIMEINTERVAL + 1)
        XCTAssertEqual(fetchAttempts, 1)

        let exps4: [XCTestExpectation] = [
            runExample(provider: provider),
            runExample(provider: provider),
        ]

        wait(for: exps1 + exps2 + exps3 + exps4, timeout: 10_000)

        XCTAssertEqual(fetchAttempts, 2)
    }

    // MARK: - Life cycle
    
    override func setUp() {
        fetchAttempts = 0
        Token._count = 0
        self.exampleCount = 0
        self.sleepCount = 0
    }
    
    // MARK: - Helpers

    private var exampleCount = 0
    private func runExample(provider: SerialUpdatingValue<Token>) -> XCTestExpectation {
        self.exampleCount += 1
        let i = self.exampleCount
        let exp = expectation(description: "wait for \(i)")
        print("🧐", i, "Dispatching async")
        Task.detached(priority: TaskPriority.medium) { [provider] in
            print("🧐", i, " Inside Task: getting token...")
            let token = try await provider.value
            print("🧐", i, "  got token:", token)
            exp.fulfill()
        }
        return exp
    }
    
    private var sleepCount = 0
    private func sleep(seconds: TimeInterval) {
        self.sleepCount += 1
        let i = self.sleepCount
        let sleepExp = expectation(description: "sleep \(i)")
        print(" 😴", i, "for:", seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            sleepExp.fulfill()
        }
        wait(for: [sleepExp], timeout: 10000)
    }

    private var tokenProvider: SerialUpdatingValue<Token> {
        SerialUpdatingValue(
            isValid: { token in
                token.isValid
            },
            getUpdatedValue: { [self] in
                /// Bridge between Combine API to a Async/Throwing function
                for try await newToken in self.getToken().values {
                    return newToken
                }
                throw "Left for loop and Future didn't throw or return a value"
            }
        )
    }
    
    private var fetchAttempts = 0
    private func getToken() -> AnyPublisher<Token, Error> {
        Deferred { [self] in
            Future { completion in
                self.fetchAttempts += 1
                let i = self.fetchAttempts
                print("🌥 fetching \(i)...")
                DispatchQueue.main.asyncAfter(deadline: .now() + FETCH_TIMEINTERVAL) {
                    print("🌥  ...fetched \(i)!")
                    completion(.success(Token(expires: Date().addingTimeInterval(TOKEN_TIMEOUT_TIMEINTERVAL))))
                }
            }
        }
        .eraseToAnyPublisher()
    }
}

let FETCH_TIMEINTERVAL: TimeInterval = 0.5
let TOKEN_TIMEOUT_TIMEINTERVAL: TimeInterval = 1.0

extension String: Error {}
extension Date: @unchecked Sendable {}
extension XCTestExpectation: @unchecked Sendable {}

 struct Token {
    let count = count
    let expires: Date
    
    var isValid: Bool {
        Date() < expires
    }
    
    static var _count = 0
    static var count: Int {
        _count += 1
        return _count
    }
}
