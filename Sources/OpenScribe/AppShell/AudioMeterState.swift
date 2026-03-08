import Combine
import Foundation

@MainActor
final class AudioMeterState: ObservableObject {
    @Published var level: Float = 0
}
