# Zaitan

A minimal tiling window manager for macOS. Assign any app's window to a pane, split panes, and remove them — windows snap to fill the available space automatically.

## Hotkeys

| Hotkey | Action |
|---|---|
| `Cmd+Shift+Return` | Assign frontmost window to the first empty pane |
| `Cmd+Shift+Right` | Split the focused window's pane left/right |
| `Cmd+Shift+Down` | Split the focused window's pane top/bottom |
| `Cmd+Shift+Delete` | Remove focused window from layout |

When a pane is removed its sibling automatically expands to fill the space.

## Setup

**Requirements:** macOS, CMake, Xcode command line tools.

```bash
cmake -B build
cmake --build build
open build/Zaitan.app
```

On first launch, macOS will prompt for **Accessibility permission** — this is required to move and resize other apps' windows. Grant it in System Settings → Privacy & Security → Accessibility.

> Note: rebuilding the app resets the Accessibility permission since the binary signature changes. Re-enable it after each build.

## How it works

The layout is a binary tree. Each leaf node holds a pane (a screen region + the window assigned to it). Splitting a leaf turns it into an internal node with two child panes. Removing a pane promotes its sibling to fill the parent's space, recursively redistributing frames down the tree.

The layout engine (`src/`) is pure C++ with no platform dependencies. The platform layer (`platform/`, `app/`, `input/`) handles Accessibility API calls, hotkey registration, and wiring everything together.
