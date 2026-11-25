# Contributing to RuleBox

Bug reports, rule presets, condition/action additions, and UI polish PRs are welcome.

## Repository Layout

- `Sources/RuleBoxCore/` — Rule models, token expander, `FileInspector` (`PDFKit` + `URLResourceValues`), `RuleEvaluator` (dry-run engine), `RuleExecutor` (atomic actions + 1-click Undo), `FolderWatcher` (`O_EVTONLY` kernel dispatch source), and `RuleBoxStore`.
- `Sources/RuleBox/` — Native SwiftUI + AppKit 3-pane macOS desktop app and menu bar companion (`NSStatusItem`).
- `Tests/RuleBoxCoreTests/` — XCTest suite covering matching, PDF content inspection, conflict policies, ZIP archiving, 1-click Undo, and live kernel folder watching.
- `benchmarks/` — Reproducible Swift release benchmarks (`./benchmarks/run_benchmarks.sh`).

## Running Tests & Building Locally

```bash
swift build
swift test
./scripts/build_app.sh release
codesign --verify --strict --verbose=2 "build/RuleBox.app"
```

## Pull Request Checklist

- Keep commits focused and run `swift test` before opening a PR.
- Add unit tests in `Tests/RuleBoxCoreTests/` for any new condition, action, or undo behavior.
- Never silently mutate files during dry-run preview paths (`RuleEvaluator`).
