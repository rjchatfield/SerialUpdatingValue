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
            /// Check for in-flight task, return value only if still valid, rethrow error and reset state
            if let taskHandle = taskHandle {
                do {
                    let value = try await taskHandle.value
                    try Task.checkCancellation()
                    if isValid(value) {
                        return value
                    }
                } catch let cancellationError as CancellationError {
                    /// If this child-task is cancelled, don't nil out `taskHandle` so next caller can still get value
                    throw cancellationError
                } catch {
                    /// If in-flight task returns an error, rethrow error and nil out `taskHandle` so next caller will get updated value
                    self.taskHandle = nil
                    throw error
                }
            }
            /// Else, there is no valid value & now requires updated value
            let taskHandle = Task { try await getUpdatedValue() }
            self.taskHandle = taskHandle
            return try await taskHandle.value /// Assumes new values are valid
        }
    }
}
