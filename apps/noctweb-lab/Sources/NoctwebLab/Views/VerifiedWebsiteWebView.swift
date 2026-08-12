import Foundation
import NoctwebLabCore
import SwiftUI
import WebKit

/// A native shell around a publication-scoped WebKit renderer.
///
/// The renderer only knows how to load files from the verified `WebsiteBundle`.
/// It deliberately exposes no script-message handlers or other native bridge.
struct VerifiedWebsiteWebView: View {
    let bundle: WebsiteBundle
    let origin: String
    let reloadToken: UUID

    var body: some View {
        switch BundleSnapshot.validation(bundle: bundle, origin: origin) {
        case .valid:
            VerifiedWebsiteRepresentable(
                bundle: bundle,
                origin: origin,
                reloadToken: reloadToken
            )
            .id(origin)
        case .invalidOrigin:
            ContentUnavailableView(
                "Publisher identity unavailable",
                systemImage: "person.crop.circle.badge.exclamationmark",
                description: Text("A verified publisher identity is required before this website can run.")
            )
        case .invalidBundle:
            ContentUnavailableView(
                "Website bundle rejected",
                systemImage: "exclamationmark.shield",
                description: Text(
                    "The website contains a noncanonical path, media type, entry point, or size."
                )
            )
        case .missingEntryPoint(let entryPath):
            ContentUnavailableView(
                "Website entry point unavailable",
                systemImage: "doc.badge.ellipsis",
                description: Text("The verified bundle does not contain \(entryPath).")
            )
        }
    }
}

/// The reusable `NSViewRepresentable` boundary around `WKWebView`.
///
/// Keep this type free of script-message handlers: a website must not gain
/// ambient access to the native app merely by being rendered.
private struct VerifiedWebsiteRepresentable: NSViewRepresentable {
    let bundle: WebsiteBundle
    let origin: String
    let reloadToken: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(bundle: bundle, origin: origin)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: BundleSnapshot.networkIsolationScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        configuration.setURLSchemeHandler(
            context.coordinator.schemeHandler,
            forURLScheme: BundleSnapshot.scheme
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsMagnification = true

        context.coordinator.load(
            bundle: bundle,
            origin: origin,
            reloadToken: reloadToken,
            in: webView,
            force: true
        )
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(
            bundle: bundle,
            origin: origin,
            reloadToken: reloadToken,
            in: webView,
            force: false
        )
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        fileprivate let schemeHandler: PublicationSchemeHandler

        private var currentHost: String
        private var lastReloadToken: UUID?

        init(bundle: WebsiteBundle, origin: String) {
            let snapshot = BundleSnapshot(bundle: bundle, origin: origin)
            schemeHandler = PublicationSchemeHandler(snapshot: snapshot)
            currentHost = snapshot.host
            super.init()
        }

        func load(
            bundle: WebsiteBundle,
            origin: String,
            reloadToken: UUID,
            in webView: WKWebView,
            force: Bool
        ) {
            let snapshot = BundleSnapshot(bundle: bundle, origin: origin)
            let originChanged = snapshot.host != currentHost
            schemeHandler.replace(with: snapshot)
            currentHost = snapshot.host

            guard force || originChanged || reloadToken != lastReloadToken else {
                return
            }

            lastReloadToken = reloadToken
            webView.load(
                URLRequest(
                    url: snapshot.rootURL,
                    cachePolicy: .reloadIgnoringLocalCacheData
                )
            )
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else {
                return .cancel
            }

            if BundleSnapshot.isInternalURL(url, expectedHost: currentHost) {
                return .allow
            }

            if url.scheme == "about", url.absoluteString == "about:blank" {
                return .allow
            }

            if navigationAction.targetFrame?.isMainFrame != false {
                showBlockedNavigation(url, in: webView)
            }
            return .cancel
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard let url = navigationAction.request.url else {
                return nil
            }

            if BundleSnapshot.isInternalURL(url, expectedHost: currentHost) {
                webView.load(navigationAction.request)
            } else {
                showBlockedNavigation(url, in: webView)
            }
            return nil
        }

        private func showBlockedNavigation(_ url: URL, in webView: WKWebView) {
            let escapedURL = BundleSnapshot.escapeHTML(url.absoluteString)
            webView.loadHTMLString(
                """
                <!doctype html>
                <html lang="en">
                <head>
                  <meta charset="utf-8">
                  <meta name="viewport" content="width=device-width, initial-scale=1">
                  <style>
                    :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
                    body { min-height: 100vh; margin: 0; display: grid; place-items: center; background: Canvas; color: CanvasText; }
                    main { max-width: 34rem; padding: 2rem; text-align: center; }
                    h1 { font-size: 1.3rem; margin: 0 0 .75rem; }
                    p { color: GrayText; line-height: 1.5; overflow-wrap: anywhere; }
                  </style>
                </head>
                <body>
                  <main>
                    <h1>External navigation blocked</h1>
                    <p>This verified preview cannot open network resources.</p>
                    <p>\(escapedURL)</p>
                  </main>
                </body>
                </html>
                """,
                baseURL: nil
            )
        }
    }
}

