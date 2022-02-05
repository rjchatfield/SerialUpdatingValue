import XCTest
@testable import SerialTokenProvider

final class SerialTokenProviderTests: XCTestCase {
    func testExample() throws {
        
        var fetchAttempts = 0
        
        let provider = TokenProvider(getNewTokenFromMK: {
            Deferred {
                Future { completion in
                    fetchAttempts += 1
                    print("🌥 fetching \(fetchAttempts)...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        print("🌥  ...fetched \(fetchAttempts)!")
                        completion(.success(Token(expires: Date().addingTimeInterval(100))))
                    }
                }
            }
            .eraseToAnyPublisher()
        })
        
        wait(for: [
            runExample(i: 1, provider: provider),
            runExample(i: 2, provider: provider),
            runExample(i: 3, provider: provider),
        ], timeout: 100)
        
        XCTAssertEqual(fetchAttempts, 3)
    }
    
    func runExample(i: Int, provider: TokenProvider) -> XCTestExpectation {
        let exp = expectation(description: "wait for \(i)")
        print("🧐", i, "...")
        DispatchQueue.global().async {
            Task.detached(priority: TaskPriority.medium) {
                print("🧐", i, " getting token...")
                let token = try await provider.getToken()
                print("🧐", i, "  got token:", token)
                exp.fulfill()
            }
        }
        return exp
    }
}

actor TokenProvider {
    
    let newTokenFromMK: AnyPublisher<Token, Error>
    var latestToken: Token?
    var cancellables = Set<AnyCancellable>()
    
    init(getNewTokenFromMK: @escaping () -> AnyPublisher<Token, Error>) {
        self.newTokenFromMK = getNewTokenFromMK()
    }
    
    func getToken() async throws -> Token {
//        let values = newTokenFromMK.values
//        guard let first = try await values.first(where: { _ in true }) else {
//            throw "Left for loop and Future didn't throw or return a value"
//        }
//        return first
//        for try await token in newTokenFromMK.values {
//            return token
//        }
//        throw "Left for loop and Future didn't throw or return a value"
        try await withCheckedThrowingContinuation { cont in
            newTokenFromMK
                .first()
                .sink { (completion: Subscribers.Completion<Error>) in
                    switch completion {
                    case .finished:
                        break
                    case .failure(let error):
                        cont.resume(throwing: error)
                    }
                } receiveValue: { token in
                    cont.resume(returning: token)
                }
                .store(in: &cancellables)
        }
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
