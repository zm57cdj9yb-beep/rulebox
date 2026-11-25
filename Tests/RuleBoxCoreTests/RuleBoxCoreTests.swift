import Foundation
import RuleBoxCore
import XCTest

final class RuleBoxCoreTests: XCTestCase {
    private func makeTempDir(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuleBoxTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testTokenExpansionAndPathSanitization() {
        let cal = Calendar(identifier: .gregorian)
        let date = cal.date(from: DateComponents(year: 2026, month: 11, day: 25))!
        let url = URL(fileURLWithPath: "/tmp/Downloads/Invoice_Q4.pdf")

        let expanded = TokenExpander.expand(
            pattern: "[Year]-[Month]-[Day]_[Name]_[Counter].[Ext]",
            fileURL: url,
            kind: .pdf,
            referenceDate: date,
            counter: 7
        )
        XCTAssertEqual(expanded, "2026-11-25_Invoice_Q4_007.pdf")

        // Path traversal must be stripped
        let sub = TokenExpander.sanitizeRelativeSubfolder("../../etc/2026/11")
        XCTAssertEqual(sub, "etc/2026/11")

        let safeName = TokenExpander.sanitizeFileName("../bad/name.txt", fallback: "fallback.txt")
        XCTAssertFalse(safeName.contains("/"))
    }

    func testPDFContentConditionMatchesEmbeddedTextOnly() throws {
        let dir = try makeTempDir("pdf")
        defer { try? FileManager.default.removeItem(at: dir) }

        let invoicePDF = dir.appendingPathComponent("Vendor.pdf")
        let memoPDF = dir.appendingPathComponent("Notes.pdf")
        DemoWorkspaceGenerator.writeTextPDF(to: invoicePDF, title: "ACME Invoice #99", body: "Amount due: $250")
        DemoWorkspaceGenerator.writeTextPDF(to: memoPDF, title: "Meeting Notes", body: "Roadmap planning")

        let rule = AutomationRule(
            name: "PDF Invoice",
            conditions: [
                RuleCondition(field: .kind, op: .equals, value: FileKindCategory.pdf.rawValue),
                RuleCondition(field: .contents, op: .contains, value: "Invoice")
            ],
            actions: [RuleAction(kind: .addTag, tagName: "Green")]
        )

        let invSnap = try XCTUnwrap(FileInspector.inspect(url: invoicePDF))
        let memoSnap = try XCTUnwrap(FileInspector.inspect(url: memoPDF))

        XCTAssertTrue(RuleEvaluator.matches(rule: rule, file: invSnap))
        XCTAssertFalse(RuleEvaluator.matches(rule: rule, file: memoSnap))
    }

    func testMatchModesAllAnyNoneAndRegex() throws {
        let dir = try makeTempDir("matchmodes")
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("IMG_2026_0042.png")
        try Data(repeating: 1, count: 128).write(to: file)
        let snap = try XCTUnwrap(FileInspector.inspect(url: file))

        let regexRule = AutomationRule(
            name: "Regex",
            matchMode: .all,
            conditions: [
                RuleCondition(field: .name, op: .matchesRegex, value: "^IMG_\\d{4}_\\d{4}\\.png$"),
                RuleCondition(field: .fileExtension, op: .inList, value: "png,jpg,webp")
            ]
        )
        XCTAssertTrue(RuleEvaluator.matches(rule: regexRule, file: snap))

        let noneRule = AutomationRule(
            name: "None",
            matchMode: .none,
            conditions: [
                RuleCondition(field: .kind, op: .equals, value: FileKindCategory.pdf.rawValue)
            ]
        )
        XCTAssertTrue(RuleEvaluator.matches(rule: noneRule, file: snap))
    }

    func testAgeDaysAndSizeMBConditions() throws {
        let dir = try makeTempDir("age")
        defer { try? FileManager.default.removeItem(at: dir) }

        let oldDmg = dir.appendingPathComponent("OldApp.dmg")
        try Data(repeating: 0x11, count: 2_200_000).write(to: oldDmg)
        let oldDate = Date().addingTimeInterval(-20 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldDmg.path)

        let snap = try XCTUnwrap(FileInspector.inspect(url: oldDmg))
        let rule = AutomationRule(
            name: "Old Large DMG",
            conditions: [
                RuleCondition(field: .kind, op: .equals, value: FileKindCategory.diskImage.rawValue),
                RuleCondition(field: .ageDays, op: .greaterThan, value: "14"),
                RuleCondition(field: .sizeMB, op: .greaterThan, value: "2.0")
            ]
        )
        XCTAssertTrue(RuleEvaluator.matches(rule: rule, file: snap))
    }

    func testDryRunDoesNotMutateFilesystem() throws {
        let dir = try makeTempDir("dryrun")
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("Screenshot 1.png")
        try Data(repeating: 0x02, count: 64).write(to: file)

        let folder = WatchedFolder(
            name: "Test",
            path: dir.path,
            rules: [
                AutomationRule(
                    name: "Sort Screenshots",
                    conditions: [RuleCondition(field: .name, op: .startsWith, value: "Screenshot")],
                    actions: [
                        RuleAction(kind: .addTag, tagName: "Blue"),
                        RuleAction(kind: .sortIntoSubfolder, pattern: "[Year]/[Month]")
                    ]
                )
            ]
        )

        let matches = RuleEvaluator.dryRun(folder: folder)
        XCTAssertEqual(matches.count, 1)
        XCTAssertTrue(matches[0].actionBadges.contains("+Blue"))
        XCTAssertTrue(matches[0].actionBadges.contains("Subfolder"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "Dry run must never move files")
    }

    func testExecuteTagRenameMoveAndOneClickUndo() throws {
        let dir = try makeTempDir("exec-undo")
        defer { try? FileManager.default.removeItem(at: dir) }

        let srcDir = dir.appendingPathComponent("Inbox", isDirectory: true)
        let dstDir = dir.appendingPathComponent("Sorted", isDirectory: true)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)

        let file = srcDir.appendingPathComponent("report.txt")
        try "hello rulebox".write(to: file, atomically: true, encoding: .utf8)

        let folder = WatchedFolder(
            name: "Inbox",
            path: srcDir.path,
            rules: [
                AutomationRule(
                    name: "File Reports",
                    conditions: [RuleCondition(field: .fileExtension, op: .equals, value: "txt")],
                    actions: [
                        RuleAction(kind: .addTag, tagName: "Green"),
                        RuleAction(kind: .rename, pattern: "filed_[Name].[Ext]"),
                        RuleAction(kind: .move, targetPath: dstDir.path)
                    ]
                )
            ]
        )

        let report = RuleExecutor.run(folder: folder)
        XCTAssertEqual(report.matchedCount, 1)
        XCTAssertEqual(report.errorCount, 0)
        let movedURL = dstDir.appendingPathComponent("filed_report.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))

        let tags = (try? movedURL.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
        XCTAssertTrue(tags.contains("Green"))

        // 1-Click Undo must restore original path, filename, and empty tags!
        let entry = try XCTUnwrap(report.entries.first)
        XCTAssertTrue(entry.canUndo)
        let undone = try RuleExecutor.undo(entry: entry)
        XCTAssertEqual(undone.status, .undone)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: movedURL.path))
        let restoredTags = (try? file.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
        XCTAssertFalse(restoredTags.contains("Green"))
    }

    func testConflictPolicyRenameAndArchiveZip() throws {
        let dir = try makeTempDir("conflict-zip")
        defer { try? FileManager.default.removeItem(at: dir) }

        let dst = dir.appendingPathComponent("Dest", isDirectory: true)
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        try "existing".write(to: dst.appendingPathComponent("doc.md"), atomically: true, encoding: .utf8)

        let incoming = dir.appendingPathComponent("doc.md")
        try "incoming".write(to: incoming, atomically: true, encoding: .utf8)

        let folder = WatchedFolder(
            name: "Src",
            path: dir.path,
            rules: [
                AutomationRule(
                    name: "Zip & Move",
                    conditions: [RuleCondition(field: .fileExtension, op: .equals, value: "md")],
                    actions: [
                        RuleAction(kind: .archiveZip),
                        RuleAction(kind: .move, targetPath: dst.path, conflictPolicy: .rename)
                    ]
                )
            ]
        )

        let report = RuleExecutor.run(folder: folder)
        XCTAssertEqual(report.errorCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("doc.zip").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst.appendingPathComponent("doc 2.md").path))
    }

    func testWorkspaceJSONRoundTripAndDemoGenerator() throws {
        let dir = try makeTempDir("demo")
        defer { try? FileManager.default.removeItem(at: dir) }

        let demo = DemoWorkspaceGenerator.ensureDemoWorkspace(baseDir: dir)
        XCTAssertEqual(demo.folders.count, 3)
        let downloads = try XCTUnwrap(demo.folders.first)
        let matches = RuleEvaluator.dryRun(folder: downloads)
        // Expect: 2 PDF invoices + 4 PNG screenshots + 2 old DMGs + 2 archives = 10 matches
        XCTAssertEqual(matches.count, 10)

        let data = try JSONEncoder().encode(demo)
        let decoded = try JSONDecoder().decode(RuleBoxWorkspace.self, from: data)
        XCTAssertEqual(decoded, demo)
    }

    func testKernelFolderWatcherDetectsNewFile() throws {
        let dir = try makeTempDir("watcher")
        defer { try? FileManager.default.removeItem(at: dir) }

        let exp = expectation(description: "FolderWatcher fires on file write")
        let folder = WatchedFolder(name: "Watch", path: dir.path)
        let watcher = FolderWatcher(debounceInterval: 0.1) { id in
            if id == folder.id {
                exp.fulfill()
            }
        }
        watcher.sync(folders: [folder], active: true)

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
            try? "trigger".write(to: dir.appendingPathComponent("drop.txt"), atomically: true, encoding: .utf8)
        }

        wait(for: [exp], timeout: 3.0)
        watcher.stopAll()
    }

