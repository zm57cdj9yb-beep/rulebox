import AppKit
import CoreGraphics
import Foundation

/// Curated 1-click starter rule templates modeled after the most common Hazel workflows.
public struct RulePreset: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let symbolName: String
    public let category: String
    public let makeRule: @Sendable (String) -> AutomationRule
}

/// Creates a safe local demo sandbox with real PDFs (with embedded text), PNG screenshots,
/// old disk images, archives, and starter rules so first-launch users can inspect live matches
/// and test Run / Undo safely without touching their real ~/Downloads.
public enum DemoWorkspaceGenerator {
    public static func defaultSupportDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("RuleBox", isDirectory: true)
    }

    public static func ensureDemoWorkspace(baseDir: URL? = nil) -> RuleBoxWorkspace {
        let root = (baseDir ?? defaultSupportDirectory()).appendingPathComponent("DemoWorkspace", isDirectory: true)
        let downloads = root.appendingPathComponent("Downloads", isDirectory: true)
        let invoices = root.appendingPathComponent("Invoices", isDirectory: true)
        let screenshots = root.appendingPathComponent("Screenshots", isDirectory: true)
        let archives = root.appendingPathComponent("Archives", isDirectory: true)

        let fm = FileManager.default
        for dir in [downloads, invoices, screenshots, archives] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Only populate sample files if Downloads is empty (so user edits/runs persist)
        let existing = (try? fm.contentsOfDirectory(atPath: downloads.path))?.filter { $0 != ".DS_Store" } ?? []
        if existing.isEmpty {
            populateDemoFiles(downloads: downloads, screenshots: screenshots)
        }

        let downloadsFolder = WatchedFolder(
            name: "Downloads (Demo)",
            path: downloads.path,
            iconName: "arrow.down.circle.fill",
            isEnabled: true,
            includeSubfolders: false,
            rules: [
                AutomationRule(
                    name: "Auto-File PDF Invoices",
                    isEnabled: true,
                    matchMode: .all,
                    conditions: [
                        RuleCondition(field: .kind, op: .equals, value: FileKindCategory.pdf.rawValue),
                        RuleCondition(field: .contents, op: .contains, value: "Invoice")
                    ],
                    actions: [
                        RuleAction(kind: .addTag, tagName: "Green"),
                        RuleAction(kind: .rename, pattern: "[Year]-[Month]_[Name].[Ext]"),
                        RuleAction(kind: .move, targetPath: invoices.path, conflictPolicy: .rename)
                    ]
                ),
                AutomationRule(
                    name: "Organize Screenshots by Month",
                    isEnabled: true,
                    matchMode: .all,
                    conditions: [
                        RuleCondition(field: .kind, op: .equals, value: FileKindCategory.image.rawValue),
                        RuleCondition(field: .name, op: .startsWith, value: "Screenshot")
                    ],
                    actions: [
                        RuleAction(kind: .addTag, tagName: "Blue"),
                        RuleAction(kind: .move, targetPath: screenshots.path, conflictPolicy: .rename)
                    ]
                ),
                AutomationRule(
                    name: "Clean Up Old Installers (>14d)",
                    isEnabled: true,
                    matchMode: .all,
                    conditions: [
                        RuleCondition(field: .kind, op: .equals, value: FileKindCategory.diskImage.rawValue),
                        RuleCondition(field: .ageDays, op: .greaterThan, value: "14")
                    ],
                    actions: [
                        RuleAction(kind: .moveToTrash)
                    ]
                ),
                AutomationRule(
                    name: "Sort Archives into Folder",
                    isEnabled: true,
                    matchMode: .all,
                    conditions: [
                        RuleCondition(field: .fileExtension, op: .inList, value: "zip,tar,gz,7z")
                    ],
                    actions: [
                        RuleAction(kind: .addTag, tagName: "Purple"),
                        RuleAction(kind: .move, targetPath: archives.path, conflictPolicy: .rename)
                    ]
                )
            ]
        )

        let screenshotsFolder = WatchedFolder(
            name: "Screenshots (Demo)",
            path: screenshots.path,
            iconName: "camera.viewfinder",
            isEnabled: true,
            includeSubfolders: false,
            rules: [
                AutomationRule(
                    name: "Group by Year / Month",
                    isEnabled: true,
                    matchMode: .all,
                    conditions: [
                        RuleCondition(field: .kind, op: .equals, value: FileKindCategory.image.rawValue)
                    ],
                    actions: [
                        RuleAction(kind: .sortIntoSubfolder, pattern: "[Year]/[Month]")
                    ]
                )
            ]
        )

        let invoicesFolder = WatchedFolder(
            name: "Invoices (Demo)",
            path: invoices.path,
            iconName: "doc.text.fill",
            isEnabled: true,
            includeSubfolders: false,
            rules: [
                AutomationRule(
                    name: "Sort Tax PDFs by Year",
                    isEnabled: true,
                    matchMode: .all,
                    conditions: [
                        RuleCondition(field: .kind, op: .equals, value: FileKindCategory.pdf.rawValue)
                    ],
                    actions: [
                        RuleAction(kind: .sortIntoSubfolder, pattern: "[Year]")
                    ]
                )
            ]
        )

        return RuleBoxWorkspace(
            watcherActive: true,
            folders: [downloadsFolder, screenshotsFolder, invoicesFolder]
        )
    }

    public static func populateDemoFiles(downloads: URL, screenshots: URL) {
        let fm = FileManager.default
        let now = Date()

        // 3 real PDFs containing actual searchable text ("Invoice")
        writeTextPDF(
            to: downloads.appendingPathComponent("Acme_Cloud_Nov.pdf"),
            title: "ACME Cloud Services — Invoice #2026-104",
            body: "Amount Due: $49.00\nBilling Period: November 2026\nThank you for your business."
        )
        writeTextPDF(
            to: downloads.appendingPathComponent("Hetzner_Server_Bill.pdf"),
            title: "Hetzner Online GmbH — Monthly Invoice #88412",
            body: "Dedicated ARM64 Node\nTotal: EUR 18.90\nPaid via SEPA."
        )
        writeTextPDF(
            to: downloads.appendingPathComponent("Design_Contract_Draft.pdf"),
            title: "Project Scope & Architecture Notes",
            body: "This document is a technical specification and does not contain billing statements."
        )

        // 4 real PNG screenshots
        for idx in 1...4 {
            let name = "Screenshot 2026-11-\(20 + idx) at 14.\(10 + idx).png"
            writeTinyPNG(to: downloads.appendingPathComponent(name))
        }
        for idx in 1...2 {
            let name = "Capture_UI_0\(idx).png"
            writeTinyPNG(to: screenshots.appendingPathComponent(name))
        }

        // 3 disk images (2 older than 14 days, 1 recent)
        let oldDate = now.addingTimeInterval(-28 * 86_400)
        for (name, isOld) in [("Firefox_132.dmg", true), ("Docker_Desktop_4.35.dmg", true), ("Raycast_Latest.dmg", false)] {
            let url = downloads.appendingPathComponent(name)
            try? Data(repeating: 0x44, count: 4096).write(to: url)
            if isOld {
                try? fm.setAttributes([.modificationDate: oldDate, .creationDate: oldDate], ofItemAtPath: url.path)
            }
        }

        // 2 ZIP archives + 2 code/notes files
        for name in ["brand-kit-v2.zip", "logs-backup-2026.tar.gz"] {
            try? Data(repeating: 0x50, count: 2048).write(to: downloads.appendingPathComponent(name))
        }
        try? "# Release Checklist\n- Run swift test\n- Verify codesign\n".write(
            to: downloads.appendingPathComponent("release-notes.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    public static func writeTextPDF(to url: URL, title: String, body: String) {
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return
        }
        ctx.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.black
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.darkGray
        ]
        NSAttributedString(string: title, attributes: titleAttrs).draw(at: CGPoint(x: 48, y: 760))
        NSAttributedString(string: body, attributes: bodyAttrs).draw(at: CGPoint(x: 48, y: 710))

        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
        ctx.closePDF()
    }

    private static func writeTinyPNG(to url: URL) {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 24,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )
        if let rep, let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }

    public static let curatedPresets: [RulePreset] = [
        RulePreset(
            id: "clean-dmgs",
            title: "Trash Old Installers (>14 Days)",
            subtitle: "Automatically move .dmg and .pkg installers older than 14 days to Trash.",
            symbolName: "trash.circle.fill",
            category: "Cleanup",
            makeRule: { _ in
                AutomationRule(
                    name: "Clean Up Old Installers (>14d)",
                    conditions: [
                        RuleCondition(field: .kind, op: .equals, value: FileKindCategory.diskImage.rawValue),
                        RuleCondition(field: .ageDays, op: .greaterThan, value: "14")
                    ],
                    actions: [RuleAction(kind: .moveToTrash)]
                )
            }
        ),
        RulePreset(
            id: "pdf-invoices",
            title: "Auto-File PDF Invoices",
            subtitle: "Inspect PDF text with PDFKit, tag Green, prefix YYYY-MM, and sort into Invoices/.",
            symbolName: "doc.text.magnifyingglass",
            category: "Finance",
            makeRule: { folderPath in
                let dest = URL(fileURLWithPath: folderPath).appendingPathComponent("Invoices").path
                return AutomationRule(
                    name: "Auto-File PDF Invoices",
                    conditions: [
                        RuleCondition(field: .kind, op: .equals, value: FileKindCategory.pdf.rawValue),
                        RuleCondition(field: .contents, op: .contains, value: "Invoice")
                    ],
                    actions: [
                        RuleAction(kind: .addTag, tagName: "Green"),
                        RuleAction(kind: .rename, pattern: "[Year]-[Month]_[Name].[Ext]"),
                        RuleAction(kind: .move, targetPath: dest)
                    ]
                )
            }
        ),
        RulePreset(
            id: "screenshots-by-date",
            title: "Sort Screenshots by Year/Month",
            subtitle: "Group PNG screenshots cleanly into [Year]/[Month] subfolders.",
            symbolName: "calendar.badge.clock",
            category: "Organization",
            makeRule: { _ in
                AutomationRule(
                    name: "Sort Screenshots by Date",
                    conditions: [
                        RuleCondition(field: .kind, op: .equals, value: FileKindCategory.image.rawValue),
                        RuleCondition(field: .name, op: .startsWith, value: "Screenshot")
                    ],
                    actions: [
                        RuleAction(kind: .addTag, tagName: "Blue"),
                        RuleAction(kind: .sortIntoSubfolder, pattern: "[Year]/[Month]")
                    ]
                )
            }
        ),
        RulePreset(
            id: "tag-large-files",
            title: "Flag Large Files (>500 MB)",
            subtitle: "Apply a Red Finder tag to any file exceeding 500 MB for quick cleanup.",
            symbolName: "externaldrive.badge.exclamationmark",
            category: "Storage",
            makeRule: { _ in
                AutomationRule(
                    name: "Flag Large Files (>500 MB)",
                    conditions: [
                        RuleCondition(field: .sizeMB, op: .greaterThan, value: "500")
                    ],
                    actions: [
                        RuleAction(kind: .addTag, tagName: "Red")
                    ]
                )
            }
        ),
        RulePreset(
            id: "archive-old-docs",
            title: "ZIP Old Documents (>30 Days)",
            subtitle: "Compress documents untouched for 30+ days into tidy .zip archives.",
            symbolName: "archivebox.fill",
            category: "Archiving",
            makeRule: { _ in
                AutomationRule(
                    name: "ZIP Old Documents (>30d)",
                    conditions: [
                        RuleCondition(field: .kind, op: .equals, value: FileKindCategory.document.rawValue),
                        RuleCondition(field: .ageDays, op: .greaterThan, value: "30")
                    ],
                    actions: [
                        RuleAction(kind: .archiveZip)
                    ]
                )
            }
        )
    ]
}
