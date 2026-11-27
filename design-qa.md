# Design QA

## Reference and test state

- Reference: `/var/folders/yd/3j2r0kq11vxcnvv_91n4pchc0000gn/T/codex-clipboard-81a97140-a77e-44db-873f-c1abbb13ca92.png` (1688 × 1508 px).
- Main implementation: `/tmp/mouse-keyboard-profile-flow.png` (2852 × 1812 px at 2×).
- Save flow: `/tmp/mouse-keyboard-save-dialog.png`.
- Restore flow: `/tmp/mouse-keyboard-restore-dialog.png`.
- Mode taxonomy: `/tmp/mouse-keyboard-profile-modes-full.png`, showing separate workspace and window-mode sections.
- Desktop comparison: `/tmp/mouse-keyboard-desktop-canvas-comparison.png`, with the supplied reference and proportional desktop implementation side by side.
- State: light appearance, two connected displays, live window data, selected-only desktop preview, and one existing saved profile.

## Visual findings

- Each simulated desktop preserves the corresponding display aspect ratio. Selected windows use normalized desktop coordinates and sizes; overlapping windows remain overlapped.
- Core Graphics front-to-back ordering is retained when available, with back windows drawn first.
- The window-selection tray is visually separate below the desktop and contains every window in the visible Space. Only selected cards appear in the simulation.
- Saved layouts are now listed in the sidebar. Restore is attached to the selected profile rather than the global toolbar.
- Multi-window workspace modes expose a primary one-click restore action using all saved display destinations. Single-window modes expose an apply flow that asks for a target window, display, and Space.
- The save sheet clearly separates new and update modes, supplies an editable generated name, and makes overwrite behavior explicit.
- The restore sheet presents each saved window with independent display and Space pickers. Disconnected destinations receive a blocking red warning.
- Native typography, symbols, control styles, spacing, corners, and accent colors remain consistent with the existing macOS design.

No remaining P0, P1, or P2 visual defects were found. The desktop intentionally uses application icons rather than captured window contents to avoid adding Screen Recording permission.

## Interaction and platform checks

- Window selection updates both the simulated desktop and inspector.
- New/update save modes, editable name, overwrite profile picker, and cancel actions were exercised through Accessibility.
- Profile selection opens the per-window restore configuration with saved destinations preselected.
- Existing profiles migrate without data loss: multi-window profiles become workspace modes, while legacy one-window profiles become reusable window modes.
- Cross-display restoration now applies size before position and retries a constrained position after the window settles.
- Unavailable displays no longer fall back silently to the main display.
- Debug build and localization validation pass. The native app remains open for inspection.

## Comparison history

1. The original flat window grid was replaced with a proportional desktop canvas.
2. The selection controls were moved into a dedicated tray below the simulation.
3. Save and restore were refactored into explicit profile-centric dialogs.
4. Cross-display geometry ordering was corrected after a large-window-to-small-display reproduction report.

final result: passed
