import AppKit
import SwiftUI

/// Colors for the popover. Blue always means "on this Mac" and orange always means "the cloud";
/// ink carries selection, bars, and primary actions; red is only for recording.
enum PopoverPalette {
    static let local = dynamic(light: NSColor(srgbRed: 0, green: 0.345, blue: 0.69, alpha: 1),
                               dark: NSColor(srgbRed: 0.42, green: 0.71, blue: 1, alpha: 1))
    static let localTint = dynamic(light: NSColor(srgbRed: 0, green: 0.4, blue: 0.8, alpha: 0.1),
                                   dark: NSColor(srgbRed: 0.42, green: 0.71, blue: 1, alpha: 0.16))
    static let cloud = dynamic(light: NSColor(srgbRed: 0.604, green: 0.29, blue: 0, alpha: 1),
                               dark: NSColor(srgbRed: 0.95, green: 0.65, blue: 0.35, alpha: 1))
    static let cloudTint = dynamic(light: NSColor(srgbRed: 0.84, green: 0.43, blue: 0, alpha: 0.12),
                                   dark: NSColor(srgbRed: 0.95, green: 0.65, blue: 0.35, alpha: 0.16))
    static let cloudFill = dynamic(light: NSColor(srgbRed: 0.878, green: 0.541, blue: 0.173, alpha: 1),
                                   dark: NSColor(srgbRed: 0.878, green: 0.541, blue: 0.173, alpha: 1))
    static let record = Color(nsColor: .systemRed)
    static let muted = dynamic(light: NSColor(srgbRed: 0.373, green: 0.376, blue: 0.4, alpha: 1),
                               dark: NSColor(srgbRed: 0.66, green: 0.66, blue: 0.69, alpha: 1))
    static let groundTop = dynamic(light: NSColor(srgbRed: 0.965, green: 0.969, blue: 0.976, alpha: 1),
                                   dark: NSColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 1))
    static let groundBottom = dynamic(light: NSColor(srgbRed: 0.925, green: 0.933, blue: 0.949, alpha: 1),
                                      dark: NSColor(srgbRed: 0.1, green: 0.1, blue: 0.11, alpha: 1))
    static let card = dynamic(light: NSColor(white: 1, alpha: 0.82), dark: NSColor(white: 1, alpha: 0.06))
    static let cardStroke = dynamic(light: NSColor(white: 1, alpha: 0.95), dark: NSColor(white: 1, alpha: 0.08))
    static let cardShadow = dynamic(light: NSColor(srgbRed: 0.08, green: 0.09, blue: 0.16, alpha: 0.08),
                                    dark: NSColor(white: 0, alpha: 0))
    static let control = dynamic(light: NSColor.white, dark: NSColor(white: 1, alpha: 0.1))
    static let controlStroke = dynamic(light: NSColor(white: 0, alpha: 0.1), dark: NSColor(white: 1, alpha: 0.12))
    static let subtle = dynamic(light: NSColor(white: 0, alpha: 0.05), dark: NSColor(white: 1, alpha: 0.08))
    static let selection = dynamic(light: NSColor(white: 0, alpha: 0.085), dark: NSColor(white: 1, alpha: 0.12))
    static let hairline = dynamic(light: NSColor(white: 0, alpha: 0.07), dark: NSColor(white: 1, alpha: 0.08))

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

struct PopoverCard: ViewModifier {
    var radius: CGFloat = 22
    var elevated = true

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(PopoverPalette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(PopoverPalette.cardStroke, lineWidth: 1)
            )
            .shadow(color: PopoverPalette.cardShadow, radius: elevated ? 15 : 9, x: 0, y: elevated ? 10 : 6)
    }
}

extension View {
    func popoverCard(radius: CGFloat = 22, elevated: Bool = true) -> some View {
        modifier(PopoverCard(radius: radius, elevated: elevated))
    }

    /// A square outlined frame around a borderless menu, matching the icon buttons.
    func popoverMenuButton() -> some View {
        frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PopoverPalette.control)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(PopoverPalette.controlStroke, lineWidth: 1)
            )
    }
}

/// Primary actions are ink on the ground color; secondary actions are outlined.
struct PopoverButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    var kind: Kind = .secondary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .foregroundStyle(kind == .primary ? Color(nsColor: .windowBackgroundColor) : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(kind == .primary ? Color.primary : PopoverPalette.control)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(kind == .primary ? Color.clear : PopoverPalette.controlStroke, lineWidth: 1)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .contentShape(Rectangle())
    }
}

/// A square icon button with an outline, used for play, more, and similar actions.
struct PopoverIconButtonStyle: ButtonStyle {
    var circular = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: circular ? 15 : 10, style: .continuous)
                    .fill(circular ? PopoverPalette.subtle : PopoverPalette.control)
            )
            .overlay(
                RoundedRectangle(cornerRadius: circular ? 15 : 10, style: .continuous)
                    .strokeBorder(circular ? Color.clear : PopoverPalette.controlStroke, lineWidth: 1)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(Rectangle())
    }
}

struct KeycapLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(PopoverPalette.control)
                    .shadow(color: .black.opacity(0.08), radius: 0, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(PopoverPalette.controlStroke, lineWidth: 1)
            )
    }
}

/// The app mark on an ink tile, as in the popover header.
struct OpenScribeMarkTile: View {
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(Color.primary)
            .frame(width: size, height: size)
            .overlay(
                HStack(spacing: size * 0.1) {
                    bar(height: 0.24)
                    bar(height: 0.52)
                    bar(height: 0.24)
                }
            )
            .accessibilityHidden(true)
    }

    private func bar(height: CGFloat) -> some View {
        Capsule()
            .fill(Color(nsColor: .windowBackgroundColor))
            .frame(width: size * 0.1, height: size * height)
    }
}

/// Words a user reads in the popover for each provider.
enum ProviderNames {
    static func display(_ providerID: String) -> String {
        switch providerID {
        case "parakeet":
            return "Parakeet"
        case "whispercpp":
            return "Whisper"
        case "openai_whisper", "openai_polish":
            return "OpenAI"
        case "openai_realtime_transcription":
            return "OpenAI Realtime"
        case "groq_whisper", "groq_polish":
            return "Groq"
        case "openrouter_transcribe", "openrouter_polish":
            return "OpenRouter"
        case "gemini_transcribe", "gemini_polish":
            return "Gemini"
        case "cerebras_polish":
            return "Cerebras"
        default:
            return providerID
        }
    }

    /// A model id without its vendor prefix, for example "gpt-oss-120b" for "openai/gpt-oss-120b".
    static func shortModel(_ model: String) -> String {
        model.split(separator: "/").last.map(String.init) ?? model
    }
}

enum PopoverFormat {
    static func clock(seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func processing(ms: Int) -> String {
        let seconds = Double(ms) / 1000
        return seconds < 10 ? String(format: "%.1f s", seconds) : String(format: "%.0f s", seconds)
    }

    static func number(_ value: Int) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    static func speaking(seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes >= 60 {
            return "\(minutes / 60) h \(minutes % 60) min"
        }
        return minutes < 1 ? "\(Int(seconds.rounded())) s" : "\(minutes) min"
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