final class PublicationSchemeHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: BundleSnapshot

    init(snapshot: BundleSnapshot) {
        self.snapshot = snapshot
    }

    func replace(with snapshot: BundleSnapshot) {
        lock.lock()
        self.snapshot = snapshot
        lock.unlock()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        lock.lock()
        let snapshot = snapshot
        lock.unlock()

        guard let url = urlSchemeTask.request.url,
              BundleSnapshot.isInternalURL(url, expectedHost: snapshot.host)
        else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
            return
        }

        let requestedPath: String
        guard let normalizedPath = BundleSnapshot.normalizePath(url.path) else {
            respond(
                to: urlSchemeTask,
                url: url,
                statusCode: 400,
                resource: .errorPage(
                    title: "Invalid website path",
                    message: "The requested path is not valid inside this publication."
                )
            )
            return
        }

        if normalizedPath.isEmpty {
            requestedPath = snapshot.entryPath
        } else if snapshot.files[normalizedPath] != nil {
            requestedPath = normalizedPath
        } else if BundleSnapshot.isSPARoute(normalizedPath) {
            requestedPath = snapshot.entryPath
        } else {
            respond(
                to: urlSchemeTask,
                url: url,
                statusCode: 404,
                resource: .errorPage(
                    title: "Website file not found",
                    message: "/\(normalizedPath) is not part of the verified bundle."
                )
            )
            return
        }

        guard let resource = snapshot.files[requestedPath] else {
            respond(
                to: urlSchemeTask,
                url: url,
                statusCode: 404,
                resource: .errorPage(
                    title: "Entry point unavailable",
                    message: "\(snapshot.entryPath) is not part of the verified bundle."
                )
            )
            return
        }

        respond(
            to: urlSchemeTask,
            url: url,
            statusCode: 200,
            resource: resource
        )
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        // Responses are delivered synchronously; there is no outstanding work to cancel.
    }

    private func respond(
        to task: any WKURLSchemeTask,
        url: URL,
        statusCode: Int,
        resource: BundleResource
    ) {
        let headers = [
            "Content-Type": resource.mediaType,
            "Content-Security-Policy": BundleSnapshot.contentSecurityPolicy,
            "Cross-Origin-Resource-Policy": "same-origin",
            "Referrer-Policy": "no-referrer",
            "X-Content-Type-Options": "nosniff",
            "Cache-Control": "no-store"
        ]

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            task.didFailWithError(URLError(.cannotParseResponse))
            return
        }

        task.didReceive(response)
        task.didReceive(resource.data)
        task.didFinish()
    }
}

struct BundleSnapshot: @unchecked Sendable {
    enum Validation {
        case valid
        case invalidOrigin
        case invalidBundle
        case missingEntryPoint(String)
    }

    static let scheme = "noctweb-site"
    static let contentSecurityPolicy = [
        "default-src 'self' data: blob:",
        "base-uri 'self'",
        "object-src 'none'",
        "script-src 'self' 'unsafe-inline' 'unsafe-eval' 'wasm-unsafe-eval' blob:",
        "style-src 'self' 'unsafe-inline'",
        "img-src 'self' data: blob:",
        "font-src 'self' data:",
        "media-src 'self' data: blob:",
        "connect-src 'self' data: blob:",
        "webrtc 'block'",
        "worker-src 'self' blob:",
        "child-src 'self' blob:",
        "frame-src 'self'",
        "form-action 'self'",
        "manifest-src 'self'"
    ].joined(separator: "; ")

