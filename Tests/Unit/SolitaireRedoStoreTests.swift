import XCTest
@testable import MTRX

/// Money-seam tests for the $0.99 solitaire do-over Consumable. These exercise
/// the grant/consume/idempotency core against an isolated UserDefaults suite —
/// the parts that guard real money — without needing live StoreKit.
@MainActor
final class SolitaireRedoStoreTests: XCTestCase {

    private func freshStore() -> (SolitaireRedoStore, UserDefaults) {
        let name = "test.redo.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return (SolitaireRedoStore(defaults: d), d)
    }

    func testGrantAddsFive() {
        let (store, _) = freshStore()
        XCTAssertEqual(store.balance, 0)
        XCTAssertTrue(store.recordGrant(transactionId: 1001, redos: 5))
        XCTAssertEqual(store.balance, 5)
    }

    func testGrantIsIdempotentOnTransactionId() {
        let (store, _) = freshStore()
        // Same transaction delivered twice (purchase return + updates listener).
        XCTAssertTrue(store.recordGrant(transactionId: 42, redos: 5))
        XCTAssertFalse(store.recordGrant(transactionId: 42, redos: 5), "second delivery must not grant again")
        XCTAssertEqual(store.balance, 5, "double delivery grants exactly once")
    }

    func testDistinctTransactionsEachGrant() {
        let (store, _) = freshStore()
        store.recordGrant(transactionId: 1, redos: 5)
        store.recordGrant(transactionId: 2, redos: 5)
        XCTAssertEqual(store.balance, 10)
    }

    func testConsumeDecrementsAndFloorsAtZero() {
        let (store, _) = freshStore()
        store.recordGrant(transactionId: 7, redos: 5)
        XCTAssertTrue(store.consumeOne()); XCTAssertEqual(store.balance, 4)
        for _ in 0..<4 { XCTAssertTrue(store.consumeOne()) }
        XCTAssertEqual(store.balance, 0)
        XCTAssertFalse(store.consumeOne(), "cannot consume below zero")
        XCTAssertEqual(store.balance, 0)
    }

    func testBalancePersistsAcrossInstances() {
        let name = "test.redo.persist"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        let a = SolitaireRedoStore(defaults: d)
        a.recordGrant(transactionId: 99, redos: 5)
        a.consumeOne()
        // A fresh instance on the same defaults reads the balance AND the
        // processed-id set (so a re-delivered id still won't double-grant).
        let b = SolitaireRedoStore(defaults: d)
        XCTAssertEqual(b.balance, 4)
        XCTAssertFalse(b.recordGrant(transactionId: 99, redos: 5), "processed ids persist")
        XCTAssertEqual(b.balance, 4)
    }

    func testConsumableIsNotASubscriptionProduct() {
        // The Consumable must never collide with a subscription tier id — that
        // is what keeps a $0.99 purchase from ever granting Pro.
        XCTAssertNotEqual(SolitaireRedoStore.productId, StoreKitManager.proProductId)
        XCTAssertNotEqual(SolitaireRedoStore.productId, StoreKitManager.enterpriseProductId)
        XCTAssertEqual(SolitaireRedoStore.productId, "com.opnmatrx.mtrx.solitaire.redos5")
        XCTAssertEqual(SolitaireRedoStore.redosPerPurchase, 5)
    }

    func testGrantRejectsNonPositive() {
        let (store, _) = freshStore()
        XCTAssertFalse(store.recordGrant(transactionId: 5, redos: 0))
        XCTAssertEqual(store.balance, 0)
    }
}
