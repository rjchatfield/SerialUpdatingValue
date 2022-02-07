import XCTest

extension String: Error {}
extension Date: @unchecked Sendable {}
extension XCTestExpectation: @unchecked Sendable {}

struct Token: Hashable {
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

extension Result {
    var isFailure: Bool {
        switch self {
        case .failure: return true
        case .success: return false
        }
    }
    
    var stringError: String? {
        guard case .failure(let error) = self,
              let stringError = error as? String
        else { return nil }
        return stringError
    }
    
    var isCancellationError: Bool {
        guard case .failure(let error) = self,
              error is CancellationError
        else { return false }
        return true
    }
}
