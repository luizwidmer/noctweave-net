import Foundation

public struct NoctwebWebsiteFile: Codable, Equatable, Hashable, Sendable {
    public let path: String
    public let mediaType: String
    public let bytes: Data

    public init(path: String, mediaType: String, bytes: Data) {
        self.path = path
        self.mediaType = mediaType
        self.bytes = bytes
    }
}

public struct NoctwebWebsiteBundle: Codable, Equatable, Hashable, Sendable {
    public static let maximumFileCount = 512
    public static let maximumTotalBytes = 16 * 1_024 * 1_024

    public let entryPath: String
    public let files: [NoctwebWebsiteFile]

    public init(
        entryPath: String,
        files: [NoctwebWebsiteFile]
    ) throws {
        guard
            !files.isEmpty,
            files.count <= Self.maximumFileCount
        else {
            throw NoctwebBrowserError.invalidWebsiteBundle(
                "file count must be between 1 and \(Self.maximumFileCount)"
            )
        }
        let normalizedEntry = try Self.normalizedRelativePath(entryPath)
        var exactPaths = Set<String>()
        var foldedPaths = [String: String]()
        var totalBytes = 0
        var canonicalFiles: [NoctwebWebsiteFile] = []
        canonicalFiles.reserveCapacity(files.count)

        for file in files {
            let path = try Self.normalizedRelativePath(file.path)
            guard exactPaths.insert(path).inserted else {
                throw NoctwebBrowserError.invalidWebsiteBundle(
                    "duplicate path \(path)"
                )
            }
            let folded = path.lowercased()
            if let existing = foldedPaths[folded], existing != path {
                throw NoctwebBrowserError.invalidWebsiteBundle(
                    "case-conflicting paths \(existing) and \(path)"
                )
            }
            foldedPaths[folded] = path
            let mediaType = file.mediaType.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard
                !mediaType.isEmpty,
                mediaType.contains("/"),
                mediaType.utf8.count <= 128,
                !mediaType.unicodeScalars.contains(where: {
                    CharacterSet.controlCharacters.contains($0)
                })
            else {
                throw NoctwebBrowserError.invalidWebsiteBundle(
                    "invalid media type for \(path)"
                )
            }
            guard file.bytes.count <= Self.maximumTotalBytes - totalBytes else {
                throw NoctwebBrowserError.invalidWebsiteBundle(
                    "bundle exceeds \(Self.maximumTotalBytes) bytes"
                )
            }
            totalBytes += file.bytes.count
            canonicalFiles.append(
                NoctwebWebsiteFile(
                    path: path,
                    mediaType: mediaType,
                    bytes: file.bytes
                )
            )
        }
        guard exactPaths.contains(normalizedEntry) else {
            throw NoctwebBrowserError.invalidWebsiteBundle(
                "entry path does not exist"
            )
        }
        canonicalFiles.sort {
            $0.path.utf8.lexicographicallyPrecedes($1.path.utf8)
        }
        self.entryPath = normalizedEntry
        self.files = canonicalFiles
    }

    public var totalBytes: Int {
        files.reduce(0) { $0 + $1.bytes.count }
    }

    public func file(at path: String) -> NoctwebWebsiteFile? {
        files.first { $0.path == path }
    }

    public func resource(for requestPath: String) -> NoctwebWebsiteFile? {
        let candidate = requestPath == "/"
            ? entryPath
            : String(requestPath.drop(while: { $0 == "/" }))
        if let exact = file(at: candidate) {
            return exact
        }
        let finalComponent = candidate.split(separator: "/").last ?? ""
        if !finalComponent.contains(".") {
            return file(at: entryPath)
        }
        return nil
    }

    public func canonicalBytes() throws -> Data {
        struct CanonicalFile: Codable {
            let bytes: String
            let mediaType: String
            let path: String
        }
        struct CanonicalBundle: Codable {
            let entryPath: String
            let files: [CanonicalFile]
        }
        let canonical = CanonicalBundle(
            entryPath: entryPath,
            files: files.map {
                CanonicalFile(
                    bytes: $0.bytes.base64EncodedString(),
                    mediaType: $0.mediaType,
                    path: $0.path
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(canonical)
    }

    private enum CodingKeys: String, CodingKey {
        case entryPath
        case files
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            entryPath: container.decode(String.self, forKey: .entryPath),
            files: container.decode(
                [NoctwebWebsiteFile].self,
                forKey: .files
            )
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entryPath, forKey: .entryPath)
        try container.encode(files, forKey: .files)
    }

    private static func normalizedRelativePath(_ raw: String) throws -> String {
        guard
            !raw.isEmpty,
            raw.utf8.count <= 2_048
        else {
            throw NoctwebBrowserError.invalidWebsiteBundle(
                "website paths must be non-empty and bounded"
            )
        }
        let path = raw.precomposedStringWithCanonicalMapping
        guard
            !path.hasPrefix("/"),
            !path.hasPrefix("\\"),
            !path.contains("\\"),
            !path.unicodeScalars.contains(where: { $0.value == 0 }),
            path.removingPercentEncoding == path
        else {
            throw NoctwebBrowserError.invalidWebsiteBundle(
                "website paths must be normalized relative paths"
            )
        }
        let segments = path.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard segments.allSatisfy({
            !$0.isEmpty && $0 != "." && $0 != ".."
        }) else {
            throw NoctwebBrowserError.invalidWebsiteBundle(
                "website paths cannot traverse directories"
            )
        }
        if path.count >= 2 {
            let prefix = Array(path.prefix(2))
            if prefix[0].isASCII && prefix[0].isLetter && prefix[1] == ":" {
                throw NoctwebBrowserError.invalidWebsiteBundle(
                    "absolute paths are forbidden"
                )
            }
        }
        return path
    }
}
