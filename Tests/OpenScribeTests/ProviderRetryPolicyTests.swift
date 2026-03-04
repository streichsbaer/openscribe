import Foundation
import XCTest
@testable import OpenScribe

final class ProviderRetryPolicyTests: XCTestCase {
    func testTranscriptionSuccessAfterRetry() async throws {
        var attemptCount = 0
        var sleepCalls: [UInt64] = []

        let result: String = try await ProviderRetryPolicy.run(
            sleep: { duration in
                sleepCalls.append(duration)
            },
            operation: {
                attemptCount += 1
                if attemptCount == 1 {
                    throw URLError(.timedOut)
                }
                return "ok"
            }
        )

        XCTAssertEqual(result, "ok")
        XCTAssertEqual(attemptCount, 2)
        XCTAssertTrue(sleepCalls.isEmpty)
    }

    func testTranscriptionRetryExhaustion() async {
        var attemptCount = 0
        var sleepCalls: [UInt64] = []

        do {
            let _: String = try await ProviderRetryPolicy.run(
                sleep: { duration in
                    sleepCalls.append(duration)
                },
                operation: {
                    attemptCount += 1
                    throw URLError(.networkConnectionLost)
                }
            )
            XCTFail("Expected transcription-style retry exhaustion.")
        } catch {
            let urlError = error as? URLError
            XCTAssertEqual(urlError?.code, .networkConnectionLost)
        }

        XCTAssertEqual(attemptCount, 3)
        XCTAssertEqual(sleepCalls, [ProviderRetryPolicy.finalRetryDelayNanoseconds])
    }

    func testPolishSuccessAfterRetry() async throws {
        var attemptCount = 0
        var sleepCalls: [UInt64] = []

        let result: String = try await ProviderRetryPolicy.run(
            sleep: { duration in
                sleepCalls.append(duration)
            },
            operation: {
                attemptCount += 1
                if attemptCount == 1 {
                    throw OpenAICompatibleError.http(503, "{\"error\":{\"message\":\"temporary\"}}")
                }
                return "polished"
            }
        )

        XCTAssertEqual(result, "polished")
        XCTAssertEqual(attemptCount, 2)
        XCTAssertTrue(sleepCalls.isEmpty)
    }

    func testPolishRetryExhaustion() async {
        var attemptCount = 0
        var sleepCalls: [UInt64] = []

        do {
            let _: String = try await ProviderRetryPolicy.run(
                sleep: { duration in
                    sleepCalls.append(duration)
                },
                operation: {
                    attemptCount += 1
                    throw OpenAICompatibleError.http(503, "{\"error\":{\"message\":\"retry\"}}")
                }
            )
            XCTFail("Expected polish-style retry exhaustion.")
        } catch {
            guard case OpenAICompatibleError.http(let status, _) = error else {
                XCTFail("Expected OpenAICompatibleError.http.")
                return
            }
            XCTAssertEqual(status, 503)
        }

        XCTAssertEqual(attemptCount, 3)
        XCTAssertEqual(sleepCalls, [ProviderRetryPolicy.finalRetryDelayNanoseconds])
    }

    func testMissingAPIKeyDoesNotRetry() async {
        var attemptCount = 0
        var sleepCalls: [UInt64] = []

        do {
            let _: String = try await ProviderRetryPolicy.run(
                sleep: { duration in
                    sleepCalls.append(duration)
                },
                operation: {
                    attemptCount += 1
                    throw ProviderError.missingAPIKey("OpenAI")
                }
            )
            XCTFail("Expected immediate failure for missing API key.")
        } catch {
            guard case ProviderError.missingAPIKey = error else {
                XCTFail("Expected ProviderError.missingAPIKey.")
                return
            }
        }

        XCTAssertEqual(attemptCount, 1)
        XCTAssertTrue(sleepCalls.isEmpty)
    }
}
