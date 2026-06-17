// EventsView.swift
// MTRX
//
// On-chain events — upcoming events list, ticket management, QR codes, event creation.

import SwiftUI

// MARK: - Data Models

struct EventItem: Identifiable {
    let id = UUID()
    let title: String
    let date: String
    let location: String
    let ticketPrice: String
    let remaining: Int
}

struct TicketItem: Identifiable {
    let id = UUID()
    let eventTitle: String
    let eventDate: String
    let used: Bool
}

// MARK: - View Model

@MainActor
class EventsViewModel: ObservableObject {
    @Published var events: [EventItem] = []
    @Published var tickets: [TicketItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showCreate: Bool = false
    /// True while showing bundled demo data (backend gateway not configured, or a
    /// live fetch failed). Drives the demo badge; flips to false on live data.
    @Published var isDemo: Bool = false

    // Create event form
    @Published var newTitle: String = ""
    @Published var newDate: String = ""
    @Published var newLocation: String = ""
    @Published var newPrice: String = ""

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM dd, yyyy"; return f
    }()

    func load() async {
        isLoading = true
        errorMessage = nil

        // Live when the backend gateway is configured (PendingCredentials); else
        // honest, clearly-labelled demo data. The flip needs no code change.
        if PendingCredentials.isBackendConfigured {
            do {
                let live = try await EventsService.shared.getEvents()
                events = live.map { event in
                    EventItem(
                        title: event.title,
                        date: Self.dateFormatter.string(from: event.date),
                        location: event.location,
                        ticketPrice: event.ticketPrice == 0 ? "Free" : String(format: "%.2f ETH", event.ticketPrice),
                        remaining: event.remaining
                    )
                }
                tickets = [] // user tickets require a wallet address — wired separately
                isDemo = false
                isLoading = false
                return
            } catch {
                // Live fetch failed — fall back to labelled demo, never a blank screen.
                errorMessage = "Live events unavailable — showing demo."
            }
        }

        events = EventsViewModel.sampleEvents
        tickets = EventsViewModel.sampleTickets
        isDemo = true
        isLoading = false
    }

    func buyTicket(for event: EventItem) async {
        do {
            try await Task.sleep(for: .seconds(1))
            let ticket = TicketItem(eventTitle: event.title, eventDate: event.date, used: false)
            tickets.append(ticket)
        } catch { }
    }

    // MARK: - Ticket check-in (QR)

    @Published var scanResultMessage: String?
    @Published var showScanResult: Bool = false

    /// Validate a scanned ticket QR against the user's tickets and check it in.
    /// The QR is expected to carry the ticket's id (uuid) or its event title.
    func checkInScannedTicket(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = tickets.firstIndex(where: { $0.id.uuidString == trimmed || $0.eventTitle == trimmed }) {
            let ticket = tickets[index]
            if ticket.used {
                scanResultMessage = "Ticket for \(ticket.eventTitle) was already used."
            } else {
                tickets[index] = TicketItem(eventTitle: ticket.eventTitle, eventDate: ticket.eventDate, used: true)
                scanResultMessage = "Checked in: \(ticket.eventTitle)."
            }
        } else {
            scanResultMessage = "No matching ticket found for this code."
        }
        showScanResult = true
    }

    func createEvent() async {
        guard !newTitle.isEmpty else { return }
        do {
            try await Task.sleep(for: .seconds(1))
            let event = EventItem(
                title: newTitle,
                date: newDate.isEmpty ? "TBD" : newDate,
                location: newLocation.isEmpty ? "Virtual" : newLocation,
                ticketPrice: newPrice.isEmpty ? "Free" : newPrice,
                remaining: 100
            )
            events.insert(event, at: 0)
            newTitle = ""
            newDate = ""
            newLocation = ""
            newPrice = ""
            showCreate = false
        } catch { }
    }

    static let sampleEvents: [EventItem] = [
        EventItem(title: "ETH Denver 2026", date: "May 15, 2026", location: "Denver, CO", ticketPrice: "0.05 ETH", remaining: 342),
        EventItem(title: "DeFi Summit", date: "Jun 02, 2026", location: "Singapore", ticketPrice: "0.03 ETH", remaining: 128),
        EventItem(title: "NFT Paris", date: "Jul 18, 2026", location: "Paris, FR", ticketPrice: "0.02 ETH", remaining: 56),
        EventItem(title: "Web3 Builders Night", date: "Apr 25, 2026", location: "Virtual", ticketPrice: "Free", remaining: 500)
    ]

    static let sampleTickets: [TicketItem] = [
        TicketItem(eventTitle: "ETH Denver 2026", eventDate: "May 15, 2026", used: false),
        TicketItem(eventTitle: "Consensus 2025", eventDate: "Dec 10, 2025", used: true)
    ]
}

// MARK: - Events View

