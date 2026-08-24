import Foundation
import NoctwebLabCore
import WebKit
import XCTest

@testable import NoctwebLab

@MainActor
final class VerifiedWebsiteWebViewTests: XCTestCase {
    func testRendererDisablesSpeculativeDNSAndPrefetch() {
        XCTAssertTrue(
            BundleSnapshot.contentSecurityPolicy.contains(
                "prefetch-src 'none'"
            )
        )
        let source = try? String(
            contentsOfFile: #filePath
                .components(separatedBy: "/Tests/")[0]
                + "/Sources/NoctwebLab/Views/VerifiedWebsiteWebView.swift",
            encoding: .utf8
        )
        XCTAssertTrue(source?.contains("X-DNS-Prefetch-Control") == true)
    }

    func testInternalRendererURLRejectsAuthorityVariantsAndBackslashes() throws {
        let host = "publication-test"
        XCTAssertTrue(BundleSnapshot.isInternalURL(
            try XCTUnwrap(URL(string: "noctweb-site://\(host)/index.html")),
            expectedHost: host
        ))
        for value in [
            "noctweb-site://user@\(host)/index.html",
            "noctweb-site://\(host):443/index.html",
            "noctweb-site://other/index.html",
        ] {
            XCTAssertFalse(BundleSnapshot.isInternalURL(
                try XCTUnwrap(URL(string: value)),
                expectedHost: host
            ))
        }
        XCTAssertNil(BundleSnapshot.normalizePath("/assets%5csecret.js"))
    }

