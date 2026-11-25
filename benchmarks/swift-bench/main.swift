import Foundation
import RuleBoxCore

private func medianMs(_ runs: Int, _ body: () -> Void) -> Double {
    var times: [Double] = []
    for _ in 0..<runs {
        let t0 = DispatchTime.now().uptimeNanoseconds
        body()
        let t1 = DispatchTime.now().uptimeNanoseconds
        times.append(Double(t1 - t0) / 1_000_000.0)
    }
    times.sort()
    return times[times.count / 2]
}

@main
struct RuleBoxBench {
    static func main() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("RuleBoxBench-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        // Benchmark 1: 1,000-file folder scan + 4-rule dry-run evaluation
        let dir1k = tmp.appendingPathComponent("files1000", isDirectory: true)
        try fm.createDirectory(at: dir1k, withIntermediateDirectories: true)
        for i in 0..<1000 {
            let ext = ["png", "jpg", "dmg", "zip", "md"][i % 5]
            let prefix = ext == "png" ? "Screenshot_" : "Item_"
            let url = dir1k.appendingPathComponent("\(prefix)\(String(format: "%04d", i)).\(ext)")
            try Data(repeating: UInt8(i & 0xFF), count: 256).write(to: url)
        }

        let folder1k = WatchedFolder(
            name: "Bench1000",
            path: dir1k.path,
            rules: [
                AutomationRule(
                    name: "Screenshots",
                    conditions: [
                        RuleCondition(field: .kind, op: .equals, value: FileKindCategory.image.rawValue),
                        RuleCondition(field: .name, op: .startsWith, value: "Screenshot")
                    ],
                    actions: [RuleAction(kind: .sortIntoSubfolder, pattern: "[Year]/[Month]")]
                ),
                AutomationRule(
                    name: "Archives",
                    conditions: [RuleCondition(field: .fileExtension, op: .inList, value: "zip,tar,gz")],
                    actions: [RuleAction(kind: .addTag, tagName: "Purple")]
                ),
                AutomationRule(
                    name: "Disk Images",
                    conditions: [RuleCondition(field: .kind, op: .equals, value: FileKindCategory.diskImage.rawValue)],
                    actions: [RuleAction(kind: .moveToTrash)]
                ),
                AutomationRule(
                    name: "Markdown",
                    conditions: [RuleCondition(field: .fileExtension, op: .equals, value: "md")],
                    actions: [RuleAction(kind: .rename, pattern: "[Date]_[Name].[Ext]")]
                )
            ]
        )

        var matchCount1k = 0
        let ms1k = medianMs(5) {
            let matches = RuleEvaluator.dryRun(folder: folder1k)
            matchCount1k = matches.count
        }
        print(String(format: "bench|dry_run_1000_files_4_rules|%d|%.1f", matchCount1k, ms1k))

        // Benchmark 2: 50 real PDFs with embedded text scanned via PDFKit contents condition
        let dirPdf = tmp.appendingPathComponent("pdfs50", isDirectory: true)
        try fm.createDirectory(at: dirPdf, withIntermediateDirectories: true)
        for i in 0..<50 {
            let isInvoice = (i % 2 == 0)
            DemoWorkspaceGenerator.writeTextPDF(
                to: dirPdf.appendingPathComponent("Doc_\(String(format: "%02d", i)).pdf"),
                title: isInvoice ? "Vendor Invoice #2026-\(i)" : "Engineering Memo #\(i)",
                body: isInvoice ? "Total Due: $120.00" : "No billing content here."
            )
        }
        let folderPdf = WatchedFolder(
            name: "BenchPDF50",
            path: dirPdf.path,
            rules: [
                AutomationRule(
                    name: "Match PDF Invoices",
                    conditions: [
                        RuleCondition(field: .kind, op: .equals, value: FileKindCategory.pdf.rawValue),
                        RuleCondition(field: .contents, op: .contains, value: "Invoice")
                    ],
                    actions: [RuleAction(kind: .addTag, tagName: "Green")]
                )
            ]
        )
        var pdfMatches = 0
        let msPdf = medianMs(5) {
            pdfMatches = RuleEvaluator.dryRun(folder: folderPdf).count
        }
        print(String(format: "bench|pdfkit_content_scan_50_pdfs|%d|%.1f", pdfMatches, msPdf))

        // Benchmark 3: Execute 100 real file renames + subfolder sorts + Finder tags + Undo all 100
        let dirExec = tmp.appendingPathComponent("exec100", isDirectory: true)
        try fm.createDirectory(at: dirExec, withIntermediateDirectories: true)
        for i in 0..<100 {
            try Data(repeating: 0xAA, count: 512).write(to: dirExec.appendingPathComponent("Screenshot_\(i).png"))
        }
        let folderExec = WatchedFolder(
            name: "BenchExec100",
            path: dirExec.path,
            rules: [
                AutomationRule(
                    name: "Tag, Rename & Sort",
                    conditions: [RuleCondition(field: .kind, op: .equals, value: FileKindCategory.image.rawValue)],
                    actions: [
                        RuleAction(kind: .addTag, tagName: "Blue"),
                        RuleAction(kind: .rename, pattern: "[Year]-[Month]_[Name].[Ext]"),
                        RuleAction(kind: .sortIntoSubfolder, pattern: "[Year]/[Month]")
                    ]
                )
            ]
        )
        let t0 = DispatchTime.now().uptimeNanoseconds
        let report = RuleExecutor.run(folder: folderExec)
        let t1 = DispatchTime.now().uptimeNanoseconds
        let execMs = Double(t1 - t0) / 1_000_000.0

        let u0 = DispatchTime.now().uptimeNanoseconds
        var undone = 0
        for entry in report.entries where entry.canUndo {
            _ = try RuleExecutor.undo(entry: entry)
            undone += 1
        }
        let u1 = DispatchTime.now().uptimeNanoseconds
        let undoMs = Double(u1 - u0) / 1_000_000.0

        print(String(format: "bench|execute_100_tag_rename_sort|%d|%.1f", report.matchedCount, execMs))
        print(String(format: "bench|undo_100_operations|%d|%.1f", undone, undoMs))
    }
}