struct EventsView: View {
    @StateObject private var viewModel = EventsViewModel()
    @State private var showTicketScanner = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.events.isEmpty {
                    MtrxLoadingView()
                } else if let error = viewModel.errorMessage, viewModel.events.isEmpty {
                    MtrxErrorView(message: error) {
                        Task { await viewModel.load() }
                    }
                } else {
                    eventsContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Events")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if viewModel.isDemo { DemoBadge() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showTicketScanner = true
                    } label: {
                        Image(systemName: Symbols.qrScanner)
                            .foregroundStyle(Color.accentPrimary)
                    }
                    .accessibilityLabel("Scan ticket")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showCreate = true
                    } label: {
                        Image(systemName: Symbols.addCircle)
                            .accessibilityLabel("Create event")
                            .foregroundStyle(Color.accentPrimary)
                    }
                }
            }
            .task { await viewModel.load() }
            .sheet(isPresented: $viewModel.showCreate) {
                createEventSheet
            }
            .fullScreenCover(isPresented: $showTicketScanner) {
                QRScannerSheet(title: "Scan Ticket") { code in
                    viewModel.checkInScannedTicket(code)
                }
            }
            .alert("Ticket", isPresented: $viewModel.showScanResult) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.scanResultMessage ?? "")
            }
        }
    }

    // MARK: - Content

    private var eventsContent: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionGap) {
                upcomingEventsSection
                if !viewModel.tickets.isEmpty {
                    myTicketsSection
                }
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - Upcoming Events

    private var upcomingEventsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Upcoming Events")
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.events) { event in
                eventCard(event)
            }
        }
    }

    private func eventCard(_ event: EventItem) -> some View {
        MtrxCard(style: .standard) {
            VStack(spacing: Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(event.title)
                            .font(.mtrxBodyBold)
                            .foregroundStyle(Color.labelPrimary)
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: Symbols.calendar)
                                .font(.system(size: 12))
                            Text(event.date)
                                .font(.mtrxCaption1)
                        }
                        .foregroundStyle(Color.labelSecondary)
                    }
                    Spacer()
                    MtrxBadge(text: "\(event.remaining) left", style: event.remaining < 100 ? .warning : .info)
                }

                MtrxDivider()

                HStack {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: Symbols.location)
                            .font(.system(size: 12))
                        Text(event.location)
                            .font(.mtrxCaption1)
                    }
                    .foregroundStyle(Color.labelSecondary)

                    Spacer()

                    Text(event.ticketPrice)
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.accentPrimary)
                }

                Button {
                    Task { await viewModel.buyTicket(for: event) }
                } label: {
                    Text("Buy Ticket")
                }
                .buttonStyle(MtrxButtonStyle(variant: .primary, size: .compact, fullWidth: true))
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
        .accessibilityElement(children: .combine)
    }

    // MARK: - My Tickets

    private var myTicketsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "My Tickets")
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.tickets) { ticket in
                ticketCard(ticket)
            }
        }
    }

    private func ticketCard(_ ticket: TicketItem) -> some View {
        MtrxCard(style: ticket.used ? .outlined : .glass, accentEdge: ticket.used ? nil : .leading) {
            HStack(spacing: Spacing.ms) {
                // QR placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm)
                        .fill(Color.surfaceOverlay)
                        .frame(width: 56, height: 56)
                    Image(systemName: Symbols.qrCode)
                        .font(.system(size: 24))
                        .foregroundStyle(ticket.used ? Color.labelTertiary : Color.accentPrimary)
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(ticket.eventTitle)
                        .font(.mtrxBodyBold)
                        .foregroundStyle(ticket.used ? Color.labelTertiary : Color.labelPrimary)
                    Text(ticket.eventDate)
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                }

                Spacer()

                MtrxBadge(
                    text: ticket.used ? "Used" : "Active",
                    style: ticket.used ? .neutral : .success
                )
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Create Event Sheet

    private var createEventSheet: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                MtrxSheetHeader(title: "Create Event", subtitle: "Publish an on-chain event") {
                    viewModel.showCreate = false
                }

                VStack(spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Event Title")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)
                        MtrxTextField(placeholder: "Enter event name", text: $viewModel.newTitle)
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Date")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)
                        MtrxTextField(placeholder: "e.g. Jun 15, 2026", text: $viewModel.newDate, icon: Symbols.calendar)
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Location")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)
                        MtrxTextField(placeholder: "City or Virtual", text: $viewModel.newLocation, icon: Symbols.location)
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Ticket Price")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)
                        MtrxTextField(placeholder: "0.00 ETH or Free", text: $viewModel.newPrice, keyboardType: .decimalPad)
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)

                Spacer()

                Button {
                    Task { await viewModel.createEvent() }
                } label: {
                    Text("Create Event")
                }
                .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, fullWidth: true))
                .disabled(viewModel.newTitle.isEmpty)
                .opacity(viewModel.newTitle.isEmpty ? 0.5 : 1)
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.bottom, Spacing.lg)
            }
            .background(MtrxGradientBackground(style: .primary))
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - Preview

#Preview {
    EventsView()
        .preferredColorScheme(.dark)
}
