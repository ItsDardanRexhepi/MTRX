// ContactsManager.swift
// MTRX Apple Integration — Interaction
//
// Contacts framework for wallet address suggestions from address book

import Contacts
import Foundation

// MARK: - ContactsManager

final class ContactsManager: ObservableObject {

    static let shared = ContactsManager()

    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var mtrxContacts: [MTRXContact] = []

    private let contactStore = CNContactStore()
    private let walletAddressKey = "MTRX Wallet"

    // MARK: - Authorization

    func requestAccess() async throws -> Bool {
        let granted = try await contactStore.requestAccess(for: .contacts)
        await MainActor.run { isAuthorized = granted }
        return granted
    }

    // MARK: - Fetch Contacts with Wallet Addresses

    func fetchMTRXContacts() throws -> [MTRXContact] {
        guard isAuthorized else { throw ContactsError.notAuthorized }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
            CNContactNoteKey as CNKeyDescriptor,
            CNContactInstantMessageAddressesKey as CNKeyDescriptor
        ]

        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        var contacts: [MTRXContact] = []

        try contactStore.enumerateContacts(with: request) { contact, _ in
            // Look for wallet address in instant messages or notes
            let walletFromIM = contact.instantMessageAddresses.first(where: {
                $0.value.service == self.walletAddressKey
            })?.value.username

            let walletFromNote = self.extractWalletAddress(from: contact.note)
            let walletAddress = walletFromIM ?? walletFromNote

            if let wallet = walletAddress {
                let mtrxContact = MTRXContact(
                    id: contact.identifier,
                    givenName: contact.givenName,
                    familyName: contact.familyName,
                    walletAddress: wallet,
                    email: contact.emailAddresses.first?.value as String?,
                    phoneNumber: contact.phoneNumbers.first?.value.stringValue,
                    hasImage: contact.imageDataAvailable,
                    thumbnailData: contact.thumbnailImageData
                )
                contacts.append(mtrxContact)
            }
        }

        let resolved = contacts
        Task { @MainActor in mtrxContacts = resolved }
        return resolved
    }

    // MARK: - Search

    func searchContacts(query: String) throws -> [MTRXContact] {
        let allContacts = try fetchMTRXContacts()
        let lowered = query.lowercased()
        return allContacts.filter {
            $0.fullName.lowercased().contains(lowered) ||
            $0.walletAddress.lowercased().contains(lowered)
        }
    }

    // MARK: - Save Wallet Address

    func saveWalletAddress(_ address: String, to contactId: String) throws {
        guard isAuthorized else { throw ContactsError.notAuthorized }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactInstantMessageAddressesKey as CNKeyDescriptor
        ]

        guard let contact = try? contactStore.unifiedContact(withIdentifier: contactId, keysToFetch: keysToFetch) else {
            throw ContactsError.contactNotFound
        }

        let mutableContact = contact.mutableCopy() as! CNMutableContact
        let walletIM = CNInstantMessageAddress(username: address, service: walletAddressKey)
        let labeledValue = CNLabeledValue(label: walletAddressKey, value: walletIM)
        mutableContact.instantMessageAddresses.append(labeledValue)

        let saveRequest = CNSaveRequest()
        saveRequest.update(mutableContact)
        try contactStore.execute(saveRequest)
    }

    // MARK: - Suggestions

    func suggestRecipients(for partialAddress: String) -> [MTRXContact] {
        mtrxContacts.filter { $0.walletAddress.lowercased().hasPrefix(partialAddress.lowercased()) }
    }

    // MARK: - Private

    private func extractWalletAddress(from note: String) -> String? {
        let pattern = "0x[a-fA-F0-9]{40}"
        if let range = note.range(of: pattern, options: .regularExpression) {
            return String(note[range])
        }
        return nil
    }
}

// MARK: - MTRXContact

struct MTRXContact: Identifiable {
    let id: String
    let givenName: String
    let familyName: String
    let walletAddress: String
    let email: String?
    let phoneNumber: String?
    let hasImage: Bool
    let thumbnailData: Data?

    var fullName: String { "\(givenName) \(familyName)".trimmingCharacters(in: .whitespaces) }
    var shortAddress: String { String(walletAddress.prefix(6)) + "..." + String(walletAddress.suffix(4)) }
}

// MARK: - ContactsError

enum ContactsError: LocalizedError {
    case notAuthorized
    case contactNotFound
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Contacts access not authorized."
        case .contactNotFound: return "Contact not found."
        case .saveFailed(let r): return "Failed to save contact: \(r)"
        }
    }
}
