import Carbon
import Foundation

enum HotkeyDisplay {
    static func string(for setting: HotkeySetting) -> String {
        let normalized = setting.normalizedForCarbonHotkey()
        var parts: [String] = []

        if (normalized.modifiers & HotkeySetting.carbonFunctionMask) != 0 {
            parts.append("Fn")
        }
        if (normalized.modifiers & UInt32(controlKey)) != 0 {
            parts.append("Ctrl")
        }
        if (normalized.modifiers & UInt32(optionKey)) != 0 {
            parts.append("Option")
        }
        if (normalized.modifiers & UInt32(cmdKey)) != 0 {
            parts.append("Cmd")
        }
        if (normalized.modifiers & UInt32(shiftKey)) != 0 {
            parts.append("Shift")
        }

        parts.append(keyName(for: normalized.keyCode))
        return parts.joined(separator: "+")
    }

    static func keyName(for keyCode: UInt32) -> String {
        keyNames[keyCode] ?? "Key \(keyCode)"
    }

    private static let keyNames: [UInt32: String] = [
        0: "A",
        1: "S",
        2: "D",
        3: "F",
        4: "H",
        5: "G",
        6: "Z",
        7: "X",
        8: "C",
        9: "V",
        11: "B",
        12: "Q",
        13: "W",
        14: "E",
        15: "R",
        16: "Y",
        17: "T",
        18: "1",
        19: "2",
        20: "3",
        21: "4",
        22: "6",
        23: "5",
        24: "=",
        25: "9",
        26: "7",
        27: "-",
        28: "8",
        29: "0",
        30: "]",
        31: "O",
        32: "U",
        33: "[",
        34: "I",
        35: "P",
        36: "Return",
        37: "L",
        38: "J",
        39: "'",
        40: "K",
        41: ";",
        42: "\\",
        43: ",",
        44: "/",
        45: "N",
        46: "M",
        47: ".",
        48: "Tab",
        49: "Space",
        50: "`",
        51: "Delete",
        53: "Esc",
        122: "F1",
        120: "F2",
        99: "F3",
        118: "F4",
        96: "F5",
        97: "F6",
        98: "F7",
        100: "F8",
        101: "F9",
        109: "F10",
        103: "F11",
        111: "F12",
        123: "Left",
        124: "Right",
        125: "Down",
        126: "Up"
    ]
}
