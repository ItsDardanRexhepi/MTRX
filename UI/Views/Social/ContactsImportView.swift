// ContactsImportView.swift
// MTRX -- Import phone contacts to connect with people you already know
// Copyright 2026 OPN MATRX. All rights reserved.

import SwiftUI
import Contacts
import UIKit

// MARK: - Model

/// A person pulled from the device address book that we can reach on MTRX.
struct PhoneContact: Identifiable, Equatable {
    let id: String
    let fullName: String
    /// Phone number or email — how we'd reach them.
    let detail: String
    let initials: String
    let color: Color

    static func == (lhs: PhoneContact, rhs: PhoneContact) -> Bool { lhs.id == rhs.id }
}

// MARK: - View Model

@MainActor
final class ContactsImportViewModel: ObservableObject {

    @Published var contacts: [PhoneContact] = []
    @Published var status: CNAuthorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    @Published var isLoading = false
    @Published var searchText = ""

    private let palette: [Color] = [
        .accentPrimary, .accentSecondary, .accentTertiary,
        .statusInfo, .statusSuccess, .trinityPrimary
    ]

    /// Whether we're allowed to read the address book (full or limited).
    var hasAccess: Bool {
        if status == .authorized { return true }
        if #available(iOS 18.0, *), status == .limited { return true }
        return false
    }

    /// Access was explicitly turned off — only changeable from Settings.
    var isDenied: Bool { status == .denied || status == .restricted }

    /// Contacts filtered by the live search field.
    var filtered: [PhoneContact] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return contacts }
        return contacts.filter {
            $0.fullName.lowercased().contains(q) || $0.detail.lowercased().contains(q)
        }
    }

    /// Ask for permission if needed, then pull the address book in.
    func importContacts() {
        status = CNContactStore.authorizationStatus(for: .contacts)
        if isDenied { return }                      // only changeable from Settings
        if hasAccess { fetch(); return }

        // .notDetermined — prompt the system permission dialog.
        isLoading = true
        CNContactStore().requestAccess(for: .contacts) { [weak self] granted, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.status = CNContactStore.authorizationStatus(for: .contacts)
                if granted { self.fetch() } else { self.isLoading = false }
            }
        }
    }

    /// Reload silently if we already have access (e.g. returning to the screen).
    func loadIfAuthorized() {
        status = CNContactStore.authorizationStatus(for: .contacts)
        if hasAccess && contacts.isEmpty { fetch() }
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Fetch

    private func fetch() {
        isLoading = true
        let palette = self.palette
        Task.detached(priority: .userInitiated) {
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactEmailAddressesKey as CNKeyDescriptor
            ]
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.sortOrder = .givenName

            var results: [PhoneContact] = []
            var seen = Set<String>()
            do {
                try CNContactStore().enumerateContacts(with: request) { contact, _ in
                    let first = contact.givenName.trimmingCharacters(in: .whitespaces)
                    let last = contact.familyName.trimmingCharacters(in: .whitespaces)
                    let full = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
                    guard !full.isEmpty else { return }

                    let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
                    let email = contact.emailAddresses.first.map { $0.value as String } ?? ""
                    let detail = !phone.isEmpty ? phone : email
                    guard !detail.isEmpty else { return }   // only people we can reach

                    let key = (full + "|" + detail).lowercased()
                    guard !seen.contains(key) else { return }
                    seen.insert(key)

                    let initials = Self.initials(first: first, last: last, full: full)
                    let color = palette[abs(full.hashValue % palette.count)]
                    results.append(PhoneContact(
                        id: contact.identifier,
                        fullName: full,
                        detail: detail,
                        initials: initials,
                        color: color
                    ))
                }
            } catch {
                // surfaced as an empty list in the UI
            }

            let sorted = results.sorted {
                $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
            }
            await MainActor.run { [weak self] in
                self?.contacts = sorted
                self?.isLoading = false
            }
        }
    }

    private nonisolated static func initials(first: String, last: String, full: String) -> String {
        let f = first.first.map(String.init) ?? ""
        let l = last.first.map(String.init) ?? ""
        let combined = f + l
        if !combined.isEmpty { return combined.uppercased() }
        return String(full.prefix(2)).uppercased()
    }
}

// MARK: - View

struct ContactsImportView: View {

    @StateObject private var vm = ContactsImportViewModel()

    /// Called when the user taps Connect on a contact.
    var onSelect: (PhoneContact) -> Void

    @State private var connected: Set<String> = []

    var body: some View {
        Group {
            if vm.hasAccess {
                if vm.isLoading && vm.contacts.isEmpty {
                    loadingState
                } else if vm.contacts.isEmpty {
                    noContactsState
                } else {
                    contactList
                }
            } else if vm.isDenied {
                deniedState
            } else {
                introState
            }
        }
        .onAppear { vm.loadIfAuthorized() }
    }

    // MARK: States

    private var introState: some View {
        MtrxEmptyState(
            icon: "person.crop.circle.badge.plus",
            title: "Import Your Contacts",
            message: "Find people you already know and start an encrypted conversation. Your contacts stay private on your device.",
            actionLabel: "Import Contacts"
        ) {
            MtrxHaptics.impact(.medium)
            vm.importContacts()
        }
    }

    private var deniedState: some View {
        MtrxEmptyState(
            icon: "lock.fill",
            title: "Contacts Access Off",
            message: "Turn on Contacts access in Settings to find people you know and connect with them on MTRX.",
            actionLabel: "Open Settings"
        ) {
            vm.openSettings()
        }
    }

    private var loadingState: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
            Text("Importing contacts…")
                .font(.mtrxBody)
                .foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noContactsState: some View {
        MtrxEmptyState(
            icon: "person.2",
            title: "No Contacts Found",
            message: "We couldn't find any contacts with a phone number or email to connect with."
        )
    }

    // MARK: List

    private var contactList: some View {
        VStack(spacing: 0) {
            searchBar
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(vm.filtered) { contact in
                        contactRow(contact)
                        MtrxDivider().padding(.leading, 72)
                    }
                }
                .padding(.top, Spacing.xs)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: Symbols.search)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.labelTertiary)
            TextField("Search contacts", text: $vm.searchText)
                .font(.mtrxBody)
                .foregroundStyle(Color.labelPrimary)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.surfaceOverlay)
        .clipShape(Capsule())
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    private func contactRow(_ contact: PhoneContact) -> some View {
        HStack(spacing: Spacing.avatarContentGap) {
            MtrxAvatar(text: contact.initials, color: contact.color, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.fullName)
                    .font(.mtrxBodyBold)
                    .foregroundStyle(Color.labelPrimary)
                Text(contact.detail)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(1)
            }

            Spacer()
            connectButton(contact)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.listRowVertical)
        .contentShape(Rectangle())
    }

    private func connectButton(_ contact: PhoneContact) -> some View {
        let isConnected = connected.contains(contact.id)
        return Button {
            MtrxHaptics.impact(.light)
            connected.insert(contact.id)
            onSelect(contact)
        } label: {
            Text(isConnected ? "Open" : "Connect")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(isConnected ? Color.labelSecondary : .white)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 7)
                .background(isConnected ? Color.surfaceOverlay : Color.accentPrimary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