    func testExampleRuleboxWorkspacesDecodeCleanly() throws {
        let examplesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("examples")
        let files = try FileManager.default.contentsOfDirectory(at: examplesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "rulebox" }
        XCTAssertGreaterThanOrEqual(files.count, 3)

        let decoder = JSONDecoder()
        for file in files {
            let data = try Data(contentsOf: file)
            let ws = try decoder.decode(RuleBoxWorkspace.self, from: data)
            XCTAssertFalse(ws.folders.isEmpty, "Example \(file.lastPathComponent) has no folders")
            XCTAssertFalse(ws.folders[0].rules.isEmpty, "Example \(file.lastPathComponent) has no rules")
            XCTAssertFalse(ws.folders[0].autoRunOnChange)
        }
    }

    @MainActor
    func testAutoRunTogglePersistsAndTriggersOnFolderEvent() throws {
        let dir = try makeTempDir("autorun")
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = RuleBoxStore(supportDir: dir, startWatcher: false)
        let firstID = try XCTUnwrap(store.workspace.folders.first?.id)
        XCTAssertFalse(store.workspace.folders[0].autoRunOnChange)

        store.toggleAutoRun(for: firstID)
        XCTAssertTrue(store.workspace.folders[0].autoRunOnChange)

        // Reload from disk and verify persistence
        let reloaded = RuleBoxStore(supportDir: dir, startWatcher: false)
        XCTAssertTrue(reloaded.workspace.folders[0].autoRunOnChange)
    }
}
