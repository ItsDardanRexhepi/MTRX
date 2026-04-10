//
//  MockURLProtocol.swift
//  MTRX Tests
//
//  Reusable URLProtocol subclass that intercepts every request made by a
//  URLSession configured with it in `protocolClasses`. Lets us drive the
//  Packager and APIClient against canned responses without ever hitting
//  the network.
//
//  Usage:
//
//      let config = URLSessionConfiguration.ephemeral
//      config.protocolClasses = [MockURLProtocol.self]
//      let client = MTRXAPIClient(baseURL: "http://test.local", session: URLSession(configuration: config))
//
//      MockURLProtocol.handler = { request in
//          let body = #"{"success": true, "data": {"token_id": 42}}"#.data(using: .utf8)!
//          let response = HTTPURLResponse(
//              url: request.url!, statusCode: 200,
//              httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]
//          )!
//          return (response, body)
//      }
//

import Foundation

final class MockURLProtocol: URLProtocol, @unchecked Sendable {

    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    /// Global handler. Set before each test; reset in tearDown.
    nonisolated(unsafe) static var handler: Handler?

    /// Last request seen by the mock — useful for asserting headers, body
    /// contents, and query parameters after a call.
    nonisolated(unsafe) static var lastRequest: URLRequest?

    /// Every request intercepted, in order, for tests that care about
    /// multi-step sequences.
    nonisolated(unsafe) static var seenRequests: [URLRequest] = []

    static func reset() {
        handler = nil
        lastRequest = nil
        seenRequests = []
    }

    // MARK: - URLProtocol overrides

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        // Capture request body from the stream if it was staged there.
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            captured.httpBody = Self.readStream(stream)
        }

        Self.lastRequest = captured
        Self.seenRequests.append(captured)

        guard let handler = Self.handler else {
            client?.urlProtocol(
                self,
                didFailWithError: NSError(
                    domain: "MockURLProtocol",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No handler set"]
                )
            )
            return
        }

        do {
            let (response, data) = try handler(captured)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() { /* no-op */ }

    // MARK: - Helpers

    private static func readStream(_ stream: InputStream) -> Data {
        var data = Data()
        stream.open()
        defer { stream.close() }
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    /// Convenience: build a JSON response helper usable from any test.
    static func json(
        _ object: Any,
        status: Int = 200,
        url: URL = URL(string: "http://test.local")!
    ) throws -> (HTTPURLResponse, Data) {
        let data = try JSONSerialization.data(withJSONObject: object)
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)
    }
}
