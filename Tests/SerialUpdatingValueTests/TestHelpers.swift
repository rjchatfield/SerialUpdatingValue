import XCTest

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
