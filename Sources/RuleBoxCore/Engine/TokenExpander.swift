import Foundation

/// Expands dynamic filename and subfolder tokens such as `[Name]`, `[Ext]`, `[Year]`, `[Month]`, `[Day]`, `[Date]`, `[Kind]`, `[Parent]`, `[Counter]`.
public enum TokenExpander {
    public static let availableTokens: [String] = [
        "[Name]", "[Ext]", "[Year]", "[Month]", "[Day]", "[Date]", "[Kind]", "[Parent]", "[Counter]"
    ]

    public static func expand(
        pattern: String,
        fileURL: URL,
        kind: FileKindCategory,
        referenceDate: Date = Date(),
        counter: Int = 1
    ) -> String {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day], from: referenceDate)
        let year = String(format: "%04d", comps.year ?? 2026)
        let month = String(format: "%02d", comps.month ?? 1)
        let day = String(format: "%02d", comps.day ?? 1)
        let isoDate = "\(year)-\(month)-\(day)"

        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let ext = fileURL.pathExtension
        let parent = fileURL.deletingLastPathComponent().lastPathComponent
        let counterStr = String(format: "%03d", max(1, counter))

        var out = pattern
        let map: [(String, String)] = [
            ("[Name]", baseName),
            ("[Ext]", ext),
            ("[Year]", year),
            ("[Month]", month),
            ("[Day]", day),
            ("[Date]", isoDate),
            ("[Kind]", kind.rawValue),
            ("[Parent]", parent),
            ("[Counter]", counterStr)
        ]
        for (token, replacement) in map {
            out = out.replacingOccurrences(of: token, with: replacement)
        }
        return out
    }

    /// Sanitizes an expanded filename (never allows path separators or empty strings).
    public static func sanitizeFileName(_ raw: String, fallback: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." {
            return fallback
        }
        return cleaned
    }

    /// Sanitizes a relative subfolder path (prevents path traversal `..`).
    public static func sanitizeRelativeSubfolder(_ raw: String) -> String {
        let components = raw
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
            .map { $0.replacingOccurrences(of: ":", with: "-") }
        return components.joined(separator: "/")
    }
}
