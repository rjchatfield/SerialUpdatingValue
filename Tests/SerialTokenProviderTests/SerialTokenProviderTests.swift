import XCTest
@testable import SerialTokenProvider

let FETCH_TIMEINTERVAL: TimeInterval = 0.5
let TOKEN_TIMEOUT_TIMEINTERVAL: TimeInterval = 1.0

final class SerialTokenProviderTests: XCTestCase {
    
    func testExample() async {
        let provider = mkTokenProvider

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

    func test1() async {
        let provider = mkTokenProvider
        let exp = runExample(provider: provider)
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(fetchAttempts, 1)
    }

    func testLots() async {
        let provider = mkTokenProvider
        let exps = (1...100).map { _ in runExample(provider: provider) }
        wait(for: exps, timeout: 10_000)
        XCTAssertEqual(fetchAttempts, 1)
    }
    
    // MARK: -

    var i = 0
    func runExample(provider: SerialUpdatingValue<Token>) -> XCTestExpectation {
        self.i += 1
        let i = self.i
        let exp = expectation(description: "wait for \(i)")
        print("🧐", i, "Dispatching async")
        Task.detached(priority: TaskPriority.medium) { [provider] in
            print("🧐", i, " Inside Task: getting token...")
            let token = await provider.value
            print("🧐", i, "  got token:", token)
            exp.fulfill()
        }
        return exp
    }
    
    var sleepCount = 0
    func sleep(seconds: TimeInterval) {
        self.sleepCount += 1
        let i = self.sleepCount
        let sleepExp = expectation(description: "sleep \(i)")
        print(" 😴", i, "for:", seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            sleepExp.fulfill()
        }
        wait(for: [sleepExp], timeout: 10000)
    }
    
    override func setUp() {
        fetchAttempts = 0
        Token._count = 0
        self.i = 0
        self.sleepCount = 0
    }
    
    var fetchAttempts = 0
    var mkTokenProvider: SerialUpdatingValue<Token> {
        SerialUpdatingValue.tokenProvider(
            getNewTokenFromMK: { [self] in
                Deferred {
                    Future { completion in
                        fetchAttempts += 1
                        let i = fetchAttempts
                        print("🌥 fetching \(i)...")
                        DispatchQueue.main.asyncAfter(deadline: .now() + FETCH_TIMEINTERVAL) {
                            print("🌥  ...fetched \(i)!")
                            completion(.success(Token(expires: Date().addingTimeInterval(TOKEN_TIMEOUT_TIMEINTERVAL))))
                        }
                    }
                }
                .eraseToAnyPublisher()
            }
        )
    }
}

extension SerialUpdatingValue where Value == Token {
    
    static func tokenProvider(
        getNewTokenFromMK: @escaping @Sendable () -> AnyPublisher<Token, Error>
    ) -> Self {
        Self(
            isValid: { token in
                token.isValid
            },
            getUpdatedValue: { () async -> Token in
                do {
                    for try await newToken in getNewTokenFromMK().values {
                        return newToken
                    }
                    preconditionFailure("Left for loop and Future didn't throw or return a value")
                } catch {
                    preconditionFailure(error.localizedDescription)
                }
            }
        )
    }
}

import Combine

extension String: Error {}

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

extension Date: @unchecked Sendable {}
extension XCTestExpectation: @unchecked Sendable {}
