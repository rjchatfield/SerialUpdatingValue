/// Thread -safe
public actor SerialUpdatingValue<Value> where Value: Sendable {
    
    // MARK: - Properties
    
    private let isValid: @Sendable (Value) -> Bool
    private let getUpdatedValue: @Sendable () async -> Value
    
    private var latestValue: Value?
    private var callbacks: [(Value) -> Void] = []
    private var isUpdating = false
    private var updateTask: Task<(), Never>? { willSet { updateTask?.cancel() } }
    
    // MARK: - Life cycle
    
    public init(
        isValid: @escaping @Sendable (Value) -> Bool = { _ in true },
        getUpdatedValue: @escaping @Sendable () async -> Value
    ) {
        self.isValid = isValid
        self.getUpdatedValue = getUpdatedValue
    }
    
    deinit {
        callbacks = []
        updateTask = nil
    }
    
    // MARK: - Public API
    
    public func getValue() async -> Value {
        await withCheckedContinuation({ cont in
            append(callback: cont.resume(returning:))
        })
    }
    
    // MARK: - Private methods
    
    private func append(callback: @escaping (Value) -> Void) {
        if let value = latestValue, isValid(value) {
            return callback(value)
        } else {
            callbacks.append(callback)
            guard !isUpdating else { return }
            latestValue = nil
            isUpdating = true
            updateTask = Task {
                let updatedValue = await getUpdatedValue()
                latestValue = updatedValue
                isUpdating = false
                for callback in callbacks {
                    callback(updatedValue)
                }
                callbacks = []
            }
        }
    }
}
