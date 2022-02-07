/// Thread-safe access to a lazily retrieved value, with optional validity checking
public actor SerialUpdatingValue<Value> where Value: Sendable {
    
    // MARK: - Properties
    
    private let isValid: @Sendable (Value) -> Bool
    private let getUpdatedValue: @Sendable () async throws -> Value
    private var taskHandle: Task<Value, Error>?
    
    // MARK: - Life cycle
    
    /// - Parameters:
    ///   - isValid: Run against the locally stored `latestValue`, if `false` then value will be updated.
    ///   - getUpdatedValue: Long-running task to get updated value. Will be called lazily, initially, and if stored `latestValue` is no longer valid
    public init(
        isValid: @escaping @Sendable (Value) -> Bool = { _ in true },
        getUpdatedValue: @escaping @Sendable () async throws -> Value
    ) {
        self.isValid = isValid
        self.getUpdatedValue = getUpdatedValue
    }
    
    // MARK: - Public API
    
    /// Will get up-to-date value
    public var value: Value {
        get async throws {
            if let value = try? await taskHandle?.value, isValid(value) {
                return value
            } else {
                let taskHandle = Task { try await getUpdatedValue() }
                self.taskHandle = taskHandle
                return try await self.value /// recursively check `isValid`
            }
        }
    }
}

// MARK: -

private enum SerialUpdatingValueError: Error {
    case actorDeallocated
}
