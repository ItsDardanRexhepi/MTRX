//
//  GatewayURLResolutionTests.swift
//  MTRX — Tests
//
//  End-to-end proof for the Cloud Trinity URL fixes (build 200.1.2): a gateway
//  URL entered AT RUNTIME must reach BOTH transport paths — the WebSocket
//  (GatewayRealtimeURL.chatSocket) and the REST fallback (MTRXAPIClient.baseURL)
//  — and the single normalizer must make malformed entries either work or count
//  as unconfigured (never half-configured).
//
//  Regression guards for: the frozen `let baseURL` (runtime URL never reached
//  REST), the trailing-slash //bridge/v1/chat 404, and the scheme-less entry
//  that half-configured everything.
//

import XCTest
@testable import MTRX

final class GatewayURLResolutionTests: XCTestCase {

    private var savedURL: String!

    override func setUp() {
        super.setUp()
        savedURL = PendingCredentials.runtimeGatewayURL
    }

    override func tearDown() {
        PendingCredentials.runtimeGatewayURL = savedURL
        super.tearDown()
    }

    /// The core 200.1.2 guarantee: set the URL at runtime -> BOTH paths see it.
    func test_runtimeURL_reachesBothWSAndRESTPaths() {
        PendingCredentials.runtimeGatewayURL = "http://10.0.0.5:18790"

        // REST path — MTRXAPIClient.shared existed long before this URL was set;
        // baseURL must still resolve to it (the old frozen `let` failed here).
        XCTAssertEqual(MTRXAPIClient.shared.baseURL, "http://10.0.0.5:18790")

        // WS path — same URL, ws scheme, /ws path.
        XCTAssertEqual(GatewayRealtimeURL.chatSocket?.absoluteString, "ws://10.0.0.5:18790/ws")

        XCTAssertTrue(PendingCredentials.isBackendConfigured)
    }

    /// Changing the URL mid-session re-points BOTH paths (no relaunch needed).
    func test_changingURL_repointsBothPaths() {
        PendingCredentials.runtimeGatewayURL = "http://192.168.1.68:18790"
        XCTAssertEqual(MTRXAPIClient.shared.baseURL, "http://192.168.1.68:18790")

        PendingCredentials.runtimeGatewayURL = "https://gateway.openmatrix-ai.com"
        XCTAssertEqual(MTRXAPIClient.shared.baseURL, "https://gateway.openmatrix-ai.com")
        XCTAssertEqual(GatewayRealtimeURL.chatSocket?.absoluteString,
                       "wss://gateway.openmatrix-ai.com/ws")
    }

    /// Trailing slashes are stripped centrally (REST concatenates baseURL+path;
    /// "…/" used to produce //bridge/v1/chat -> 404 while WS worked).
    func test_trailingSlashes_strippedForBothPaths() {
        PendingCredentials.runtimeGatewayURL = "http://10.0.0.5:18790///"
        XCTAssertEqual(PendingCredentials.effectiveGatewayURL, "http://10.0.0.5:18790")
        XCTAssertEqual(MTRXAPIClient.shared.baseURL, "http://10.0.0.5:18790")
        XCTAssertEqual(GatewayRealtimeURL.chatSocket?.absoluteString, "ws://10.0.0.5:18790/ws")
    }

    /// A scheme-less LAN entry (what a tester actually types) gets http:// and works.
    func test_schemelessEntry_getsHTTPAndWorks() {
        PendingCredentials.runtimeGatewayURL = "192.168.1.68:18790"
        XCTAssertEqual(PendingCredentials.effectiveGatewayURL, "http://192.168.1.68:18790")
        XCTAssertTrue(PendingCredentials.isBackendConfigured)
        XCTAssertEqual(GatewayRealtimeURL.chatSocket?.absoluteString, "ws://192.168.1.68:18790/ws")
    }

    /// Garbage never half-configures: isBackendConfigured must stay false so the
    /// router keeps on-device answers instead of believing a dead cloud exists.
    func test_garbageOrEmpty_neverHalfConfigures() {
        PendingCredentials.runtimeGatewayURL = "not a url"
        XCTAssertFalse(PendingCredentials.isBackendConfigured)
        XCTAssertNil(GatewayRealtimeURL.chatSocket)

        PendingCredentials.runtimeGatewayURL = ""
        XCTAssertFalse(PendingCredentials.isBackendConfigured)
        XCTAssertNil(GatewayRealtimeURL.chatSocket)
    }

    /// Non-http(s) schemes are rejected (ftp:// etc. can't carry the chat).
    func test_wrongScheme_rejected() {
        PendingCredentials.runtimeGatewayURL = "ftp://10.0.0.5:18790"
        XCTAssertFalse(PendingCredentials.isBackendConfigured)
    }
}
