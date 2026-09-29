# Popover Contract

## Scope

- Popover tab behavior for Live, History, and Stats.
- Sizing policy and parity guarantees.
- Smoke verification requirements.

## Tab switch path

All tab changes route through one state entry point.

- Segmented control clicks.
- Global hotkeys.
- Programmatic transitions.

## Sizing policy

Every tab uses one size, `540 x 680`, so switching tabs never resizes the popover.
Final height is capped by active display visible frame.

## Verification

Smoke runs validate click and hotkey parity with specific screenshot artifacts.

## Deep details

- Repository spec: [`docs/popover-spec.md`](https://github.com/streichsbaer/openscribe/blob/main/docs/popover-spec.md)
