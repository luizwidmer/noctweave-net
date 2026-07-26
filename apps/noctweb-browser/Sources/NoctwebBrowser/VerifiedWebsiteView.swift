import CryptoKit
import Foundation
import NoctwebBrowserCore
import SwiftUI
import WebKit

struct VerifiedNoctwebWebsiteView: View {
    let site: VerifiedNoctwebSite
    let reloadToken: UUID
    let onNoctNavigation: (URL) -> Void
    let onInternalNavigation: (URL) -> Void
    let onBlockedNavigation: (URL) -> Void

    var body: some View {
        VerifiedNoctwebWebsiteRepresentable(
            site: site,
            reloadToken: reloadToken,
            onNoctNavigation: onNoctNavigation,
            onInternalNavigation: onInternalNavigation,
            onBlockedNavigation: onBlockedNavigation
        )
        .id(site.evidence.publisherID + site.evidence.headID)
    }
}

private struct VerifiedNoctwebWebsiteRepresentable: NSViewRepresentable {
    let site: VerifiedNoctwebSite
    let reloadToken: UUID
    let onNoctNavigation: (URL) -> Void
    let onInternalNavigation: (URL) -> Void
    let onBlockedNavigation: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            site: site,
            onNoctNavigation: onNoctNavigation,
            onInternalNavigation: onInternalNavigation,
            onBlockedNavigation: onBlockedNavigation
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: NoctwebRendererSnapshot.networkIsolationScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        configuration.setURLSchemeHandler(
            context.coordinator.schemeHandler,
            forURLScheme: NoctwebRendererSnapshot.scheme
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = false

        context.coordinator.load(
            site: site,
            reloadToken: reloadToken,
            in: webView,
            force: true
        )
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onNoctNavigation = onNoctNavigation
        context.coordinator.onInternalNavigation = onInternalNavigation
        context.coordinator.onBlockedNavigation = onBlockedNavigation
        context.coordinator.load(
            site: site,
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
        fileprivate let schemeHandler: NoctwebPublicationSchemeHandler
        fileprivate var onNoctNavigation: (URL) -> Void
        fileprivate var onInternalNavigation: (URL) -> Void
        fileprivate var onBlockedNavigation: (URL) -> Void

        private var currentHost: String
        private var lastReloadToken: UUID?
        private var URLObservation: NSKeyValueObservation?

        init(
            site: VerifiedNoctwebSite,
            onNoctNavigation: @escaping (URL) -> Void,
            onInternalNavigation: @escaping (URL) -> Void,
            onBlockedNavigation: @escaping (URL) -> Void
        ) {
            let snapshot = NoctwebRendererSnapshot(site: site)
            schemeHandler = NoctwebPublicationSchemeHandler(snapshot: snapshot)
            currentHost = snapshot.host
            self.onNoctNavigation = onNoctNavigation
            self.onInternalNavigation = onInternalNavigation
            self.onBlockedNavigation = onBlockedNavigation
            super.init()
        }

        func load(
            site: VerifiedNoctwebSite,
            reloadToken: UUID,
            in webView: WKWebView,
            force: Bool
        ) {
            let snapshot = NoctwebRendererSnapshot(site: site)
            let publicationChanged = snapshot.host != currentHost
            schemeHandler.replace(with: snapshot)
            currentHost = snapshot.host

            guard force || publicationChanged || reloadToken != lastReloadToken else {
                return
            }
            lastReloadToken = reloadToken
            if URLObservation == nil {
                URLObservation = webView.observe(
                    \.url,
                    options: [.new]
                ) { [weak self] _, change in
                    guard let url = change.newValue ?? nil else { return }
                    Task { @MainActor [weak self] in
                        guard
                            let self,
                            NoctwebRendererSnapshot.isInternalURL(
                                url,
                                expectedHost: self.currentHost
                            )
                        else {
                            return
                        }
                        self.onInternalNavigation(url)
                    }
                }
            }
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
            if NoctwebRendererSnapshot.isInternalURL(
                url,
                expectedHost: currentHost
            ) {
                return .allow
            }
            if url.scheme?.lowercased() == "noct" {
                guard
                    navigationAction.targetFrame?.isMainFrame == true,
                    navigationAction.sourceFrame.isMainFrame,
                    navigationAction.navigationType == .linkActivated
                else {
                    return .cancel
                }
                onNoctNavigation(url)
                return .cancel
            }
            if url.absoluteString == "about:blank",
               navigationAction.targetFrame?.isMainFrame == false {
                return .allow
            }
            if navigationAction.targetFrame?.isMainFrame != false {
                onBlockedNavigation(url)
            }
            return .cancel
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard let url = navigationAction.request.url else { return nil }
            if url.scheme?.lowercased() == "noct",
               navigationAction.sourceFrame.isMainFrame,
               navigationAction.navigationType == .linkActivated {
                onNoctNavigation(url)
            } else if NoctwebRendererSnapshot.isInternalURL(
                url,
                expectedHost: currentHost
            ),
                navigationAction.sourceFrame.isMainFrame,
                navigationAction.navigationType == .linkActivated {
                webView.load(navigationAction.request)
            } else if navigationAction.sourceFrame.isMainFrame,
                      navigationAction.navigationType == .linkActivated {
                onBlockedNavigation(url)
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
            initiatedBy frame: WKFrameInfo,
            type: WKMediaCaptureType
        ) async -> WKPermissionDecision {
            .deny
        }
    }
}

final class NoctwebPublicationSchemeHandler:
    NSObject,
    WKURLSchemeHandler,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var snapshot: NoctwebRendererSnapshot

    init(snapshot: NoctwebRendererSnapshot) {
        self.snapshot = snapshot
    }

    func replace(with snapshot: NoctwebRendererSnapshot) {
        lock.lock()
        self.snapshot = snapshot
        lock.unlock()
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        lock.lock()
        let snapshot = snapshot
        lock.unlock()

        guard
            let url = task.request.url,
            NoctwebRendererSnapshot.isInternalURL(
                url,
                expectedHost: snapshot.host
            )
        else {
            task.didFailWithError(URLError(.unsupportedURL))
            return
        }
        guard let normalizedPath = NoctwebRendererSnapshot.normalizePath(
            url.path
        ) else {
            respond(
                to: task,
                url: url,
                statusCode: 400,
                resource: .errorPage(
                    title: "Invalid website path",
                    message: "The requested path is not valid inside this publication."
                )
            )
            return
        }

        let requestedPath: String
        if normalizedPath.isEmpty {
            requestedPath = snapshot.entryPath
        } else if snapshot.files[normalizedPath] != nil {
            requestedPath = normalizedPath
        } else if NoctwebRendererSnapshot.isSPARoute(normalizedPath) {
            requestedPath = snapshot.entryPath
        } else {
            respond(
                to: task,
                url: url,
                statusCode: 404,
                resource: .errorPage(
                    title: "Website file not found",
                    message: "/\(normalizedPath) is not part of the verified publication."
                )
            )
            return
        }
        guard let resource = snapshot.files[requestedPath] else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        respond(to: task, url: url, statusCode: 200, resource: resource)
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        // Resources are returned synchronously, so there is nothing to cancel.
    }

    private func respond(
        to task: any WKURLSchemeTask,
        url: URL,
        statusCode: Int,
        resource: NoctwebBundleResource
    ) {
        let headers = [
            "Content-Type": resource.mediaType,
            "Content-Security-Policy":
                NoctwebRendererSnapshot.contentSecurityPolicy,
            "Cross-Origin-Resource-Policy": "same-origin",
            "Permissions-Policy":
                "camera=(), microphone=(), geolocation=(), payment=(), usb=()",
            "Referrer-Policy": "no-referrer",
            "X-Content-Type-Options": "nosniff",
            "X-DNS-Prefetch-Control": "off",
            "Cache-Control": "no-store",
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

struct NoctwebRendererSnapshot: @unchecked Sendable {
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
        "prefetch-src 'none'",
        "webrtc 'block'",
        "worker-src 'self' blob:",
        "child-src 'self' blob:",
        "frame-src 'self'",
        "form-action 'self'",
        "manifest-src 'self'",
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
    let rootURL: URL
    let entryPath: String
    let files: [String: NoctwebBundleResource]

    init(site: VerifiedNoctwebSite) {
        var originMaterial = Data(site.evidence.publisherID.utf8)
        originMaterial.append(0)
        originMaterial.append(Data(site.evidence.headID.utf8))
        originMaterial.append(0)
        originMaterial.append(Data(site.evidence.objectID.utf8))
        let digest = SHA256.hash(data: originMaterial)
            .prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
        host = "publication-\(digest)"
        entryPath = site.bundle.entryPath
        files = Dictionary(
            uniqueKeysWithValues: site.bundle.files.map {
                (
                    $0.path,
                    NoctwebBundleResource(
                        data: $0.bytes,
                        mediaType: Self.safeMediaType($0.mediaType)
                    )
                )
            }
        )
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = host
        components.percentEncodedPath = site.navigationURL.percentEncodedPath
        components.percentEncodedQuery =
            site.navigationURL.percentEncodedQuery
        components.percentEncodedFragment =
            site.navigationURL.percentEncodedFragment
        rootURL = components.url!
    }

    static func normalizePath(_ rawPath: String) -> String? {
        let candidate = rawPath.removingPercentEncoding ?? rawPath
        guard !candidate.contains("\\") else { return nil }
        var components: [Substring] = []
        for component in candidate.split(
            separator: "/",
            omittingEmptySubsequences: true
        ) {
            guard
                component != ".",
                component != "..",
                !component.unicodeScalars.contains(where: { $0.value == 0 })
            else {
                return nil
            }
            components.append(component)
        }
        return components.joined(separator: "/")
    }

    static func isSPARoute(_ path: String) -> Bool {
        guard let final = path.split(separator: "/").last else { return true }
        return !final.contains(".")
    }

    static func isInternalURL(_ url: URL, expectedHost: String) -> Bool {
        url.scheme?.lowercased() == scheme &&
            url.host?.caseInsensitiveCompare(expectedHost) == .orderedSame &&
            url.user == nil &&
            url.password == nil &&
            url.port == nil
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
        guard
            !trimmed.isEmpty,
            !trimmed.contains("\r"),
            !trimmed.contains("\n")
        else {
            return "application/octet-stream"
        }
        return trimmed
    }
}

struct NoctwebBundleResource: @unchecked Sendable {
    let data: Data
    let mediaType: String

    static func errorPage(
        title: String,
        message: String
    ) -> NoctwebBundleResource {
        let escapedTitle = NoctwebRendererSnapshot.escapeHTML(title)
        let escapedMessage = NoctwebRendererSnapshot.escapeHTML(message)
        return NoctwebBundleResource(
            data: Data(
                """
                <!doctype html>
                <html lang="en">
                <head>
                  <meta charset="utf-8">
                  <meta name="viewport" content="width=device-width,initial-scale=1">
                  <style>
                    :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
                    body { min-height: 100vh; margin: 0; display: grid; place-items: center; background: Canvas; color: CanvasText; }
                    main { max-width: 34rem; padding: 2rem; text-align: center; }
                    p { color: GrayText; line-height: 1.5; }
                  </style>
                </head>
                <body><main><h1>\(escapedTitle)</h1><p>\(escapedMessage)</p></main></body>
                </html>
                """.utf8
            ),
            mediaType: "text/html; charset=utf-8"
        )
    }
}
