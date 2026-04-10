//
//  MTRXAPIClientTests.swift
//  MTRX Tests
//
//  Unit tests for the MTRXAPIClient transport layer. Every test drives a
//  dedicated `MTRXAPIClient(baseURL:session:)` instance whose session is
//  stubbed with `MockURLProtocol` — no real network is used.
//
//  The goals here are:
//
//  * Verify request construction (headers, query items, body encoding)
//  * Verify the retry/backoff policy for 429 and 5xx
//  * Verify HTTP status → MTRXAPIError mapping
//  * Verify 401 clears the stored auth token
//  * Verify the env-var / init baseURL override
//

import XCTest
@testable import MTRX

final class MTRXAPIClientTests: XCTestCase {

    // MARK: - Helpers

    private func makeClient(baseURL: String = "http://test.local") -> MTRXAPIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return MTRXAPIClient(baseURL: baseURL, session: session)
    }

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - baseURL & Init

    func test_init_defaultsToLocalhost_whenEnvNotSet() {
        // If MTRX_RUNTIME_URL is unset the fallback is http://localhost:8000.
        // Run this check only when the env var is absent to avoid flaking in
        // CI environments that pin it.
        if ProcessInfo.processInfo.environment["MTRX_RUNTIME_URL"] == nil {
            let client = MTRXAPIClient()
            XCTAssertEqual(client.baseURL, "http://localhost:8000")
        }
    }

    func test_init_overrideBaseURL_winsOverEnvironment() {
        let client = MTRXAPIClient(baseURL: "https://runtime.example.com")
        XCTAssertEqual(client.baseURL, "https://runtime.example.com")
    }

    // MARK: - Health (happy path)

    func test_health_decodesSuccessResponse() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/health")
            return try MockURLProtocol.json([
                "status": "healthy",
                "blockchain_components": 30,
                "phase3_subsystems": 12,
            ])
        }

        let client = makeClient()
        let result = try await client.health()
        XCTAssertEqual(result.status, "healthy")
        XCTAssertEqual(result.blockchainComponents, 30)
        XCTAssertEqual(result.phase3Subsystems, 12)
    }

    // MARK: - Auth Token Injection

    func test_authenticatedGet_attachesBearerToken() async throws {
        let client = makeClient()
        client.authToken = "jwt-abc"

        MockURLProtocol.handler = { request in
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer jwt-abc",
                "Auth header must be attached to authenticated calls"
            )
            return try MockURLProtocol.json(["tokens": [], "nfts": [], "defi_positions": [], "total_value_usd": 0])
        }

        _ = try? await client.getPortfolio()
    }

    func test_unauthenticatedCall_doesNotSendAuthHeader() async throws {
        let client = makeClient()
        client.authToken = "jwt-abc"

        MockURLProtocol.handler = { request in
            XCTAssertNil(
                request.value(forHTTPHeaderField: "Authorization"),
                "Unauthenticated calls must NOT send Authorization"
            )
            return try MockURLProtocol.json(["status": "healthy"])
        }

        _ = try? await client.health()
    }

    // MARK: - Status Code Mapping

    func test_401_clearsAuthTokenAndThrowsUnauthorized() async throws {
        let client = makeClient()
        client.authToken = "soon-to-be-gone"

        MockURLProtocol.handler = { request in
            let body = Data("{\"error\":\"token expired\"}".utf8)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401,
                httpVersion: "HTTP/1.1", headerFields: nil
            )!
            return (response, body)
        }

        do {
            let _: MTRXAPIClient.HealthResponse = try await client.get(path: "/health")
            XCTFail("Expected MTRXAPIError.unauthorized")
        } catch MTRXAPIError.unauthorized {
            XCTAssertNil(client.authToken, "401 must clear the auth token")
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func test_403_throwsForbidden() async throws {
        let client = makeClient()
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 403,
                httpVersion: "HTTP/1.1", headerFields: nil
            )!
            return (response, Data())
        }
        do {
            let _: MTRXAPIClient.HealthResponse = try await client.get(path: "/health")
            XCTFail("Expected .forbidden")
        } catch MTRXAPIError.forbidden {
            // ok
        } catch {
            XCTFail("Expected .forbidden, got \(error)")
        }
    }

    func test_404_throwsNotFound() async throws {
        let client = makeClient()
        MockURLProtocol.handler = { request in
            let body = Data("resource missing".utf8)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 404,
                httpVersion: "HTTP/1.1", headerFields: nil
            )!
            return (response, body)
        }
        do {
            let _: MTRXAPIClient.HealthResponse = try await client.get(path: "/health")
            XCTFail("Expected .notFound")
        } catch MTRXAPIError.notFound(let body) {
            XCTAssertTrue(body.contains("resource missing"))
        } catch {
            XCTFail("Expected .notFound, got \(error)")
        }
    }

    func test_500_retriesThenThrowsServerError() async throws {
        let client = makeClient()
        let attempts = Atomic(0)

        MockURLProtocol.handler = { request in
            attempts.increment()
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500,
                httpVersion: "HTTP/1.1", headerFields: nil
            )!
            return (response, Data("upstream blew up".utf8))
        }

        do {
            let _: MTRXAPIClient.HealthResponse = try await client.get(path: "/health")
            XCTFail("Expected .serverError")
        } catch MTRXAPIError.serverError(let body) {
            XCTAssertTrue(body.contains("upstream blew up"))
            // Original attempt + 3 retries = 4 requests sent.
            XCTAssertEqual(attempts.value, 4,
                           "500 must retry maxRetries times before surfacing")
        } catch {
            XCTFail("Expected .serverError, got \(error)")
        }
    }

    func test_429_retriesAndThenSucceeds() async throws {
        let client = makeClient()
        let attempts = Atomic(0)

        MockURLProtocol.handler = { request in
            let n = attempts.increment()
            if n < 2 {
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 429,
                    httpVersion: "HTTP/1.1", headerFields: ["Retry-After": "0"]
                )!
                return (response, Data())
            }
            return try MockURLProtocol.json(["status": "healthy"])
        }

        let result = try await client.health()
        XCTAssertEqual(result.status, "healthy")
        XCTAssertEqual(attempts.value, 2, "One 429 → one retry → success")
    }

    // MARK: - Body Encoding

    func test_postBody_encodesToSnakeCase() async throws {
        let client = makeClient()

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            // The mock's capturedRequest already has httpBody extracted from
            // the stream, so we assert against lastRequest directly.
            return try MockURLProtocol.json([
                "ok": true,
                "data": ["session_id": "sess-1", "greeting": "Welcome, Neo."],
            ])
        }

        _ = try? await client.bridgeCreateSession(deviceId: "device-xyz")

        let captured = try XCTUnwrap(MockURLProtocol.lastRequest)
        let body = try XCTUnwrap(captured.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["device_id"] as? String, "device-xyz")
        XCTAssertEqual(json["app_version"] as? String, "1.0.0")
    }

    func test_getWithQueryItems_appendsEverythingToURL() async throws {
        let client = makeClient()

        MockURLProtocol.handler = { request in
            let query = request.url?.query ?? ""
            XCTAssertTrue(query.contains("page=3"))
            XCTAssertTrue(query.contains("per_page=25"))
            return try MockURLProtocol.json(["status": "healthy"])
        }

        let _: MTRXAPIClient.HealthResponse = try await client.get(
            path: "/health",
            queryItems: [
                URLQueryItem(name: "page", value: "3"),
                URLQueryItem(name: "per_page", value: "25"),
            ],
            authenticated: false
        )
    }

    // MARK: - Token Storage

    func test_clearToken_removesTokenFromMemory() {
        let client = makeClient()
        client.authToken = "some-token"
        XCTAssertTrue(client.isAuthenticated)
        client.clearToken()
        XCTAssertFalse(client.isAuthenticated)
    }
}

// MARK: - Atomic counter helper

/// Thread-safe Int counter for test assertions.
private final class Atomic: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int

    init(_ initial: Int = 0) { _value = initial }

    var value: Int {
        lock.withLock { _value }
    }

    @discardableResult
    func increment() -> Int {
        lock.withLock {
            _value += 1
            return _value
        }
    }
}
