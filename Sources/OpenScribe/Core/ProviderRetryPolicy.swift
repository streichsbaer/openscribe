import Foundation

enum ProviderRetryPolicy {
    static let maxAttempts = 3
    static let finalRetryDelayNanoseconds: UInt64 = 1_000_000_000

    @MainActor
    static func run<T>(
        sleep: (UInt64) async throws -> Void = { duration in
            try await Task.sleep(nanoseconds: duration)
        },
        operation: () async throws -> T
    ) async throws -> T {
        var attempt = 1

        while true {
            do {
                return try await operation()
            } catch {
                if !isRetryableProviderError(error) || attempt >= maxAttempts {
                    throw error
                }

                // Retry schedule: immediate second attempt, then 1 second delay before final attempt.
                if attempt == maxAttempts - 1 {
                    try await sleep(finalRetryDelayNanoseconds)
                }

                attempt += 1
            }
        }
    }

    static func isRetryableProviderError(_ error: Error) -> Bool {
        if error is CancellationError {
            return false
        }

        if let providerError = error as? ProviderError {
            switch providerError {
            case .missingAPIKey, .missingModel, .unsupported:
                return false
            case .invalidResponse, .processFailed:
                return true
            }
        }

        if let openAICompatibleError = error as? OpenAICompatibleError {
            switch openAICompatibleError {
            case .http(let status, _):
                return status == 408 || status == 429 || (500...599).contains(status)
            }
        }

        if let urlError = error as? URLError {
            return urlError.code != .cancelled
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return nsError.code != URLError.cancelled.rawValue
        }

        return false
    }

    static func isProviderRelatedError(_ error: Error) -> Bool {
        if error is ProviderError {
            return true
        }
        if error is OpenAICompatibleError {
            return true
        }
        if error is URLError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
    }
}
