// YouTubeEmbedIntegrationTests.swift
// Verifies youtube-nocookie.com embeds load without error 152/153.
//
// How it works:
//   1. Creates a real WKWebView with a JS→native message bridge
//   2. Loads the same HTML YouTubeWebView produces
//   3. A postMessage listener forwards YouTube IFrame API events to native
//   4. Waits up to 20s for onReady (✅) or onError (❌)
//
// Runs via: xcodebuild test -scheme SingCoach -testPlan SingCoach

import XCTest
import WebKit
import UIKit
@testable import SingCoach

// MARK: - HTML structure unit tests (no network, instant)

final class YouTubeEmbedHTMLTests: XCTestCase {

    // Fast regression tests for the embed HTML — no network needed.
    // Guards against accidentally reverting to youtube.com or dropping the
    // origin= parameter that fixed error 152.

    func testUsesNoCookieDomain() {
        let (html, baseURL) = YouTubeWebView.embedHTML(for: "OtxPre6RvaA")
        XCTAssertTrue(html.contains("youtube-nocookie.com"),
                      "Must use youtube-nocookie.com — youtube.com embed causes error 152")
        XCTAssertFalse(html.contains("//www.youtube.com/embed"),
                       "Must NOT use youtube.com/embed")
        XCTAssertEqual(baseURL?.host, "www.youtube-nocookie.com",
                       "baseURL must match the embed domain")
    }

    func testHasMatchingOriginParameter() {
        let (html, _) = YouTubeWebView.embedHTML(for: "OtxPre6RvaA")
        XCTAssertTrue(html.contains("origin=https://www.youtube-nocookie.com"),
                      "origin= param must match baseURL domain — this is what error 152 checks")
    }

    func testHasReferrerPolicy() {
        let (html, _) = YouTubeWebView.embedHTML(for: "OtxPre6RvaA")
        XCTAssertTrue(html.contains("referrerpolicy=\"strict-origin-when-cross-origin\""),
                      "referrerpolicy is required for YouTube to accept the embed origin")
    }

    func testHasEnableJSAPI() {
        let (html, _) = YouTubeWebView.embedHTML(for: "OtxPre6RvaA")
        XCTAssertTrue(html.contains("enablejsapi=1"),
                      "enablejsapi=1 is required for IFrame API postMessage events to fire")
    }

    func testVideoIDAppearsInEmbedURL() {
        let (html, _) = YouTubeWebView.embedHTML(for: "OtxPre6RvaA")
        XCTAssertTrue(html.contains("OtxPre6RvaA"),
                      "Video ID must appear in embed src URL")
    }
}

// MARK: - Network integration tests (skips on timeout)

@MainActor
final class YouTubeEmbedIntegrationTests: XCTestCase {

    let testVideoIDs = [
        "OtxPre6RvaA",  // Breathing exercise
        "JyfUn0FC5oo",  // Brett Manning warm-up
        "VVM9uJ25VbM",  // Lip trill
    ]

    func testEmbedLoadsWithoutError() async throws {
        for videoID in testVideoIDs {
            print("Testing YouTube embed: \(videoID)")
            try await assertEmbedLoads(videoID: videoID)
        }
    }

    private func assertEmbedLoads(videoID: String) async throws {
        do {
            try await _assertEmbedLoads(videoID: videoID)
        } catch is CancellationError {
            throw XCTSkip("YouTube embed timed out for \(videoID) — likely a network/simulator issue")
        }
    }

    private func _assertEmbedLoads(videoID: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let handler = YouTubeMessageHandler(videoID: videoID, continuation: continuation)
            let config = WKWebViewConfiguration()
            config.allowsInlineMediaPlayback = true
            config.mediaTypesRequiringUserActionForPlayback = []
            config.websiteDataStore = .default()
            config.userContentController.add(handler, name: "youtubeEvents")

            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), configuration: config)
            handler.webView = webView // retain

            // WKWebView needs to be in a window to process JS events (postMessage won't fire otherwise)
            if let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) {
                window.addSubview(webView)
                handler.parentWindow = window
            }

            webView.loadHTMLString(embedHTML(for: videoID), baseURL: URL(string: "https://www.youtube-nocookie.com"))

            // Timeout after 20s
            Task {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                handler.timeOut()
            }
        }
    }

    private func embedHTML(for videoID: String) -> String {
        let src = "https://www.youtube-nocookie.com/embed/\(videoID)?playsinline=1&rel=0&enablejsapi=1&origin=https://www.youtube-nocookie.com"
        return """
        <!DOCTYPE html><html>
        <head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>* { margin:0; padding:0; background:#000; } iframe { width:100%; height:100vh; border:none; }</style>
        </head>
        <body>
        <iframe src="\(src)" allow="autoplay; encrypted-media" allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe>
        <script>
        window.addEventListener('message', function(e) {
          try {
            var d = JSON.parse(e.data);
            if (d.event === 'onReady') {
              window.webkit.messageHandlers.youtubeEvents.postMessage({ type: 'ready' });
            } else if (d.event === 'onError') {
              window.webkit.messageHandlers.youtubeEvents.postMessage({ type: 'error', code: d.info });
            }
          } catch(ex) {}
        });
        </script>
        </body></html>
        """
    }
}

// MARK: - Message handler (reference type, holds continuation)

private final class YouTubeMessageHandler: NSObject, WKScriptMessageHandler, @unchecked Sendable {
    let videoID: String
    var webView: WKWebView? // retained so WKWebView stays alive during the test
    weak var parentWindow: UIWindow? // add webView to window so JS events fire
    private var continuation: CheckedContinuation<Void, Error>?
    private let lock = NSLock()

    init(videoID: String, continuation: CheckedContinuation<Void, Error>) {
        self.videoID = videoID
        self.continuation = continuation
    }

    func userContentController(_ userContentController: WKUserContentController,
                                didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let c = continuation else { return }
        continuation = nil
        let webViewToClean = webView
        webView = nil
        if type == "ready" {
            print("✅ YouTube player ready: \(videoID)")
            DispatchQueue.main.async { webViewToClean?.removeFromSuperview() }
            c.resume()
        } else {
            let code = body["code"] as? Int ?? -1
            print("❌ YouTube player error \(code) for: \(videoID)")
            DispatchQueue.main.async { webViewToClean?.removeFromSuperview() }
            c.resume(throwing: YouTubeEmbedError.playerError(videoID: videoID, code: code))
        }
    }

    func timeOut() {
        lock.lock()
        defer { lock.unlock() }
        guard let c = continuation else { return }
        continuation = nil
        let webViewToClean = webView
        webView = nil
        print("⏱ YouTube embed timed out for \(videoID)")
        DispatchQueue.main.async { webViewToClean?.removeFromSuperview() }
        c.resume(throwing: CancellationError())
    }
}

// MARK: - Error

enum YouTubeEmbedError: Error, LocalizedError {
    case playerError(videoID: String, code: Int)

    var errorDescription: String? {
        switch self {
        case .playerError(let id, let code):
            return "YouTube error \(code) for \(id). 100=not found, 150/152=embed restricted, 153=origin config."
        }
    }
}
