# Changelog

All notable changes to RuleBox are documented in this file.

## [1.0.0] - 2026-11-25

### Added
- Native macOS 14+ 3-pane SwiftUI + AppKit workspace (`Folders`, `Rule Cards`, `Rule Editor + Live Dry-Run Preview`) plus `NSStatusItem` menu bar companion.
- 8 condition fields (`Name`, `Extension`, `Kind`, `Size (MB)`, `Age (Days)`, `Contents (Text/PDF)` via `PDFKit`, `Finder Tag`, `Is Hidden`) with `All / Any / None` matching and regex support.
- 9 actions (`Move to Folder`, `Copy to Folder`, `Rename`, `Sort into Subfolder`, `Add Finder Tag`, `Remove Finder Tags`, `Archive (ZIP)` via `ditto`, `Move to Trash` via `FileManager.trashItem`, `Run Shell Script` with 10s timeout) with dynamic filename tokens (`[Name]`, `[Ext]`, `[Year]`, `[Month]`, `[Day]`, `[Date]`, `[Kind]`, `[Parent]`, `[Counter]`).
- Non-mutating live `Before -> After` dry-run simulator and persistent Activity & 1-Click Undo journal.
- Kernel-level `DispatchSourceFileSystemObject` (`O_EVTONLY`) debounced folder watcher.
- Safe first-launch demo sandbox (`DemoWorkspace`), curated Rule Presets gallery, 3 tested `.rulebox` examples, 10 XCTests, and reproducible Apple M2 benchmarks.
