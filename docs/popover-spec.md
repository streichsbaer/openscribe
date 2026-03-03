# OpenScribe Popover Spec

## Purpose

Define one clear contract for popover behavior, sizing, tab switching, and smoke verification.

## Scope

- Menubar popover layout and sizing.
- Live, History, and Stats tab interaction.
- Rules hotkey behavior from popover context.
- Click and hotkey parity requirements.
- Popover-related smoke expectations.

## Source of Truth

- App state and intent live in `AppShell`.
- Popover window sizing is applied by `StatusBarController`.
- Popover content layout is rendered by `PopoverView`.

No other component should define conflicting sizing rules.

## Tab Behavior

### Selection Path

All popover tab switches use one path:

- `AppShell.selectPopoverTab(_:, revealPopover:)`

This applies to:

- Segmented control clicks.
- Global hotkeys (`Ctrl+Option+L`, `Ctrl+Option+H`, `Ctrl+Option+S`).
- Programmatic transitions (for example opening a history row into Live).

### Rules Hotkey Behavior

- `Ctrl+Option+R` opens Settings on the Rules tab.
- This command does not switch the popover tab. It opens the settings window.

### History Refresh

- Selecting History refreshes history sessions while preserving currently loaded count.

### History Pagination

- Initial load is fixed to 10 sessions.
- Load more options are fixed: `next 10`, `next 25`, `next 50`, `whole`.

## Sizing Policy

Popover size is deterministic by state.

### Requested Sizes

- Live compact: `540 x 700`
- Live expanded: `620 x 980`
- History: `620 x 700`
- Stats: `620 x 700`

### Screen-Aware Height Cap

Final popover height is capped to the active display visible frame:

- Margin cap: `visibleFrame.height - 64`
- Fraction cap: `visibleFrame.height * 0.88`
- Final cap: `max(420, min(marginCap, fractionCap))`

Final height is:

- `min(requestedHeight, screenCap)`

Popover width is not scaled by screen cap.

## Layout Behavior

### Live

- Live content is rendered inside a vertical `ScrollView`.
- Transcript panel heights are fixed per mode to avoid jumpy empty-to-filled reflow:
  - Compact: `110`
  - Expanded: `220`

### History

- History fills available vertical space in the card.
- The session list area grows to consume remaining height.
- No large bottom slack should remain above footer/status row.

## Interaction Parity Requirements

History view geometry must be equivalent when reached by:

1. Click path (segmented control).
2. Hotkey path.

Parity is measured by smoke metrics and screenshots.

## Smoke Requirements

The UI smoke run must include and validate:

- `openscribe-window-click-history.png`
- `openscribe-window-click-history-full.png`
- `openscribe-window-click-stats.png`
- `openscribe-window-hotkey-history.png`
- `openscribe-window-hotkey-history-full.png`
- `openscribe-window-hotkey-stats.png`
- `openscribe-window-hotkey-live.png`
- `openscribe-window-live-expanded-content.png`

Status checks must pass:

- `tabClickDispatch`
- `hotkeyDispatch`
- `historyLayoutParityDirect`
- `historyLayoutParity`
- `historyVerticalFill`
- `liveExpandedContentCapture`

## Non-Goals

- Dynamic popover height based on transcript text length.
- Separate sizing logic per trigger path.
- Hidden fallback tab-switch paths.
