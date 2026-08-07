import Darwin
import Foundation
import NoctwebLabCore
import UniformTypeIdentifiers

enum WebsiteProjectBuilderError: LocalizedError {
    case missingEntryPoint(String)
    case unreadableFile(String)
    case symbolicLink(String)
    case tooManyFiles(Int)
    case bundleTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case let .missingEntryPoint(path):
            "The selected folder does not contain \(path). Choose a static build output such as dist."
        case let .unreadableFile(path):
            "The website file could not be read: \(path)"
        case let .symbolicLink(path):
            "Symbolic links are not imported into a signed website bundle: \(path)"
        case let .tooManyFiles(count):
            "The website contains \(count) files; the Lab limit is 512."
        case let .bundleTooLarge(bytes):
            "The website is \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)); the Lab limit is 16 MB."
        }
    }
}

enum WebsiteProjectBuilder {
    static let entryPath = "index.html"
    static let maximumFileCount = 512
    static let maximumBundleBytes = 16 * 1_024 * 1_024

    static func ensureProject(_ site: inout SiteProject) {
        if site.blocks == nil || site.blocks?.isEmpty == true {
            site.blocks = legacyBlocks(for: site)
        }
        if site.projectKind == nil {
            site.projectKind = .visual
        }
        if site.entryPath == nil {
            site.entryPath = entryPath
        }
        if site.files == nil || site.files?.isEmpty == true {
            synchronizeVisualProject(&site)
        }
    }

    static func synchronizeVisualProject(_ site: inout SiteProject) {
        let blocks = site.resolvedBlocks.isEmpty
            ? legacyBlocks(for: site)
            : site.resolvedBlocks
        site.blocks = blocks
        site.projectKind = .visual
        site.entryPath = entryPath

        if let hero = blocks.first(where: { $0.kind == .hero }) {
            site.title = hero.heading
            site.subtitle = hero.body
        }
        if let text = blocks.first(where: { $0.kind == .text }) {
            site.body = text.body
        }

        let generated: [(String, String, Data)] = [
            (
                "index.html",
                "text/html",
                Data(renderHTML(site: site, blocks: blocks).utf8)
            ),
            (
                "styles.css",
                "text/css",
                Data(renderCSS(accentHex: site.accentHex).utf8)
            ),
            (
                "app.js",
                "text/javascript",
                Data(defaultJavaScript.utf8)
            ),
        ]
        let existing = Dictionary(
            uniqueKeysWithValues: site.resolvedFiles.map { ($0.path, $0) }
        )
        let generatedPaths = Set(generated.map(\.0))
        let customFiles = site.resolvedFiles.filter {
            !generatedPaths.contains($0.path)
        }
        site.files = generated.map { path, mediaType, bytes in
            SiteSourceFile(
                id: existing[path]?.id ?? UUID(),
                path: path,
                mediaType: mediaType,
                bytes: bytes
            )
        } + customFiles
    }

    static func makeBundle(from site: SiteProject) throws -> WebsiteBundle {
        try WebsiteBundle(
            entryPath: site.resolvedEntryPath,
            files: site.resolvedFiles.map {
                WebsiteFile(
                    path: $0.path,
                    mediaType: $0.mediaType,
                    bytes: $0.bytes
                )
            }
        ).canonicalized()
    }

    static func importDirectory(
        at rootURL: URL,
        entryPath: String = WebsiteProjectBuilder.entryPath
    ) throws -> [SiteSourceFile] {
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            throw WebsiteProjectBuilderError.unreadableFile(
                rootURL.lastPathComponent
            )
        }

