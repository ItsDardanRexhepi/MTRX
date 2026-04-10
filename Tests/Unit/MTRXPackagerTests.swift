//
//  MTRXPackagerTests.swift
//  MTRX Tests
//
//  Unit tests for the MTRXPackager — component registry, request packaging,
//  batch envelope construction, offline queue, and SSE message parsing.
//
//  These tests do NOT hit the network. The packager is purely a
//  URLRequest/Data transformation layer, so we verify its outputs against
//  the snake_case wire format that the Python runtime expects.
//

import XCTest
import Combine
@testable import MTRX

final class MTRXPackagerTests: XCTestCase {

    private var packager: MTRXPackager!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        packager = MTRXPackager.shared
        cancellables = []
        // Start from a clean offline queue for each test.
        packager.clearQueue()
        packager.resetSession()
    }

    override func tearDown() {
        packager.clearQueue()
        cancellables = nil
        packager = nil
        super.tearDown()
    }

    // MARK: - Component Registry

    func test_registry_hasAllThirtyComponents() {
        let all = packager.allComponents
        XCTAssertEqual(all.count, 30, "Registry must expose exactly 30 components")
        let ids = Set(all.map(\.id))
        XCTAssertEqual(ids, Set(1...30), "Component IDs must be contiguous 1...30")
    }

    func test_registry_componentPathsMatchRuntime() {
        // Spot-check a handful of components against the runtime paths.
        XCTAssertEqual(packager.component(1)?.path,  "/contracts")
        XCTAssertEqual(packager.component(2)?.path,  "/defi")
        XCTAssertEqual(packager.component(3)?.path,  "/nfts")
        XCTAssertEqual(packager.component(11)?.path, "/oracle")
        XCTAssertEqual(packager.component(20)?.path, "/dashboard")
        XCTAssertEqual(packager.component(30)?.path, "/disputes")
    }

    func test_registry_versionedPathIncludesAPIv1Prefix() {
        XCTAssertEqual(packager.component(1)?.versionedPath, "/api/v1/contracts")
        XCTAssertEqual(packager.component(20)?.versionedPath, "/api/v1/dashboard")
    }

    func test_registry_componentsFilteredByFamily() {
        let defi = packager.components(in: .defi)
        let defiIds = Set(defi.map(\.id))
        // C2 DeFi Lending, C7 Stablecoin, C13 Insurance, C16 Staking,
        // C17 Payments, C21 DEX.
        XCTAssertEqual(defiIds, Set([2, 7, 13, 16, 17, 21]))
    }

    func test_unknownComponent_throwsPackagerError() {
        struct Empty: Encodable {}
        XCTAssertThrowsError(try packager.package(Empty(), for: 999)) { error in
            guard case PackagerError.unknownComponent(let id) = error else {
                return XCTFail("Expected .unknownComponent, got \(error)")
            }
            XCTAssertEqual(id, 999)
        }
    }

    // MARK: - Request Packaging

    struct SampleConvertRequest: Encodable {
        let templateId: String
        let sourceCode: String
        let chainId: Int
    }

    func test_package_buildsURLWithVersionedComponentPath() throws {
        let body = SampleConvertRequest(
            templateId: "erc20",
            sourceCode: "contract A {}",
            chainId: 8453
        )
        let request = try packager.package(body, for: 1, subpath: "convert")

        XCTAssertEqual(request.httpMethod, "POST")
        let path = request.url?.path ?? ""
        XCTAssertEqual(path, "/api/v1/contracts/convert")
    }

    func test_package_setsStandardHeaders() throws {
        struct Empty: Encodable {}
        let request = try packager.package(Empty(), for: 2, method: .post)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-MTRX-API-Version"), "1.0")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-MTRX-Platform"), "ios")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-MTRX-Component"), "2")
    }

    func test_package_injectsIdempotencyKey() throws {
        struct Empty: Encodable {}
        let request = try packager.package(
            Empty(),
            for: 17,
            idempotencyKey: "abc-123"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "abc-123")
    }

    func test_package_encodesBodyWithSnakeCaseKeys() throws {
        let body = SampleConvertRequest(
            templateId: "erc20",
            sourceCode: "contract A {}",
            chainId: 8453
        )
        let request = try packager.package(body, for: 1)
        guard let data = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("Request body should be JSON-decodable")
        }
        XCTAssertEqual(json["template_id"] as? String, "erc20")
        XCTAssertEqual(json["source_code"] as? String, "contract A {}")
        XCTAssertEqual(json["chain_id"] as? Int, 8453)
        // camelCase keys must NOT leak into the wire format.
        XCTAssertNil(json["templateId"])
        XCTAssertNil(json["sourceCode"])
        XCTAssertNil(json["chainId"])
    }

    func test_package_getRequestHasNoBody() throws {
        let request = try packager.buildListRequest(componentId: 20, page: 2, perPage: 50)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertTrue(request.url?.query?.contains("page=2") ?? false)
        XCTAssertTrue(request.url?.query?.contains("per_page=50") ?? false)
    }

    func test_package_appendsQueryItems() throws {
        let request = try packager.buildListRequest(
            componentId: 3,
            page: 1,
            perPage: 10,
            filters: ["owner": "0xNeo", "status": "active"]
        )
        let query = request.url?.query ?? ""
        XCTAssertTrue(query.contains("owner=0xNeo"))
        XCTAssertTrue(query.contains("status=active"))
    }

    func test_buildDetailRequest_buildsResourcePath() throws {
        let request = try packager.buildDetailRequest(componentId: 3, resourceId: "token-42")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/v1/nfts/token-42")
    }

    func test_buildDeleteRequest_usesDeleteMethod() throws {
        let request = try packager.buildDeleteRequest(componentId: 3, resourceId: "token-42")
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/api/v1/nfts/token-42")
        XCTAssertNil(request.httpBody)
    }

    // MARK: - Batch Envelope

    func test_batchPackage_usesBatchEndpoint() throws {
        let reqs = [
            ComponentRequest(componentId: 1, subpath: "convert"),
            ComponentRequest(componentId: 20, method: .get),
        ]
        let request = try packager.batchPackage(reqs)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/batch")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-MTRX-Component"), "batch")
    }

    func test_batchPackage_convertsAbortOnFailureToSnakeCase() throws {
        let reqs = [
            ComponentRequest(componentId: 1, subpath: "convert"),
        ]
        let request = try packager.batchPackage(reqs, sequential: true, abortOnFailure: true)
        guard let data = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("Batch envelope should be JSON-decodable")
        }
        XCTAssertEqual(json["sequential"] as? Bool, true)
        XCTAssertEqual(json["abort_on_failure"] as? Bool, true,
                       "abortOnFailure must serialize as abort_on_failure")
        XCTAssertNil(json["abortOnFailure"], "camelCase must not leak through")

        let requests = json["requests"] as? [[String: Any]] ?? []
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?["method"] as? String, "POST")
        XCTAssertEqual(requests.first?["path"] as? String, "/api/v1/contracts/convert")
    }

    func test_batchPackage_rejectsUnknownComponentId() {
        let reqs = [ComponentRequest(componentId: 777)]
        XCTAssertThrowsError(try packager.batchPackage(reqs)) { error in
            guard case PackagerError.unknownComponent(let id) = error else {
                return XCTFail("Expected .unknownComponent, got \(error)")
            }
            XCTAssertEqual(id, 777)
        }
    }

    // MARK: - Response Unpacking

    func test_unpack_decodesDirectPayload() throws {
        struct Echo: Codable, Equatable { let name: String; let count: Int }
        let payload = #"{"name":"neo","count":42}"#.data(using: .utf8)!
        let result = try packager.unpack(payload, as: Echo.self)
        XCTAssertEqual(result, Echo(name: "neo", count: 42))
    }

    func test_unpack_decodesWrappedAPIResponse() throws {
        struct Echo: Codable, Equatable { let name: String }
        let payload = #"""
        {"success":true,"data":{"name":"morpheus"},"error":null}
        """#.data(using: .utf8)!
        let result = try packager.unpack(payload, as: Echo.self)
        XCTAssertEqual(result, Echo(name: "morpheus"))
    }

    func test_unpack_surfacesErrorFromWrapper() {
        struct Echo: Codable { let name: String }
        let payload = #"""
        {"success":false,"data":null,"error":"component disabled"}
        """#.data(using: .utf8)!
        XCTAssertThrowsError(try packager.unpack(payload, as: Echo.self)) { error in
            guard case PackagerError.invalidResponse(let msg) = error else {
                return XCTFail("Expected .invalidResponse, got \(error)")
            }
            XCTAssertTrue(msg.contains("component disabled"))
        }
    }

    // MARK: - Offline Queue

    struct DummyBody: Encodable, Sendable {
        let action: String
        let amount: Int
    }

    func test_enqueue_persistsAcrossReads() throws {
        try packager.enqueue(
            ComponentRequest(
                componentId: 17,
                subpath: "transfer",
                body: DummyBody(action: "send", amount: 100),
                idempotencyKey: "tx-1"
            ),
            priority: .normal
        )
        XCTAssertEqual(packager.pendingCount, 1)
        let op = packager.pendingOperations.first
        XCTAssertEqual(op?.componentId, 17)
        XCTAssertEqual(op?.path, "/api/v1/payments/transfer")
        XCTAssertEqual(op?.idempotencyKey, "tx-1")
    }

    func test_pendingOperations_sortedByPriorityThenCreatedAt() throws {
        try packager.enqueue(
            ComponentRequest(componentId: 17, body: DummyBody(action: "a", amount: 1)),
            priority: .low
        )
        try packager.enqueue(
            ComponentRequest(componentId: 17, body: DummyBody(action: "b", amount: 2)),
            priority: .critical
        )
        try packager.enqueue(
            ComponentRequest(componentId: 17, body: DummyBody(action: "c", amount: 3)),
            priority: .high
        )

        let ordered = packager.pendingOperations
        XCTAssertEqual(ordered.count, 3)
        XCTAssertEqual(ordered[0].priority, .critical)
        XCTAssertEqual(ordered[1].priority, .high)
        XCTAssertEqual(ordered[2].priority, .low)
    }

    func test_dequeue_removesOperation() throws {
        try packager.enqueue(
            ComponentRequest(componentId: 17, body: DummyBody(action: "x", amount: 9)),
            priority: .normal
        )
        let op = try XCTUnwrap(packager.pendingOperations.first)
        packager.dequeue(op.id)
        XCTAssertEqual(packager.pendingCount, 0)
    }

    func test_drainQueue_buildsRequestsAndClearsQueue() throws {
        try packager.enqueue(
            ComponentRequest(componentId: 3, subpath: "mint",
                             body: DummyBody(action: "mint", amount: 1)),
            priority: .high
        )
        let drained = try packager.drainQueue()
        XCTAssertEqual(drained.count, 1)
        XCTAssertEqual(drained.first?.request.httpMethod, "POST")
        XCTAssertEqual(drained.first?.request.url?.path, "/api/v1/nfts/mint")
        XCTAssertNotNil(drained.first?.request.value(forHTTPHeaderField: "Idempotency-Key"))
        XCTAssertEqual(packager.pendingCount, 0,
                       "drainQueue must empty the queue after building requests")
    }

    func test_markFailed_incrementsRetryUntilLimit() throws {
        try packager.enqueue(
            ComponentRequest(componentId: 17, body: DummyBody(action: "retry", amount: 0)),
            priority: .normal
        )
        let op = try XCTUnwrap(packager.pendingOperations.first)
        // Default maxRetries is 5; six failures should remove the op.
        for _ in 0..<6 {
            packager.markFailed(op.id)
        }
        XCTAssertEqual(packager.pendingCount, 0,
                       "Operation exceeding max retries must be removed")
    }

    func test_clearQueue_removesAllOperations() throws {
        for idx in 0..<5 {
            try packager.enqueue(
                ComponentRequest(componentId: 17, body: DummyBody(action: "op", amount: idx)),
                priority: .normal
            )
        }
        XCTAssertEqual(packager.pendingCount, 5)
        packager.clearQueue()
        XCTAssertEqual(packager.pendingCount, 0)
    }

    // MARK: - Session Tracking

    func test_packageRecordsSessionUsage() throws {
        struct Empty: Encodable {}
        _ = try packager.package(Empty(), for: 11)
        _ = try packager.package(Empty(), for: 20)
        let session = packager.packageSessionInfo()
        XCTAssertEqual(session.actionsTaken, 2)
        XCTAssertEqual(session.lastComponent, 20)
    }

    func test_resetSession_clearsCounter() throws {
        struct Empty: Encodable {}
        _ = try packager.package(Empty(), for: 5)
        packager.resetSession()
        let session = packager.packageSessionInfo()
        XCTAssertEqual(session.actionsTaken, 0)
        XCTAssertNil(session.lastComponent)
    }
}
