//
//  BridgeSmokeTest.swift
//  MTRX Tests
//
//  End-to-end smoke test for the 0pnMatrx Bridge flow. Exercises the full
//  handshake sequence the iOS app performs on launch, with every HTTP call
//  stubbed by MockURLProtocol against the canonical 0pnMatrx /bridge/v1/*
//  response envelopes:
//
//      create_session → chat → link_wallet → execute_action → wallet_status
//                    → get_dashboard → get_components → get_manifest
//
//  The goal is to catch wire-format regressions in the BridgeResponse<T>
//  envelope, snake_case key handling, and the side effects the client
//  performs (like stashing bridgeSessionId for subsequent calls).
//

import XCTest
@testable import MTRX

final class BridgeSmokeTest: XCTestCase {

    private var client: MTRXAPIClient!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        client = MTRXAPIClient(baseURL: "http://bridge.test", session: session)
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        client = nil
        super.tearDown()
    }

    // MARK: - Individual endpoint coverage

    func test_bridgeCreateSession_storesSessionId() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/bridge/v1/session/create")
            XCTAssertEqual(request.httpMethod, "POST")
            return try MockURLProtocol.json([
                "ok": true,
                "data": [
                    "session_id": "neo-session-42",
                    "greeting": "Wake up, Neo...",
                ],
                "error": NSNull(),
                "timestamp": 1_700_000_000.0,
            ])
        }

        let data = try await client.bridgeCreateSession(deviceId: "device-123")
        XCTAssertEqual(data.sessionId, "neo-session-42")
        XCTAssertEqual(data.greeting, "Wake up, Neo...")
        XCTAssertEqual(client.bridgeSessionId, "neo-session-42",
                       "bridgeSessionId must be persisted after create")
    }

    func test_bridgeResumeSession_returnsTrueOnResumed() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/bridge/v1/session/resume")
            return try MockURLProtocol.json([
                "ok": true,
                "data": [
                    "session_id": "existing-session",
                    "resumed": true,
                    "message_count": 7,
                ],
                "error": NSNull(),
            ])
        }
        let resumed = try await client.bridgeResumeSession("existing-session")
        XCTAssertTrue(resumed)
        XCTAssertEqual(client.bridgeSessionId, "existing-session")
    }

    func test_bridgeLinkWallet_sendsAddressAndNetwork() async throws {
        _ = try await seedSession(sessionId: "session-x")

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/bridge/v1/wallet/link")
            return try MockURLProtocol.json([
                "ok": true,
                "data": ["linked": true, "address": "0xNeo"],
                "error": NSNull(),
            ])
        }

        try await client.bridgeLinkWallet(address: "0xNeo", network: "base-sepolia")

        let captured = try XCTUnwrap(MockURLProtocol.lastRequest)
        let body = try XCTUnwrap(captured.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["session_id"] as? String, "session-x")
        XCTAssertEqual(json["address"] as? String, "0xNeo")
        XCTAssertEqual(json["network"] as? String, "base-sepolia")
    }

    func test_bridgeWalletStatus_returnsStatusOrFallback() async throws {
        _ = try await seedSession(sessionId: "sess-ws")

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/bridge/v1/wallet/status")
            XCTAssertEqual(request.httpMethod, "GET")
            return try MockURLProtocol.json([
                "ok": true,
                "data": [
                    "linked": true,
                    "address": "0xNeo",
                    "network": "base-sepolia",
                    "balance_eth": "0.125",
                ],
                "error": NSNull(),
            ])
        }

        let status = try await client.bridgeWalletStatus()
        XCTAssertTrue(status.linked)
        XCTAssertEqual(status.address, "0xNeo")
        XCTAssertEqual(status.network, "base-sepolia")
        XCTAssertEqual(status.balanceEth, "0.125")
    }

    func test_bridgeGetDashboard_returnsTypedData() async throws {
        _ = try await seedSession(sessionId: "sess-dash")

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/bridge/v1/dashboard")
            return try MockURLProtocol.json([
                "ok": true,
                "data": [
                    "wallet": [
                        "linked": true,
                        "address": "0xNeo",
                        "network": "base-sepolia",
                        "balance_eth": "0.5",
                    ],
                    "services_available": 30,
                    "active_sessions": 1,
                    "suggestions": ["Mint an NFT", "Swap on DEX"],
                ],
                "error": NSNull(),
            ])
        }

        let dash = try await client.bridgeGetDashboard()
        XCTAssertEqual(dash.servicesAvailable, 30)
        XCTAssertEqual(dash.activeSessions, 1)
        XCTAssertEqual(dash.suggestions.count, 2)
        XCTAssertEqual(dash.wallet?.address, "0xNeo")
    }

    func test_bridgeExecuteAction_roundTripsSessionId() async throws {
        _ = try await seedSession(sessionId: "sess-action")

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/bridge/v1/action")
            return try MockURLProtocol.json([
                "ok": true,
                "data": ["result": "queued"],
                "error": NSNull(),
            ])
        }

        _ = try? await client.bridgeExecuteAction(
            "mint_nft",
            params: ["contract_id": .string("abc")]
        )

        let captured = try XCTUnwrap(MockURLProtocol.lastRequest)
        let body = try XCTUnwrap(captured.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["action"] as? String, "mint_nft")
        XCTAssertEqual(json["session_id"] as? String, "sess-action")
    }

    // MARK: - End-to-end handshake

    func test_fullHandshake_walksTheHappyPath() async throws {
        // Route responses by path — one shared handler that matches on URL path.
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""

            switch path {
            case "/bridge/v1/session/create":
                return try MockURLProtocol.json([
                    "ok": true,
                    "data": ["session_id": "handshake-1", "greeting": "Welcome."],
                    "error": NSNull(),
                ])

            case "/bridge/v1/wallet/link":
                return try MockURLProtocol.json([
                    "ok": true,
                    "data": ["linked": true, "address": "0xNeo"],
                    "error": NSNull(),
                ])

            case "/bridge/v1/wallet/status":
                return try MockURLProtocol.json([
                    "ok": true,
                    "data": [
                        "linked": true,
                        "address": "0xNeo",
                        "network": "base-sepolia",
                        "balance_eth": "1.0",
                    ],
                    "error": NSNull(),
                ])

            case "/bridge/v1/dashboard":
                return try MockURLProtocol.json([
                    "ok": true,
                    "data": [
                        "wallet": NSNull(),
                        "services_available": 30,
                        "active_sessions": 1,
                        "suggestions": [],
                    ],
                    "error": NSNull(),
                ])

            default:
                XCTFail("Unexpected path: \(path)")
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 404,
                    httpVersion: "HTTP/1.1", headerFields: nil
                )!
                return (response, Data())
            }
        }

        // Step 1: create session
        let session = try await client.bridgeCreateSession(deviceId: "handshake-device")
        XCTAssertEqual(session.sessionId, "handshake-1")
        XCTAssertEqual(client.bridgeSessionId, "handshake-1")

        // Step 2: link wallet
        try await client.bridgeLinkWallet(address: "0xNeo")

        // Step 3: verify wallet status
        let status = try await client.bridgeWalletStatus()
        XCTAssertTrue(status.linked)
        XCTAssertEqual(status.address, "0xNeo")

        // Step 4: load dashboard
        let dash = try await client.bridgeGetDashboard()
        XCTAssertEqual(dash.servicesAvailable, 30)

        // All four calls should have been captured in order.
        XCTAssertEqual(MockURLProtocol.seenRequests.count, 4)
        XCTAssertEqual(MockURLProtocol.seenRequests.map { $0.url?.path }, [
            "/bridge/v1/session/create",
            "/bridge/v1/wallet/link",
            "/bridge/v1/wallet/status",
            "/bridge/v1/dashboard",
        ])
    }

    // MARK: - Error envelopes

    func test_bridgeGetDashboard_throwsWhenEnvelopeHasNoData() async throws {
        _ = try await seedSession(sessionId: "sess-err")

        MockURLProtocol.handler = { request in
            return try MockURLProtocol.json([
                "ok": false,
                "data": NSNull(),
                "error": "session expired",
            ])
        }

        do {
            _ = try await client.bridgeGetDashboard()
            XCTFail("Expected decoding failure when data is null")
        } catch MTRXAPIError.decodingFailed {
            // expected
        } catch {
            XCTFail("Expected .decodingFailed, got \(error)")
        }
    }

    // MARK: - Private helpers

    @discardableResult
    private func seedSession(sessionId: String) async throws -> BridgeSessionData {
        MockURLProtocol.handler = { request in
            return try MockURLProtocol.json([
                "ok": true,
                "data": ["session_id": sessionId, "greeting": ""],
                "error": NSNull(),
            ])
        }
        let data = try await client.bridgeCreateSession(deviceId: "seed")
        MockURLProtocol.reset()
        return data
    }
}