        var files: [SiteSourceFile] = []
        var totalBytes = 0
        let rootPath = rootURL.standardizedFileURL.path

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: resourceKeys)
            let relativePath = normalizedRelativePath(
                fileURL.standardizedFileURL.path,
                rootPath: rootPath
            )
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                throw WebsiteProjectBuilderError.symbolicLink(relativePath)
            }
            if values.isDirectory == true {
                if ["node_modules", ".git"].contains(fileURL.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true else { continue }

            if files.count + 1 > maximumFileCount {
                throw WebsiteProjectBuilderError.tooManyFiles(files.count + 1)
            }
            let remainingBytes = maximumBundleBytes - totalBytes
            if let announcedSize = values.fileSize,
               announcedSize > remainingBytes
            {
                throw WebsiteProjectBuilderError.bundleTooLarge(
                    totalBytes + announcedSize
                )
            }
            let bytes = try readBoundedRegularFile(
                at: fileURL,
                relativePath: relativePath,
                maximumBytes: remainingBytes,
                existingBytes: totalBytes
            )
            totalBytes += bytes.count
            files.append(
                SiteSourceFile(
                    path: relativePath,
                    mediaType: mediaType(for: fileURL),
                    bytes: bytes
                )
            )
        }

        guard files.contains(where: { $0.path == entryPath }) else {
            throw WebsiteProjectBuilderError.missingEntryPoint(entryPath)
        }
        return files.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    static func mediaType(forPath path: String) -> String {
        mediaType(for: URL(fileURLWithPath: path))
    }

    static func legacyCSS(accentHex: String) -> String {
        """
        :root { color-scheme: light dark; --accent: \(accentHex); --canvas: #f5f7fc; --ink: #151827; --muted: #62697a; }
        body { font: 18px/1.65 -apple-system, sans-serif; max-width: 760px; margin: auto; padding: 10vw 2rem; color: var(--ink); background: var(--canvas); }
        h1 { color: var(--accent); font: 700 clamp(3rem, 8vw, 6rem)/.96 Georgia, serif; }
        .subtitle { color: var(--muted); font-size: 1.3rem; }
        @media (prefers-color-scheme: dark) {
          :root { --ink: #f3f5fa; --muted: #a8adbd; --canvas: #080b16; }
        }
        """
    }

    private static func legacyBlocks(for site: SiteProject) -> [SiteBlock] {
        [
            SiteBlock(
                id: UUID(),
                kind: .hero,
                eyebrow: "Noctweb publication",
                heading: site.title,
                body: site.subtitle,
                buttonLabel: "Read more",
                buttonURL: "#content"
            ),
            SiteBlock(
                id: UUID(),
                kind: .text,
                eyebrow: "",
                heading: "About",
                body: site.body,
                buttonLabel: "",
                buttonURL: ""
            ),
        ]
    }

    private static func normalizedRelativePath(
        _ filePath: String,
        rootPath: String
    ) -> String {
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return filePath.hasPrefix(prefix)
            ? String(filePath.dropFirst(prefix.count))
            : URL(fileURLWithPath: filePath).lastPathComponent
    }

    private static func readBoundedRegularFile(
        at fileURL: URL,
        relativePath: String,
        maximumBytes: Int,
        existingBytes: Int
    ) throws -> Data {
        let descriptor = fileURL.withUnsafeFileSystemRepresentation {
            path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(
                path,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW
            )
        }
        let openError = errno
        guard descriptor >= 0 else {
            if openError == ELOOP {
                throw WebsiteProjectBuilderError.symbolicLink(relativePath)
            }
            throw WebsiteProjectBuilderError.unreadableFile(relativePath)
        }
        defer { Darwin.close(descriptor) }

        var metadata = stat()
        guard
            Darwin.fstat(descriptor, &metadata) == 0,
            (metadata.st_mode & S_IFMT) == S_IFREG,
            metadata.st_size >= 0
        else {
            throw WebsiteProjectBuilderError.unreadableFile(relativePath)
        }

        let openedSize = Int(metadata.st_size)
        guard openedSize <= maximumBytes else {
            throw WebsiteProjectBuilderError.bundleTooLarge(
                existingBytes + openedSize
            )
        }

        var data = Data()
        data.reserveCapacity(openedSize)
        var buffer = [UInt8](
            repeating: 0,
            count: max(1, min(64 * 1_024, maximumBytes + 1))
        )

        while true {
            let readCount = buffer.withUnsafeMutableBytes { storage in
                Darwin.read(
                    descriptor,
                    storage.baseAddress,
                    storage.count
                )
            }
            if readCount == 0 {
                break
            }
            if readCount < 0 {
                if errno == EINTR {
                    continue
                }
                throw WebsiteProjectBuilderError.unreadableFile(relativePath)
            }
            guard data.count <= maximumBytes - readCount else {
                throw WebsiteProjectBuilderError.bundleTooLarge(
                    existingBytes + data.count + readCount
                )
            }
            data.append(contentsOf: buffer.prefix(readCount))
        }
        return data
    }

    private static func mediaType(for url: URL) -> String {
        let extensionName = url.pathExtension.lowercased()
        if extensionName == "js" || extensionName == "mjs" {
            return "text/javascript"
        }
        if extensionName == "svg" {
            return "image/svg+xml"
        }
        if
            let type = UTType(filenameExtension: extensionName),
            let mime = type.preferredMIMEType
        {
            return mime
        }
        return "application/octet-stream"
    }

    private static func renderHTML(
        site: SiteProject,
        blocks: [SiteBlock]
    ) -> String {
        let renderedBlocks = blocks.map(renderBlock).joined(separator: "\n")
        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="description" content="\(escapeAttribute(site.subtitle))">
          <title>\(escapeHTML(site.title))</title>
          <link rel="stylesheet" href="/styles.css">
          <script type="module" src="/app.js"></script>
        </head>
        <body>
          <header class="site-header">
            <a class="brand" href="/">\(escapeHTML(site.title))</a>
            <span class="network-mark">Noctweave website</span>
          </header>
          <main id="content">
        \(renderedBlocks)
          </main>
          <footer class="site-footer">
            <span>\(escapeHTML(site.title))</span>
            <span>Verified static website</span>
          </footer>
        </body>
        </html>
        """
    }

    private static func renderBlock(_ block: SiteBlock) -> String {
        let id = block.id.uuidString.lowercased()
        let eyebrow = block.eyebrow.isEmpty
            ? ""
            : "<p class=\"eyebrow\">\(escapeHTML(block.eyebrow))</p>"
        let button = block.buttonLabel.isEmpty
            ? ""
            : """
              <a class="button" href="\(escapeAttribute(block.buttonURL))">\(escapeHTML(block.buttonLabel))</a>
            """
        let body = paragraphHTML(block.body)
        switch block.kind {
        case .hero:
            return """
              <section class="block hero" data-noctweb-block="\(id)">
                <div class="hero-copy">
                  \(eyebrow)
                  <h1>\(escapeHTML(block.heading))</h1>
                  <div class="lede">\(body)</div>
                  \(button)
                </div>
                <div class="hero-art" aria-hidden="true"><span></span><span></span><span></span></div>
              </section>
            """
        case .text:
            return """
              <section class="block prose" data-noctweb-block="\(id)">
                \(eyebrow)
                <h2>\(escapeHTML(block.heading))</h2>
                \(body)
                \(button)
              </section>
            """
        case .feature:
            return """
              <section class="block feature" data-noctweb-block="\(id)">
                <div class="feature-icon">✦</div>
                <div>
                  \(eyebrow)
                  <h2>\(escapeHTML(block.heading))</h2>
                  \(body)
                </div>
              </section>
            """
        case .callToAction:
            return """
              <section class="block callout" data-noctweb-block="\(id)">
                <div>
                  \(eyebrow)
                  <h2>\(escapeHTML(block.heading))</h2>
                  \(body)
                </div>
                \(button)
              </section>
            """
        }
    }

    private static func paragraphHTML(_ value: String) -> String {
        value
            .components(separatedBy: "\n\n")
            .map {
                "<p>\(escapeHTML($0).replacingOccurrences(of: "\n", with: "<br>"))</p>"
            }
            .joined(separator: "\n")
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func escapeAttribute(_ value: String) -> String {
        escapeHTML(value)
    }

    private static func renderCSS(accentHex: String) -> String {
        """
        :root {
          color-scheme: light dark;
          --accent: \(accentHex);
          --wine: #922d35;
          --coral: #a84f4b;
          --sand: #9c6b55;
          --canvas: #faf6f2;
          --ink: #25191e;
          --muted: #765f64;
          --paper: var(--canvas);
          --card: rgba(255,255,255,.82);
          font-family: Inter, ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        }
        * { box-sizing: border-box; }
        html { scroll-behavior: smooth; }
        body { margin: 0; color: var(--ink); background: var(--paper); line-height: 1.6; }
        .site-header, .site-footer {
          display: flex; align-items: center; justify-content: space-between; gap: 1rem;
          max-width: 1120px; margin: auto; padding: 1.25rem 2rem;
        }
        .brand { color: inherit; font-weight: 750; text-decoration: none; }
        .network-mark, .site-footer { color: var(--muted); font-size: .82rem; }
        main { overflow: hidden; }
        .block { max-width: 1120px; margin: 0 auto; padding: clamp(3.5rem, 8vw, 7rem) 2rem; }
        .hero { min-height: 72vh; display: grid; grid-template-columns: 1.2fr .8fr; align-items: center; gap: 4rem; }
        .hero h1 { font-family: ui-serif, Georgia, serif; font-size: clamp(3rem, 7vw, 6.8rem); line-height: .96; letter-spacing: -.055em; margin: .2em 0; }
        .lede { color: var(--muted); font-size: clamp(1.08rem, 2vw, 1.35rem); max-width: 42rem; }
        .eyebrow { color: var(--accent); font-size: .75rem; font-weight: 800; letter-spacing: .13em; text-transform: uppercase; }
        .button { display: inline-block; margin-top: 1.25rem; padding: .8rem 1.1rem; border-radius: 999px; background: var(--accent); color: white; text-decoration: none; font-weight: 700; }
        .hero-art { position: relative; aspect-ratio: 1; }
        .hero-art span { position: absolute; inset: 10%; border: 1px solid color-mix(in srgb, var(--accent), transparent 45%); border-radius: 40% 60% 55% 45%; animation: orbit 16s linear infinite; }
        .hero-art span:nth-child(2) { inset: 24%; animation-direction: reverse; animation-duration: 11s; }
        .hero-art span:nth-child(3) { inset: 38%; background: var(--accent); opacity: .18; }
        .prose { max-width: 820px; }
        .prose h2, .feature h2, .callout h2 { font-size: clamp(2rem, 4vw, 3.4rem); line-height: 1.08; margin: .2em 0 .6em; }
        .prose p, .feature p, .callout p { color: var(--muted); font-size: 1.08rem; }
        .feature { display: grid; grid-template-columns: auto 1fr; gap: 1.4rem; background: var(--card); border: 1px solid rgba(120,130,126,.2); border-radius: 1.5rem; padding: 2rem; margin-block: 3rem; }
        .feature-icon { color: var(--accent); font-size: 2rem; }
        .callout { display: flex; align-items: center; justify-content: space-between; gap: 2rem; background: var(--ink); color: white; border-radius: 1.5rem; padding: clamp(2rem, 5vw, 4rem); margin-block: 4rem; }
        .callout p { color: rgba(255,255,255,.72); }
        .site-footer { border-top: 1px solid rgba(120,130,126,.22); }
        [data-reveal] { opacity: 0; transform: translateY(18px); transition: .55s ease; }
        [data-reveal].visible { opacity: 1; transform: none; }
        @keyframes orbit { to { transform: rotate(360deg); } }
        @media (max-width: 720px) {
          .hero { grid-template-columns: 1fr; min-height: auto; }
          .hero-art { max-width: 24rem; width: 80%; }
          .callout { align-items: flex-start; flex-direction: column; }
          .site-header, .site-footer { padding-inline: 1.25rem; }
          .block { padding-inline: 1.25rem; }
        }
        @media (prefers-color-scheme: dark) {
          :root { --wine: #b55250; --coral: #c96a61; --sand: #ebc7af; --ink: #faf3ea; --muted: #bda9aa; --paper: #120b0f; --card: rgba(255,255,255,.07); }
          .callout { background: #faf3ea; color: #1b1217; }
          .callout p { color: #765f64; }
        }
        """
    }

    private static let defaultJavaScript = """
    document.querySelectorAll('.block').forEach((element) => {
      element.dataset.reveal = '';
    });
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) entry.target.classList.add('visible');
      });
    }, { threshold: 0.12 });
    document.querySelectorAll('[data-reveal]').forEach((element) => observer.observe(element));
    """
}
