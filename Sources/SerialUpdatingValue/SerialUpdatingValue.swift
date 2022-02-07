/// Thread-safe access to a lazily retrieved value, with optional validity checking
public actor SerialUpdatingValue<Value> where Value: Sendable {
    
    // MARK: - Properties
    
    private let isValid: @Sendable (Value) -> Bool
    private let getUpdatedValue: @Sendable () async throws -> Value
    
    private var latestValue: Result<Value, Error>?
    private var callbackQueue: [@Sendable (Result<Value, Error>) -> Void] = []
    private var taskHandle: Task<(), Never>?
    
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
    
    deinit {
        /// Not sure if there is a valid case when an Actor could
        taskHandle?.cancel() /// cancel long-running update task
        update(.failure(SerialUpdatingValueError.actorDeallocated)) /// flush callbacks
    }
    
    // MARK: - Public API
    
    /// Will get up-to-date value
    public var value: Value {
        get async throws {
            try await withCheckedThrowingContinuation { continuation in
                append(callback: { [continuation] result in
                    continuation.resume(with: result)
                })
            }
        }
    }
    
    // MARK: - Private methods
    
    private func append(
        callback: @escaping @Sendable (Result<Value, Error>) -> Void
    ) {
        if case .success(let value) = latestValue, isValid(value) {
            return callback(.success(value))
        } else {
            /// There is no valid value, so must get a new value
            latestValue = nil /// clear out invalid value
            callbackQueue.append(callback) /// enqueue callback
            guard taskHandle == nil else { return } /// task is already running, will be called back from other callback
            taskHandle = Task {
                let newValue: Result<Value, Error>
                do {
                    newValue = .success(try await getUpdatedValue())
                } catch is CancellationError {
                    return /// Task may be cancelled during dealloc and callbacks will be handled differently
                } catch {
                    newValue = .failure(error)
                }
                guard !Task.isCancelled else {
                    return /// Task may be cancelled during dealloc and callbacks will be handled differently
                }
                update(newValue)
                taskHandle = nil
            }
        }
    }
    
    private func update(
        _ updatedValue: Result<Value, Error>
    ) {
        latestValue = updatedValue
        /// Call all callbacks
        for callback in callbackQueue {
            callback(updatedValue)
        }
        callbackQueue.removeAll() /// Note: all of this method is executed synchrnously without suspension. Reentrancy will not occur, so this is safe to empty out after the callbacks are called
    }
}

// MARK: -

private enum SerialUpdatingValueError: Error {
    case actorDeallocated
}
