import XCTest
@testable import SerialTokenProvider

final class SerialTokenProviderTests: XCTestCase {

    func testExample() throws {
        let FETCH_TIMEINTERVAL: TimeInterval = 0.5
        let TOKEN_TIMEOUT_TIMEINERVAL: TimeInterval = 1.0
        var fetchAttempts = 0
        
        let provider = TokenProvider(getNewTokenFromMK: {
            Deferred {
                Future { completion in
                    fetchAttempts += 1
                    print("🌥 fetching \(fetchAttempts)...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + FETCH_TIMEINTERVAL) {
                        print("🌥  ...fetched \(fetchAttempts)!")
                        completion(.success(Token(expires: Date().addingTimeInterval(TOKEN_TIMEOUT_TIMEINERVAL))))
                    }
                }
            }
            .eraseToAnyPublisher()
        })
        
        let exps1 = [
            runExample(provider: provider),
            runExample(provider: provider),
        ]
        
        sleep(seconds: 0.1)
        
        let exps2 = [
            runExample(provider: provider),
//            runExample(provider: provider),
        ]
        
        sleep(seconds: FETCH_TIMEINTERVAL)

        let exps3 = [
            runExample(provider: provider),
            runExample(provider: provider),
        ]

        XCTAssertEqual(fetchAttempts, 1)
        sleep(seconds: TOKEN_TIMEOUT_TIMEINERVAL)
        XCTAssertEqual(fetchAttempts, 1)
        
        let exps4 = [
            runExample(provider: provider),
            runExample(provider: provider),
        ]

        wait(for: exps1 + exps2 + exps3 + exps4, timeout: 10_000)
        
        XCTAssertEqual(fetchAttempts, 2)
    }
    
    var i = 0
    func runExample(provider: TokenProvider) -> XCTestExpectation {
        self.i += 1
        let i = self.i
        let exp = expectation(description: "wait for \(i)")
        print("🧐", i, "Dispatching async")
        DispatchQueue.global().async {
            Task.detached(priority: TaskPriority.medium) {
                print("🧐", i, " Inside Task: getting token...")
                let token = try await provider.getToken()
                print("🧐", i, "  got token:", token)
                exp.fulfill()
            }
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
}

actor TokenProvider {
    
    private let newTokenFromMK: AnyPublisher<Token, Error>
    private var isFetching = false
    private var latestToken: Token?
    private var callbacks: [(Result<Token, Error>) -> Void] = []
    
    init(getNewTokenFromMK: @escaping () -> AnyPublisher<Token, Error>) {
        self.newTokenFromMK = getNewTokenFromMK()
    }
    
    func getToken() async throws -> Token {
        try await withCheckedThrowingContinuation({ cont in
            append(callback: { (result: Result<Token, Error>) in
                cont.resume(with: result)
            })
        })
    }
    
    private func append(callback: @escaping (Result<Token, Error>) -> Void) {
        if let token = latestToken, token.isValid {
            return callback(.success(token))
        } else {
            callbacks.append(callback)
            guard !isFetching else { return }
            latestToken = nil
            isFetching = true
            Task {
                for try await newToken in newTokenFromMK.values {
                    self.latestToken = newToken
                    self.isFetching = false
                    let _callbacks = callbacks
                    callbacks = []
                    for callback in _callbacks {
                        callback(.success(newToken))
                    }
                    return
                }
                assertionFailure("Left for loop and Future didn't throw or return a value")
            }
        }
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
    
    private static var _count = 0
    private static var count: Int {
        _count += 1
        return _count
    }
}
