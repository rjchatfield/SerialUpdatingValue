/// Thread -safe
public actor SerialUpdatingValue<Value> where Value: Sendable {
    
    // MARK: - Properties
    
    private let isValid: @Sendable (Value) -> Bool
    private let getUpdatedValue: @Sendable () async -> Value
    
    private var latestValue: Value? {
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
    
    private var callbacks: [@Sendable (Value) -> Void] = []
    
    private var updateTask: Task<(), Never>?
    
    // MARK: - Life cycle
    
    public init(
        isValid: @escaping @Sendable (Value) -> Bool = { _ in true },
        getUpdatedValue: @escaping @Sendable () async -> Value
    ) {
        self.isValid = isValid
        self.getUpdatedValue = getUpdatedValue
    }
    
    deinit {
        callbacks = [] // release to avoid retail cycles
        updateTask?.cancel() // cancel
    }
    
    // MARK: - Public API
    
    public var value: Value {
        get async {
            await withUnsafeContinuation { cont in
                append(callback: { [cont] value in
                    cont.resume(returning: value)
                })
            }
        }
    }
    
    // MARK: - Private methods
    
    private func append(callback: @escaping @Sendable (Value) -> Void) {
        if let value = latestValue, isValid(value) {
            return callback(value)
        } else {
            latestValue = nil // clear out invalid value
            callbacks.append(callback) // enqueue callback
            guard updateTask == nil else { return } // task is already running, will be called back from other callback
            updateTask = Task {
                latestValue =  await getUpdatedValue()
                updateTask = nil
            }
        }
    }
}
