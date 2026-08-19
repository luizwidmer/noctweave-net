import Foundation

/// One exact file in a Noctweb website bundle.
public struct WebsiteFile: Codable, Equatable, Sendable {
    public var path: String
    public var mediaType: String
    public var bytes: Data

    public init(path: String, mediaType: String, bytes: Data) {
        self.path = path
        self.mediaType = mediaType
        self.bytes = bytes
    }
}

/// A conventional static website whose complete contents are signed by a
/// publisher head and transported as one capsule object.
public struct WebsiteBundle: Codable, Equatable, Sendable {
    public static let maximumFileCount = 512
    public static let maximumTotalBytes = 16 * 1_024 * 1_024
    public static let maximumPathBytes = 2_048
    public static let maximumMediaTypeBytes = 128

    public var entryPath: String
    public var files: [WebsiteFile]

    public init(entryPath: String, files: [WebsiteFile]) {
        self.entryPath = entryPath
        self.files = files
    }

    public func file(at path: String) -> WebsiteFile? {
        files.first { $0.path == path }
    }

    public func canonicalized() throws -> WebsiteBundle {
        try WebsiteBundleValidation.canonicalized(self)
    }
}

enum WebsiteBundleValidation {
    static func canonicalized(_ bundle: WebsiteBundle) throws -> WebsiteBundle {
        guard !bundle.files.isEmpty else {
            throw NoctwebLabError.invalidWebsiteBundle(
                "a website bundle must contain at least one file"
            )
        }
        guard bundle.files.count <= WebsiteBundle.maximumFileCount else {
            throw NoctwebLabError.invalidWebsiteBundle(
                "a website bundle may contain at most \(WebsiteBundle.maximumFileCount) files"
            )
        }

        let entryPath = try normalizedRelativePath(bundle.entryPath)
        var exactPaths = Set<String>()
        var foldedPaths = [String: String]()
        var totalBytes = 0
        var canonicalFiles: [WebsiteFile] = []
        canonicalFiles.reserveCapacity(bundle.files.count)

        for file in bundle.files {
            let path = try normalizedRelativePath(file.path)
            guard exactPaths.insert(path).inserted else {
                throw NoctwebLabError.invalidWebsiteBundle(
                    "duplicate website path: \(path)"
                )
            }

            let folded = path.lowercased()
            if let existing = foldedPaths[folded], existing != path {
                throw NoctwebLabError.invalidWebsiteBundle(
                    "website paths conflict by case: \(existing) and \(path)"
                )
            }
            foldedPaths[folded] = path

            let mediaType = file.mediaType.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard
                !mediaType.isEmpty,
                mediaType.contains("/"),
                mediaType.utf8.count <= WebsiteBundle.maximumMediaTypeBytes,
                mediaType.unicodeScalars.allSatisfy({
                    !CharacterSet.controlCharacters.contains($0)
                })
            else {
                throw NoctwebLabError.invalidWebsiteBundle(
                    "invalid media type for \(path)"
                )
            }

            guard file.bytes.count <= WebsiteBundle.maximumTotalBytes - totalBytes else {
                throw NoctwebLabError.invalidWebsiteBundle(
                    "website bundle exceeds \(WebsiteBundle.maximumTotalBytes) bytes"
                )
            }
            totalBytes += file.bytes.count
            canonicalFiles.append(
                WebsiteFile(path: path, mediaType: mediaType, bytes: file.bytes)
            )
        }

        guard exactPaths.contains(entryPath) else {
            throw NoctwebLabError.invalidWebsiteBundle(
                "entry point does not exist: \(entryPath)"
            )
        }

        canonicalFiles.sort {
            $0.path.utf8.lexicographicallyPrecedes($1.path.utf8)
        }
        return WebsiteBundle(entryPath: entryPath, files: canonicalFiles)
    }

    private static func normalizedRelativePath(_ rawPath: String) throws -> String {
        guard
            !rawPath.isEmpty,
            rawPath.utf8.count <= WebsiteBundle.maximumPathBytes
        else {
            throw NoctwebLabError.invalidWebsiteBundle(
                "website paths must be non-empty and at most \(WebsiteBundle.maximumPathBytes) UTF-8 bytes"
            )
        }

        let path = rawPath.precomposedStringWithCanonicalMapping
        guard
            !path.hasPrefix("/"),
            !path.hasPrefix("\\"),
            !path.contains("\\"),
            !path.unicodeScalars.contains(where: { $0.value == 0 }),
            !isWindowsAbsolutePath(path)
        else {
            throw NoctwebLabError.invalidWebsiteBundle(
                "website paths must be normalized relative paths: \(rawPath)"
            )
        }

        let components = path.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw NoctwebLabError.invalidWebsiteBundle(
                "website paths cannot contain empty, current, or parent segments: \(rawPath)"
            )
        }

        if let decoded = path.removingPercentEncoding, decoded != path {
            throw NoctwebLabError.invalidWebsiteBundle(
                "percent-encoded website paths are not canonical: \(rawPath)"
            )
        }

        return path
    }

    private static func isWindowsAbsolutePath(_ path: String) -> Bool {
        guard path.count >= 2 else {
            return false
        }
        let characters = Array(path.prefix(2))
        return characters[0].isASCII &&
            characters[0].isLetter &&
            characters[1] == ":"
    }
}
