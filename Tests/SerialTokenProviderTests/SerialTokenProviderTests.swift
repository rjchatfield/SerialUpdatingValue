import XCTest
@testable import SerialTokenProvider

final class SerialTokenProviderTests: XCTestCase {
    func testExample() throws {
        
        var fetchAttempts = 0
        
        let provider = TokenProvider(getNewTokenFromMK: {
            Future { completion in
                fetchAttempts += 1
                print("🌥 fetching \(fetchAttempts)...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    print("🌥  ...fetched \(fetchAttempts)!")
                    completion(.success(Token(expires: Date().addingTimeInterval(100))))
                }
            }
            .eraseToAnyPublisher()
        })
        
        wait(for: [
            runExample(i: 1, provider: provider),
            runExample(i: 2, provider: provider),
            runExample(i: 3, provider: provider),
        ], timeout: 100)
    }
    
    func runExample(i: Int, provider: TokenProvider) -> XCTestExpectation {
        let exp = expectation(description: "wait for \(i)")
        print(i, "...")
        DispatchQueue.global().async {
            Task.detached(priority: TaskPriority.medium) {
                print(i, " getting token...")
                let token = try await provider.getToken()
                print(i, "  got token", token)
                exp.fulfill()
            }
        }
        return exp
    }
}

actor TokenProvider {
    
    let getNewTokenFromMK: () -> AnyPublisher<Token, Error>
    var latestToken: Token?
    
    init(getNewTokenFromMK: @escaping () -> AnyPublisher<Token, Error>) {
        self.getNewTokenFromMK = getNewTokenFromMK
    }
    
    func getToken() async throws -> Token {
//        let values = getTokenFromMK().values
//        let nonNilValues = values.compactMap({ $0 })
//        let first = try await nonNilValues.first(where: { _ in true })
//        return first
        for try await token in getNewTokenFromMK().values {
            return token
        }
        throw "Left for loop and Future didn't throw or return a value"
    }
}

import Combine

extension String: Error {}

struct Token {
    let expires: Date
    
    var isValid: Bool {
        Date() < expires
    }
}
