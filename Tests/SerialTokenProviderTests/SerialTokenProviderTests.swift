import XCTest
@testable import SerialTokenProvider

@MainActor var fetchAttempts = 0

final class SerialTokenProviderTests: XCTestCase {

    @MainActor
    func testExample() throws {
        let FETCH_TIMEINTERVAL: TimeInterval = 0.5
        let TOKEN_TIMEOUT_TIMEINTERVAL: TimeInterval = 1.0
        
        let provider = SerialUpdatingValue.tokenProvider(
            getNewTokenFromMK: {
                Deferred {
                    Future { completion in
                        Task { @MainActor in
                            fetchAttempts += 1
                            let i = fetchAttempts
                            print("🌥 fetching \(i)...")
                            DispatchQueue.main.asyncAfter(deadline: .now() + FETCH_TIMEINTERVAL) {
                                print("🌥  ...fetched \(i)!")
                                completion(.success(Token(expires: Date().addingTimeInterval(TOKEN_TIMEOUT_TIMEINTERVAL))))
                            }
                        }
                    }
                }
                .eraseToAnyPublisher()
            }
        )
        
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
        sleep(seconds: TOKEN_TIMEOUT_TIMEINTERVAL)
        XCTAssertEqual(fetchAttempts, 1)
        
        let exps4 = [
            runExample(provider: provider),
            runExample(provider: provider),
        ]

        wait(for: exps1 + exps2 + exps3 + exps4, timeout: 10_000)
        
        XCTAssertEqual(fetchAttempts, 2)
    }
    
    var i = 0
    @MainActor
    func runExample(provider: SerialUpdatingValue<Token>) -> XCTestExpectation {
        self.i += 1
        let i = self.i
        let exp = expectation(description: "wait for \(i)")
        print("🧐", i, "Dispatching async")
        DispatchQueue.global().async {
            Task.detached(priority: TaskPriority.medium) { [provider] in
                print("🧐", i, " Inside Task: getting token...")
                let token = await provider.getValue()
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

public actor SerialUpdatingValue<Value> where Value: Sendable {
    private var latestValue: Value?
    private var isUpdating = false
    private var callbacks: [(Value) -> Void] = []
    
    private let isValid: @Sendable (Value) -> Bool
    private let getUpdatedValue: @Sendable () async -> Value
    
    // MARK: -
    
    public init(
        isValid: @escaping @Sendable (Value) -> Bool = { _ in true },
        getUpdatedValue: @escaping @Sendable () async -> Value
    ) {
        self.isValid = isValid
        self.getUpdatedValue = getUpdatedValue
    }
    
    public func getValue() async -> Value {
        await withCheckedContinuation({ cont in
            append(callback: cont.resume(returning:))
        })
    }
    
    // MARK: -
    
    private func append(callback: @escaping (Value) -> Void) {
        if let value = latestValue, isValid(value) {
            return callback(value)
        } else {
            callbacks.append(callback)
            guard !isUpdating else { return }
            latestValue = nil
            isUpdating = true
            Task {
                let updatedValue = await getUpdatedValue()
                latestValue = updatedValue
                isUpdating = false
                for callback in callbacks {
                    callback(updatedValue)
                }
                callbacks = []
            }
        }
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
    
    private static var _count = 0
    private static var count: Int {
        _count += 1
        return _count
    }
}

extension Date: @unchecked Sendable {}
extension XCTestExpectation: @unchecked Sendable {}
