import Combine
import Foundation

/// Fork of `SerialUpdatingValue` using Combine instead of Swift Concurrency
public final class SerialUpdatingValueCombine<Value> {
    
    // MARK: - Properties
    
    private let isValid: (Value) -> Bool
    private let getUpdatedValue: () -> AnyPublisher<Value, Error>

    private var latestValue = CurrentValueSubject<Result<Value, Error>?, Never>(nil)
    private var cancellable: AnyCancellable?
    private let dispatchQueue = DispatchQueue(label: "SerialUpdatingValueCombine")
    
    // MARK: - Life cycle
    
    /// - Parameters:
    ///   - isValid: Run against the locally stored `latestValue`, if `false` then value will be updated.
    ///   - getUpdatedValue: Long-running task to get updated value. Will be called lazily, initially, and if stored `latestValue` is no longer valid
    public init<ValuePublisher: Publisher>(
        isValid: @escaping (Value) -> Bool = { _ in true },
        getUpdatedValue: @escaping () -> ValuePublisher
    ) where ValuePublisher.Output == Value {
        self.isValid = isValid
        self.getUpdatedValue = {
            getUpdatedValue()
                .mapError { $0 as Error }
                .eraseToAnyPublisher()
        }
    }
    
    deinit {
        dispatchQueue.async { [cancellable, latestValue] in
            cancellable?.cancel()
            latestValue.value = .failure(SerialUpdatingValueError.classDeallocated) /// flush out any other subscriptions with an error
        }
    }
    
    // MARK: - Public API
    
    /// Will get up-to-date value
    public var value: AnyPublisher<Result<Value, Error>, Never> {
        let returningPublisher = latestValue
            .compactMap { $0 }
            .filter { [isValid] result in
                switch result {
                case .success(let value):
                    return isValid(value)
                case .failure:
                    return true
                }
            }
            .first()
            .eraseToAnyPublisher()
        
        /// Refresh value if needed
        dispatchQueue.async { [weak self] in
            self?.updateValueIfNeeded()
        }
        
        return returningPublisher
    }
    
    // MARK: - Private methods

    /// Must be called from private serial thread
    private func updateValueIfNeeded() {
        /// if there is already an update in-flight, then no-op here
        guard cancellable == nil else { return }

        /// Is there a valid value?
        if case .success(let value) = self.latestValue.value,
           self.isValid(value) {
            return
        }
        
        /// There is no valid value, so must get a new value
        latestValue.value = nil /// clear out invalid value
        
        cancellable = getUpdatedValue()
            .map(Result<Value, Error>.success)
            .catch { Just(.failure($0)) }
            .receive(on: dispatchQueue)
            .sink { [weak self] (result: Result<Value, Error>) in
                self?.latestValue.value = result
                self?.cancellable = nil
            }
    }
}

// MARK: -

private enum SerialUpdatingValueError: Error {
    case classDeallocated
}
