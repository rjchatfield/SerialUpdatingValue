import XCTest
@testable import SerialUpdatingValue
import Combine

final class SerialUpdatingValueCombineTests: XCTestCase {
    
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
    private var cancellables: Set<AnyCancellable> = []
    private func runExample(provider: SerialUpdatingValueCombine<Token>) -> XCTestExpectation {
        self.exampleCount += 1
        let i = self.exampleCount
        let exp = expectation(description: "wait for \(i)")
        print("🧐", i, "Dispatching async")
        provider.value
            .sink { token in
                print("🧐", i, "  got token:", token)
                exp.fulfill()
            }
            .store(in: &cancellables)
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
    
    private var tokenProvider: SerialUpdatingValueCombine<Token> {
        SerialUpdatingValueCombine(
            isValid: { token in
                token.isValid
            },
            getUpdatedValue: getToken
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

private let FETCH_TIMEINTERVAL: TimeInterval = 0.5
private let TOKEN_TIMEOUT_TIMEINTERVAL: TimeInterval = 1.0
