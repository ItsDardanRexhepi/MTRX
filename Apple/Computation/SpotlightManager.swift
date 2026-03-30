// SpotlightManager.swift
// MTRX Apple Integration — Computation
//
// CoreSpotlight for system-level search of transactions, contracts, assets

import CoreSpotlight
import MobileCoreServices
import Foundation

// MARK: - SpotlightManager

final class SpotlightManager {

    static let shared = SpotlightManager()

    private let domainIdentifier = "com.mtrx.spotlight"

    // MARK: - Index Transaction

    func indexTransaction(id: String, type: String, amount: String, token: String, counterparty: String, date: Date) {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = "\(type): \(amount) \(token)"
        attributes.contentDescription = "Transaction with \(counterparty)"
        attributes.keywords = [type, token, counterparty, "transaction", "MTRX"]
        attributes.timestamp = date

        let item = CSSearchableItem(
            uniqueIdentifier: "transaction-\(id)",
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )
        item.expirationDate = Calendar.current.date(byAdding: .year, value: 1, to: date)

        CSSearchableIndex.default().indexSearchableItems([item]) { _ in }
    }

    // MARK: - Index Contract

    func indexContract(id: String, title: String, parties: [String], status: String, createdAt: Date) {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = title
        attributes.contentDescription = "Contract - \(status) - Parties: \(parties.joined(separator: ", "))"
        attributes.keywords = ["contract", status, "MTRX"] + parties
        attributes.timestamp = createdAt

        let item = CSSearchableItem(
            uniqueIdentifier: "contract-\(id)",
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )

        CSSearchableIndex.default().indexSearchableItems([item]) { _ in }
    }

    // MARK: - Index Asset

    func indexAsset(id: String, name: String, type: String, value: Double) {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = name
        attributes.contentDescription = "\(type) asset - Value: $\(String(format: "%.2f", value))"
        attributes.keywords = [type, name, "asset", "MTRX"]

        let item = CSSearchableItem(
            uniqueIdentifier: "asset-\(id)",
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )

        CSSearchableIndex.default().indexSearchableItems([item]) { _ in }
    }

    // MARK: - Index Proposal

    func indexProposal(id: String, title: String, daoId: String, status: String, deadline: Date) {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = "Vote: \(title)"
        attributes.contentDescription = "Governance proposal - \(status) - Deadline: \(deadline)"
        attributes.keywords = ["governance", "vote", "proposal", status, "MTRX"]
        attributes.timestamp = deadline

        let item = CSSearchableItem(
            uniqueIdentifier: "proposal-\(id)",
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )

        CSSearchableIndex.default().indexSearchableItems([item]) { _ in }
    }

    // MARK: - Remove

    func removeItem(id: String) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [id]) { _ in }
    }

    func removeAllItems() {
        CSSearchableIndex.default().deleteAllSearchableItems { _ in }
    }

    func removeItems(domain: String) {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in }
    }

    // MARK: - Handle User Activity

    func handleSpotlightActivity(_ activity: NSUserActivity) -> (type: String, id: String)? {
        guard activity.activityType == CSSearchableItemActionType,
              let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
            return nil
        }

        let components = identifier.split(separator: "-", maxSplits: 1)
        guard components.count == 2 else { return nil }
        return (type: String(components[0]), id: String(components[1]))
    }
}
