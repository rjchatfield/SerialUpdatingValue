/// Thread -safe
public actor SerialUpdatingValue<Value> where Value: Sendable {
    
    // MARK: - Properties
    
    private let isValid: @Sendable (Value) -> Bool
    private let getUpdatedValue: @Sendable () async throws -> Value
    
    private var latestValue: Result<Value, Error>? {
        didSet {
            guard let updatedValue = latestValue else { return }
            for callback in callbacks {
                Task {
                    callback(updatedValue)
                }
            }
            callbacks = []
        }
    }
    
    private var callbacks: [@Sendable (Result<Value, Error>) -> Void] = []
    
    private var updateTask: Task<(), Never>?
    
    // MARK: - Life cycle
    
    public init(
        isValid: @escaping @Sendable (Value) -> Bool = { _ in true },
        getUpdatedValue: @escaping @Sendable () async throws -> Value
    ) {
        self.isValid = isValid
        self.getUpdatedValue = getUpdatedValue
    }
    
    deinit {
        latestValue = .failure(SerialUpdatingValueError.actorDeallocated) // flush callbacks
        updateTask?.cancel() // cancel
    }
    
    // MARK: - Public API
    
    public var value: Value {
        get async throws {
            try await withUnsafeThrowingContinuation { cont in
                append(callback: { [cont] result in
                    cont.resume(with: result)
                })
            }
        }
    }
    
    // MARK: - Private methods
    
    private func append(callback: @escaping @Sendable (Result<Value, Error>) -> Void) {
        if case .success(let value) = latestValue, isValid(value) {
            return callback(.success(value))
//        } else if case .failure(let error) = latestValue {
//            return callback(.failure(error))
        } else {
            latestValue = nil // clear out invalid value
            callbacks.append(callback) // enqueue callback
            guard updateTask == nil else { return } // task is already running, will be called back from other callback
            updateTask = Task {
                do {
                    latestValue = .success(try await getUpdatedValue())
                } catch {
                    latestValue = .failure(error)
                }
                updateTask = nil
            }
        }
    }
}

private enum SerialUpdatingValueError: Error {
    case actorDeallocated
}
