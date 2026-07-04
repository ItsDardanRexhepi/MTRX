//
//  ReasoningRouterTests.swift
//  MTRX — Tests
//
//  Regression guard for the local-first reasoning router
//  (`ReasoningRouter` in Core/Trinity/InferenceRouter.swift).
//
//  H8 REGRESSION — DO NOT re-add bare "1." / "2." / "3." to
//  `ReasoningRouter.answerLikelyLongMarkers`. Those substrings match decimals,
//  prices, versions and times ("3.5%", "1.99", "1.0.0", "2.30"), so a bare
//  numeric-dot marker over-escalates ordinary chat to the cloud — the exact
//  hole (H8) the "never-vanish" hardening closed. Only the enumeration forms
//  "1)" / "2)" / "3)" / "(1)" / "(2)" / "(3)" plus the phrase markers remain.
//
//  These assertions hit `ReasoningRouter.route` directly (a pure function), so
//  they are deterministic on any hardware — on-device availability is passed in,
//  never read from the real device.
//

import XCTest
@testable import MTRX

final class ReasoningRouterTests: XCTestCase {

    private let router = ReasoningRouter()

    /// Route with the "ordinary chat" environment: on-device is up, the cloud is
    /// reachable, privacy mode is off, and the caller is not forcing the cloud.
    /// Under these inputs the ONLY thing that can push a prompt to the cloud is a
    /// marker/length/multi-part signal — which is exactly what we want to test.
    private func route(_ prompt: String) -> ReasoningRoute {
        router.route(
            prompt: prompt,
            onDeviceAvailable: true,
            cloudReachable: true,
            privacyMode: false,
            forceCloud: false
        )
    }

    // MARK: - Decimals / prices / versions / times stay on-device (H8 guard)

    /// Prompts that contain a bare "N." numeric-dot (a decimal, price, version, or
    /// time) but are plainly ordinary chat. Each MUST stay on-device. If a bare
    /// "1." / "2." / "3." marker is ever re-added to `answerLikelyLongMarkers`,
    /// the matching prompt below flips to `.escalateToCloud` and fails this test.
    func testDecimalAndVersionPromptsStayOnDevice() {
        let onDevicePrompts = [
            "ETH is up 3.5% today",   // guards bare "3."
            "iOS 26.1 just dropped",  // version string
            "the price is 1.99",      // guards bare "1."
            "version 1.0.0 build 6",  // guards bare "1."
            "meet me at 2.30",        // guards bare "2."
        ]

        for prompt in onDevicePrompts {
            XCTAssertEqual(
                route(prompt), .onDevice,
                """
                "\(prompt)" over-escalated to the cloud. A bare "1." / "2." / "3." \
                marker was likely re-added to ReasoningRouter.answerLikelyLongMarkers, \
                reopening H8 (decimals/prices/versions/times must stay on-device).
                """
            )
        }
    }

    // MARK: - Genuine enumeration still escalates

    /// The intended behavior the H8 fix preserved: a real numbered list of asks is
    /// a "short prompt, long answer" tell and SHOULD escalate to the cloud. This
    /// locks in that the enumeration markers ("1)" etc.) still fire.
    func testGenuineEnumerationEscalatesToCloud() {
        XCTAssertEqual(
            route("do these: 1) foo 2) bar 3) baz"), .escalateToCloud,
            #"A "1) … 2) … 3) …" enumeration should escalate; the enumeration markers must still fire."#
        )
    }

    /// Parenthesised enumeration ("(1) … (2) …") is the other retained form.
    func testParentheticalEnumerationEscalatesToCloud() {
        XCTAssertEqual(
            route("cover (1) setup (2) build (3) ship"), .escalateToCloud,
            #"A "(1) … (2) … (3) …" enumeration should escalate; the enumeration markers must still fire."#
        )
    }
}