    func testProductionModuleBundleExecutesInsideVerifiedRuntime() async throws {
        let bundle = WebsiteBundle(
            entryPath: "index.html",
            files: [
                WebsiteFile(
                    path: "index.html",
                    mediaType: "text/html",
                    bytes: Data(
                        """
                        <!doctype html>
                        <html>
                        <head>
                          <meta charset="utf-8">
                          <link rel="stylesheet" href="/assets/site.css">
                        </head>
                        <body>
                          <h1 id="result">Starting</h1>
                          <p id="same-origin">Pending</p>
                          <p id="external">Pending</p>
                          <script type="module" src="/assets/main.js"></script>
                        </body>
                        </html>
                        """.utf8
                    )
                ),
                WebsiteFile(
                    path: "assets/site.css",
                    mediaType: "text/css",
                    bytes: Data("body{background:rgb(18,35,29)}".utf8)
                ),
                WebsiteFile(
                    path: "assets/main.js",
                    mediaType: "text/javascript",
                    bytes: Data(
                        """
                        import { label } from "./vendor.js";
                        const lazy = await import("./lazy.js");
                        document.querySelector("#result").textContent =
                          `${label} · ${lazy.default}`;

                        try {
                          const response = await fetch("/assets/message.json");
                          const payload = await response.json();
                          document.querySelector("#same-origin").textContent =
                            `Same-publication fetch: ${payload.message}`;
                        } catch (error) {
                          document.querySelector("#same-origin").textContent =
                            `Same-publication fetch failed: ${error.name}`;
                        }

                        try {
                          await fetch("https://example.com/noctweb-network-probe");
                          document.querySelector("#external").textContent =
                            "External fetch unexpectedly succeeded";
                        } catch (_) {
                          document.querySelector("#external").textContent =
                            "External fetch blocked";
                        }
                        """.utf8
                    )
                ),
                WebsiteFile(
                    path: "assets/vendor.js",
                    mediaType: "text/javascript",
                    bytes: Data(
                        "export const label='Module bundle executed';".utf8
                    )
                ),
                WebsiteFile(
                    path: "assets/lazy.js",
                    mediaType: "text/javascript",
                    bytes: Data(
                        "export default 'dynamic chunk loaded';".utf8
                    )
                ),
                WebsiteFile(
                    path: "assets/message.json",
                    mediaType: "application/json",
                    bytes: Data(
                        #"{"message":"verified asset loaded"}"#.utf8
                    )
                ),
            ]
        )
        let snapshot = BundleSnapshot(
            bundle: bundle,
            origin: "nwpub1_test-runtime"
        )
        XCTAssertTrue(snapshot.isValidBundle)

        let schemeHandler = PublicationSchemeHandler(snapshot: snapshot)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: BundleSnapshot.networkIsolationScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        configuration.setURLSchemeHandler(
            schemeHandler,
            forURLScheme: BundleSnapshot.scheme
        )

        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 800, height: 600),
                                configuration: configuration)
        let navigationObserver = NavigationObserver()
        webView.navigationDelegate = navigationObserver
        navigationObserver.prepareForNavigation()
        webView.load(URLRequest(url: snapshot.rootURL))
        try await navigationObserver.waitForNavigation()

        var bodyText = ""
        var backgroundColor = ""
        for _ in 0..<120 {
            if let value = try await boundedJavaScriptString(
                "document.body?.innerText ?? ''",
                in: webView
            ) {
                bodyText = value
            }
            if let value = try await boundedJavaScriptString(
                "getComputedStyle(document.body).backgroundColor",
                in: webView
            ) {
                backgroundColor = value
            }
            if
                bodyText.contains("dynamic chunk loaded"),
                bodyText.contains("verified asset loaded"),
                bodyText.contains("External fetch blocked")
            {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertTrue(
            bodyText.contains("Module bundle executed · dynamic chunk loaded"),
            bodyText
        )
        XCTAssertTrue(
            bodyText.contains("Same-publication fetch: verified asset loaded"),
            bodyText
        )
        XCTAssertTrue(
            bodyText.contains("External fetch blocked"),
            bodyText
        )
        XCTAssertEqual(backgroundColor, "rgb(18, 35, 29)")

        let rtcResult = try await boundedJavaScriptString(
            """
            (() => {
              try {
                new RTCPeerConnection();
                return "unexpected";
              } catch (_) {
                return "blocked";
              }
            })()
            """,
            in: webView,
            ignoresJavaScriptErrors: false
        )
        XCTAssertEqual(rtcResult, "blocked")

        let routeURL = snapshot.rootURL.appendingPathComponent("dashboard")
        navigationObserver.prepareForNavigation()
        webView.load(URLRequest(url: routeURL))
        try await navigationObserver.waitForNavigation()
        var routedBodyText = ""
        for _ in 0..<120 {
            if let value = try await boundedJavaScriptString(
                "document.body?.innerText ?? ''",
                in: webView
            ) {
                routedBodyText = value
            }
            if routedBodyText.contains("dynamic chunk loaded") {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(
            routedBodyText.contains(
                "Module bundle executed · dynamic chunk loaded"
            ),
            routedBodyText
        )
    }

    private enum RendererTestError: Error, Sendable {
        case javaScriptTimedOut
        case javaScriptFailed(String)
        case navigationTimedOut
        case navigationFailed(String)
    }

    @MainActor
    private final class CompletionGate<Value: Sendable> {
        private var continuation: CheckedContinuation<Value, Error>?
        private var pendingResult: Result<Value, Error>?
        private var timeoutTask: Task<Void, Never>?
        private var isComplete = false

        func wait(
            timeout: Duration,
            timeoutError: RendererTestError
        ) async throws -> Value {
            if let pendingResult {
                return try pendingResult.get()
            }

            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                timeoutTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }
                    self?.resolve(.failure(timeoutError))
                }
            }
        }

        func resolve(_ result: Result<Value, Error>) {
            guard !isComplete else { return }
            isComplete = true
            timeoutTask?.cancel()
            timeoutTask = nil

            if let continuation {
                self.continuation = nil
                continuation.resume(with: result)
            } else {
                pendingResult = result
            }
        }
    }

    @MainActor
    private final class NavigationObserver: NSObject, WKNavigationDelegate {
        private var gate = CompletionGate<Void>()

        func prepareForNavigation() {
            gate = CompletionGate<Void>()
        }

        func waitForNavigation() async throws {
            try await gate.wait(
                timeout: .seconds(10),
                timeoutError: .navigationTimedOut
            )
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            gate.resolve(.success(()))
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            gate.resolve(.failure(
                RendererTestError.navigationFailed(error.localizedDescription)
            ))
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            gate.resolve(.failure(
                RendererTestError.navigationFailed(error.localizedDescription)
            ))
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            gate.resolve(.failure(
                RendererTestError.navigationFailed("Web content process terminated")
            ))
        }
    }

    private func boundedJavaScriptString(
        _ source: String,
        in webView: WKWebView,
        timeout: Duration = .seconds(5),
        ignoresJavaScriptErrors: Bool = true
    ) async throws -> String? {
        let gate = CompletionGate<String?>()
        let evaluationTask = Task { @MainActor [weak webView, weak gate] in
            guard let webView, let gate else { return }
            do {
                let value = try await webView.evaluateJavaScript(source) as? String
                gate.resolve(.success(value))
            } catch {
                if ignoresJavaScriptErrors {
                    gate.resolve(.success(nil))
                } else {
                    gate.resolve(.failure(
                        RendererTestError.javaScriptFailed(error.localizedDescription)
                    ))
                }
            }
        }
        defer { evaluationTask.cancel() }
        return try await gate.wait(
            timeout: timeout,
            timeoutError: .javaScriptTimedOut
        )
    }
}
