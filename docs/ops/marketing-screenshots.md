# Marketing Screenshots

Use this runbook for OpenScribe screenshots intended for marketing assets, release notes, or social previews.

## Goal

Capture screenshots from the currently running app state without launching UI smoke mode and without starting a new recording session.

## Prerequisites

- OpenScribe is already running.
- The target popover tab is visible on screen.
- Terminal has macOS permissions:
  - Accessibility
  - Screen Recording

## Capture flow

1. Open the target popover state manually.
2. Capture the live popover window by window id.

```bash
stamp="$(date +%Y%m%d-%H%M%S)"
out="artifacts/live-screen-capture/manual-popover-$stamp"
mkdir -p "$out"

swift - <<'SWIFT' > "$out/window-id.txt"
import Foundation
import CoreGraphics

let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

func score(_ w: [String: Any]) -> Int {
    guard let owner = w[kCGWindowOwnerName as String] as? String, owner == "OpenScribe" else { return -1 }
    let name = (w[kCGWindowName as String] as? String) ?? ""
    guard let bounds = w[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Double,
          let height = bounds["Height"] as? Double else { return -1 }

    var s = 0
    if name.isEmpty || name == "OpenScribe" { s += 2 }
    if abs(width - 540) < 24 && abs(height - 620) < 40 { s += 5 }
    if abs(width - 620) < 24 && abs(height - 700) < 40 { s += 4 }
    if height > 500 && height < 760 { s += 1 }
    return s
}

let candidates = list.compactMap { w -> (Int, UInt32)? in
    let s = score(w)
    guard s >= 0, let n = w[kCGWindowNumber as String] as? UInt32 else { return nil }
    return (s, n)
}.sorted { $0.0 > $1.0 }

if let best = candidates.first {
    print(best.1)
} else {
    fputs("NO_POPOVER\\n", stderr)
    exit(2)
}
SWIFT

id="$(cat "$out/window-id.txt")"
screencapture -x -l "$id" "$out/popover.png"
```

## Optional opaque export

If background transparency is undesirable for marketing composition, flatten to an opaque background.
Use the same `$out` directory from the capture flow.

```bash
src="$out/popover.png"
opaque="$out/popover-opaque.png"

SRC="$src" OPAQUE="$opaque" swift - <<'SWIFT'
import AppKit
import Foundation

let src = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SRC"]!)
let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OPAQUE"]!)

guard let image = NSImage(contentsOf: src) else { exit(1) }
let size = image.size
let output = NSImage(size: size)
output.lockFocus()
NSColor(calibratedWhite: 0.08, alpha: 1.0).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1.0)
output.unlockFocus()

guard let tiff = output.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: out)
SWIFT
```

## Verification checklist

- Screenshot shows the intended tab and content state.
- No desktop wallpaper shows through popover interior.
- Copy is readable at 100 percent zoom.
- File path is reported in PR notes or release notes draft.
