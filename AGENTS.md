# Repository Guidelines

## Project Structure & Module Organization

This repository contains one macOS SwiftUI application. Production code lives in `mouse_keyboard/` and follows a feature-first structure. `App/` contains the application entry point and delegate. Shared platform services belong in `Core/`, grouped by responsibility such as `Display/`, `Permissions/`, and `Settings/`. User-facing capabilities live in `Features/`; keep keyboard control, status bar, app switcher, HUD, and window layout code in their respective feature directories. The window layout feature further separates `Models/`, `Services/`, `ViewModels/`, `Views/`, and `Controllers/`.

Localized strings are under `mouse_keyboard/en.lproj/` and `mouse_keyboard/zh-Hans.lproj/`; add matching keys to both languages. Images, colors, and icons belong in `mouse_keyboard/Assets.xcassets/`. The Xcode project is `mouse_keyboard.xcodeproj`. `README.md` documents usage and installation, and `DESIGN.md` describes the visual direction.

## Build, Test, and Development Commands

- `open mouse_keyboard.xcodeproj` opens the project for normal development and signing setup.
- `xcodebuild -project mouse_keyboard.xcodeproj -scheme mouse_keyboard -configuration Debug build CODE_SIGNING_ALLOWED=NO` performs a command-line debug build without signing.
- `xcodebuild -project mouse_keyboard.xcodeproj -scheme mouse_keyboard -configuration Release build CODE_SIGNING_ALLOWED=NO` checks the optimized build.

Command-line builds require a full Xcode installation selected with `xcode-select`, not Command Line Tools alone. Run the app from Xcode with `Cmd+R`; global input behavior requires Accessibility permission and may also require Input Monitoring.

## Coding Style & Naming Conventions

Use four-space indentation and standard Swift API naming: `UpperCamelCase` for types, `lowerCamelCase` for methods and properties, and descriptive enum cases. Prefer small `final` service/controller classes, narrow access control, early `guard` exits, and `[weak self]` in escaping UI callbacks. Keep user-facing text in localization files. No formatter or linter is configured, so match the surrounding Xcode formatting and organize imports before submitting.

## Testing Guidelines

There is currently no test target. For logic changes, add an XCTest target and name files `<TypeName>Tests.swift`; name methods `test_<behavior>_<expectedResult>()`. Prioritize deterministic tests for key routing, settings persistence, and movement calculations. Also manually verify mode toggling, mouse movement, clicks, scrolling, multi-display shortcuts, and permission-denied behavior.

## Commit & Pull Request Guidelines

Recent commits use short, imperative subjects, sometimes with Conventional Commit prefixes such as `feat:`, `fix:`, `refactor:`, or `docs:`. Keep each commit focused. Pull requests should explain behavior changes, list build/manual-test results, link relevant issues, and include screenshots or recordings for UI/HUD changes. Highlight new permissions, shortcuts, or localization updates explicitly.
