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
            if let latestValue = try await latestValue, isValid(latestValue) {
                /// May throw if:
                /// - `getUpdatedValue()` returned an error
                /// - Task was cancelled
                return latestValue
                
            } else {
                /// There is no valid value & now requires updated value. Either:
                /// - `taskHandle` was `nil`
                /// - `value` is no longer valid
                /// - `getUpdatedValue()` returned an error
                taskHandle = Task { try await getUpdatedValue() }
                return try await self.value /// use recursion to check `isValid` and cancellation
            }
        }
    }
    
    // MARK: - Private methods
    
    /// Check for in-flight task and return value. Will rethrow error and reset state.
    private var latestValue: Value? {
        get async throws {
            guard let taskHandle = taskHandle else { return nil }
            do {
                let value = try await taskHandle.value
                try Task.checkCancellation()
                return value
                
            } catch let cancellationError as CancellationError {
                /// If this child-task is cancelled, don't nil out `taskHandle` so next caller can still get value
                throw cancellationError
                
            } catch {
                /// If in-flight task returns an error, rethrow error and nil out `taskHandle` so next caller will get updated value
                self.taskHandle = nil
                throw error
            }
        }
    }
}
