import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Snapshot of a file's metadata used during rule evaluation.
public struct FileSnapshot: Sendable {
    public let url: URL
    public let fileName: String
    public let baseName: String
    public let fileExtension: String
    public let kind: FileKindCategory
    public let sizeBytes: Int64
    public let creationDate: Date
    public let modificationDate: Date
    public let addedDate: Date
    public let isHidden: Bool
    public let isDirectory: Bool
    public let tags: [String]

    public var sizeMB: Double {
        Double(sizeBytes) / 1_048_576.0
    }

    public func ageDays(relativeTo now: Date = Date()) -> Double {
        max(0.0, now.timeIntervalSince(modificationDate) / 86_400.0)
    }
}

/// Fast, zero-dependency file metadata & PDF/text content inspector.
public enum FileInspector {
    private static let resourceKeys: Set<URLResourceKey> = [
        .nameKey,
        .isRegularFileKey,
        .isDirectoryKey,
        .isHiddenKey,
        .fileSizeKey,
        .creationDateKey,
        .contentModificationDateKey,
        .addedToDirectoryDateKey,
        .tagNamesKey,
        .contentTypeKey
    ]

    public static func inspect(url: URL) -> FileSnapshot? {
        guard let values = try? url.resourceValues(forKeys: resourceKeys) else {
            return nil
        }
        let isDir = values.isDirectory ?? false
        let name = values.name ?? url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let baseName = url.deletingPathExtension().lastPathComponent
        let size = Int64(values.fileSize ?? 0)
        let mod = values.contentModificationDate ?? Date()
        let created = values.creationDate ?? mod
        let added = values.addedToDirectoryDate ?? mod
        let hidden = values.isHidden ?? name.hasPrefix(".")
        let tags = values.tagNames ?? []
        let kind = classifyKind(isDirectory: isDir, ext: ext, contentType: values.contentType)

        return FileSnapshot(
            url: url,
            fileName: name,
            baseName: baseName,
            fileExtension: ext,
            kind: kind,
            sizeBytes: size,
            creationDate: created,
            modificationDate: mod,
            addedDate: added,
            isHidden: hidden,
            isDirectory: isDir,
            tags: tags
        )
    }

    public static func listFiles(in folderURL: URL, includeSubfolders: Bool) -> [FileSnapshot] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folderURL.path) else { return [] }

        var urls: [URL] = []
        if includeSubfolders {
            if let en = fm.enumerator(
                at: folderURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsPackageDescendants]
            ) {
                for case let url as URL in en {
                    if url.lastPathComponent == ".DS_Store" { continue }
                    urls.append(url)
                }
            }
        } else {
            if let items = try? fm.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: []
            ) {
                urls = items.filter { $0.lastPathComponent != ".DS_Store" }
            }
        }

        return urls
            .compactMap { inspect(url: $0) }
            .sorted { $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending }
    }

    /// Extracts searchable text from plain-text files or PDF documents (bounded to first 5 pages / 32 KB).
    public static func extractSearchableText(from snapshot: FileSnapshot) -> String {
        guard !snapshot.isDirectory else { return "" }

        if snapshot.kind == .pdf || snapshot.fileExtension == "pdf" {
            guard let doc = PDFDocument(url: snapshot.url) else { return "" }
            let limit = min(doc.pageCount, 5)
            var combined = ""
            combined.reserveCapacity(4096)
            for idx in 0..<limit {
                if let pageText = doc.page(at: idx)?.string {
                    combined.append(pageText)
                    combined.append("\n")
                    if combined.utf8.count >= 32_768 { break }
                }
            }
            return combined
        }

        let textExts: Set<String> = [
            "txt", "md", "markdown", "csv", "json", "xml", "html", "htm",
            "swift", "rs", "ts", "tsx", "js", "py", "sh", "yml", "yaml", "toml", "log", "rtf"
        ]
        guard textExts.contains(snapshot.fileExtension), snapshot.sizeBytes <= 2_097_152 else {
            return ""
        }
        guard let handle = try? FileHandle(forReadingFrom: snapshot.url) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 32_768)) ?? Data()
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .macOSRoman) ?? ""
    }

    public static func classifyKind(isDirectory: Bool, ext: String, contentType: UTType?) -> FileKindCategory {
        if isDirectory { return .folder }
        let lower = ext.lowercased()

        if lower == "pdf" || contentType?.conforms(to: .pdf) == true { return .pdf }
        if ["dmg", "iso", "img", "pkg"].contains(lower) { return .diskImage }
        if ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar"].contains(lower) || contentType?.conforms(to: .archive) == true {
            return .archive
        }
        if ["png", "jpg", "jpeg", "heic", "heif", "webp", "gif", "tiff", "tif", "bmp", "svg", "raw", "dng", "cr2", "nef", "arw"].contains(lower)
            || contentType?.conforms(to: .image) == true {
            return .image
        }
        if ["mp4", "mov", "mkv", "avi", "webm", "m4v"].contains(lower) || contentType?.conforms(to: .movie) == true {
            return .video
        }
        if ["mp3", "wav", "aac", "m4a", "flac", "ogg", "aiff"].contains(lower) || contentType?.conforms(to: .audio) == true {
            return .audio
        }
        if ["swift", "rs", "ts", "tsx", "js", "jsx", "py", "go", "c", "cpp", "h", "hpp", "java", "kt", "rb", "sh", "zsh", "json", "yaml", "yml", "toml"].contains(lower) {
            return .code
        }
        if ["doc", "docx", "pages", "rtf", "txt", "md", "markdown", "csv", "xls", "xlsx", "numbers", "ppt", "pptx", "key"].contains(lower)
            || contentType?.conforms(to: .text) == true {
            return .document
        }
        return .other
    }
}