    static let networkIsolationScript = """
    (() => {
      'use strict';
      class BlockedPeerConnection {
        constructor() {
          throw new DOMException(
            'External network access is disabled in verified Noctweb websites.',
            'SecurityError'
          );
        }
      }
      for (const name of ['RTCPeerConnection', 'webkitRTCPeerConnection']) {
        try {
          Object.defineProperty(globalThis, name, {
            value: BlockedPeerConnection,
            writable: false,
            configurable: false
          });
        } catch (_) {}
      }
    })();
    """

    let host: String
    let entryPath: String
    let files: [String: BundleResource]
    let isValidBundle: Bool

    init(bundle: WebsiteBundle, origin: String) {
        host = Self.host(for: origin)
        guard let canonicalBundle = try? bundle.canonicalized() else {
            entryPath = ""
            files = [:]
            isValidBundle = false
            return
        }
        entryPath = Self.normalizePath(canonicalBundle.entryPath) ?? ""

        var resources: [String: BundleResource] = [:]
        for file in canonicalBundle.files {
            guard let path = Self.normalizePath(file.path), !path.isEmpty else {
                continue
            }
            resources[path] = BundleResource(
                data: Data(file.bytes),
                mediaType: Self.safeMediaType(file.mediaType)
            )
        }
        files = resources
        isValidBundle =
            resources.count == canonicalBundle.files.count &&
            resources[entryPath] != nil
    }

    var rootURL: URL {
        URL(string: "\(Self.scheme)://\(host)/")!
    }

    static func validation(bundle: WebsiteBundle, origin: String) -> Validation {
        guard !origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .invalidOrigin
        }

        let snapshot = BundleSnapshot(bundle: bundle, origin: origin)
        guard snapshot.isValidBundle else {
            return .invalidBundle
        }
        guard !snapshot.entryPath.isEmpty,
              snapshot.files[snapshot.entryPath] != nil
        else {
            return .missingEntryPoint(bundle.entryPath)
        }
        return .valid
    }

    static func normalizePath(_ rawPath: String) -> String? {
        var candidate = rawPath
        candidate = candidate.removingPercentEncoding ?? candidate
        guard !candidate.contains("\\") else { return nil }

        var components: [Substring] = []
        for component in candidate.split(separator: "/", omittingEmptySubsequences: true) {
            if component == "." {
                continue
            }
            guard component != "..",
                  !component.unicodeScalars.contains(where: { $0.value == 0 })
            else {
                return nil
            }
            components.append(component)
        }
        return components.joined(separator: "/")
    }

    static func isSPARoute(_ path: String) -> Bool {
        guard let finalComponent = path.split(separator: "/").last else {
            return true
        }
        return !finalComponent.contains(".")
    }

    static func isInternalURL(_ url: URL, expectedHost: String) -> Bool {
        url.scheme?.lowercased() == scheme
            && url.host?.caseInsensitiveCompare(expectedHost) == .orderedSame
            && url.user == nil
            && url.password == nil
            && url.port == nil
    }

    static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func safeMediaType(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("\r"),
              !trimmed.contains("\n")
        else {
            return "application/octet-stream"
        }
        return trimmed
    }

    private static func host(for origin: String) -> String {
        let lowercase = origin.lowercased()
        let readable = lowercase.unicodeScalars.map { scalar -> Character in
            switch scalar.value {
            case 48...57, 97...122:
                return Character(String(scalar))
            default:
                return "-"
            }
        }
        let prefix = String(readable)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
            .prefix(28)

        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in origin.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }

        return "publication-\(prefix)-\(String(hash, radix: 16))"
    }
}

struct BundleResource: @unchecked Sendable {
    let data: Data
    let mediaType: String

    static func errorPage(title: String, message: String) -> BundleResource {
        let escapedTitle = BundleSnapshot.escapeHTML(title)
        let escapedMessage = BundleSnapshot.escapeHTML(message)
        let html = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
            body { min-height: 100vh; margin: 0; display: grid; place-items: center; background: Canvas; color: CanvasText; }
            main { max-width: 34rem; padding: 2rem; text-align: center; }
            h1 { font-size: 1.3rem; margin: 0 0 .75rem; }
            p { color: GrayText; line-height: 1.5; overflow-wrap: anywhere; }
          </style>
        </head>
        <body><main><h1>\(escapedTitle)</h1><p>\(escapedMessage)</p></main></body>
        </html>
        """
        return BundleResource(
            data: Data(html.utf8),
            mediaType: "text/html; charset=utf-8"
        )
    }
}
