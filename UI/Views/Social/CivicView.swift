// CivicView.swift
// MTRX -- Civic engagement (non-binding participation) + the honest
// research roadmap toward verifiable elections. Lives inside Governance.
// Copyright 2026 OPN MATRX. All rights reserved.

import SwiftUI

// MARK: - View Model

@MainActor
final class CivicViewModel: ObservableObject {

    struct Poll: Identifiable {
        let id: String
        let category: String
        let question: String
        var options: [Option]
        let closes: String

        struct Option: Identifiable {
            let id = UUID()
            let label: String
            var votes: Int
        }

        var totalVotes: Int { options.reduce(0) { $0 + $1.votes } }
    }

    struct Official: Identifiable {
        let id = UUID()
        let initials: String
        let name: String
        let office: String
        let level: String          // Local / State / Federal
        let recentAction: String
    }

    struct ElectionInfo: Identifiable {
        let id = UUID()
        let title: String
        let date: String
        let type: String           // General / Primary / Local / Ballot measure
        let detail: String
    }

    @Published var polls: [Poll] = []
    @Published var votedPollIDs: Set<String> = []
    @Published var chosenOption: [String: UUID] = [:]
    @Published var officials: [Official] = []
    @Published var elections: [ElectionInfo] = []

    init() { load() }

    func vote(pollID: String, option: Poll.Option) {
        guard !votedPollIDs.contains(pollID),
              let p = polls.firstIndex(where: { $0.id == pollID }),
              let o = polls[p].options.firstIndex(where: { $0.id == option.id }) else { return }
        polls[p].options[o].votes += 1
        votedPollIDs.insert(pollID)
        chosenOption[pollID] = option.id
        MtrxHaptics.success()
    }

    private func load() {
        polls = [
            Poll(id: "CP-08", category: "Infrastructure",
                 question: "Should the city prioritize protected bike lanes on Main Street next budget cycle?",
                 options: [.init(label: "Yes, prioritize them", votes: 1840),
                           .init(label: "No, other priorities first", votes: 920),
                           .init(label: "Need more information", votes: 410)],
                 closes: "Closes in 4 days"),
            Poll(id: "CP-07", category: "Education",
                 question: "Where should new state education funding go first?",
                 options: [.init(label: "Teacher pay", votes: 3120),
                           .init(label: "Classroom technology", votes: 1190),
                           .init(label: "Facilities & safety", votes: 2050)],
                 closes: "Closes in 9 days"),
            Poll(id: "CP-06", category: "Environment",
                 question: "Support a community solar program funded by a small utility surcharge?",
                 options: [.init(label: "Support", votes: 2670),
                           .init(label: "Oppose", votes: 1340)],
                 closes: "Closes in 2 days"),
        ]

        officials = [
            .init(initials: "JR", name: "Jordan Rivera", office: "City Council, District 4",
                  level: "Local", recentAction: "Voted FOR the affordable housing ordinance"),
            .init(initials: "SM", name: "Sam Mitchell", office: "State Assembly, Seat 12",
                  level: "State", recentAction: "Co-sponsored the clean-water funding bill"),
            .init(initials: "AC", name: "Alex Chen", office: "U.S. House, District 7",
                  level: "Federal", recentAction: "Voted AGAINST the budget continuing resolution"),
        ]

        elections = [
            .init(title: "Municipal General Election", date: "Nov 3, 2026", type: "General",
                  detail: "Mayor, city council seats, and two local ballot measures."),
            .init(title: "School Board Special Election", date: "Mar 17, 2026", type: "Local",
                  detail: "Two open seats. Check your registration and polling place with your county clerk."),
            .init(title: "Statewide Primary", date: "Jun 2, 2026", type: "Primary",
                  detail: "Party primaries for governor and state legislature."),
        ]
    }
}

// MARK: - Civic Engagement Hub

struct CivicGovernanceView: View {
    @StateObject private var vm = CivicViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                introCard
                pollsSection
                officialsSection
                electionsSection
                roadmapLink
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.bottom, Spacing.xxl)
        }
        .background(MtrxGradientBackground(style: .primary))
        .navigationTitle("Civic")
        .navigationBarTitleDisplayMode(.inline)
    }

    // Intro + honesty disclaimer
    private var introCard: some View {
        MtrxCard(style: .glass) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentPrimary)
                    Text("Your voice in public decisions")
                        .font(.mtrxHeadline)
                        .foregroundStyle(Color.labelPrimary)
                }
                Text("Weigh in on civic issues, see how your representatives vote, and stay on top of upcoming elections — right here.")
                    .font(.mtrxSubheadline)
                    .foregroundStyle(Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                MtrxDivider()

                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.labelTertiary)
                    Text("These are non-binding engagement tools — not official ballots. Cast your government ballot through your election authority. See the Verifiable Elections roadmap below for the path toward secure in-app voting.")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Community Polls

    private var pollsSection: some View {
        VStack(spacing: Spacing.ms) {
            MtrxSectionHeader(title: "Community Polls")
            ForEach($vm.polls) { $poll in
                pollCard(poll)
            }
        }
    }

    private func pollCard(_ poll: CivicViewModel.Poll) -> some View {
        let voted = vm.votedPollIDs.contains(poll.id)
        return MtrxCard(style: .standard) {
            VStack(alignment: .leading, spacing: Spacing.ms) {
                HStack {
                    MtrxBadge(text: poll.category, style: .accent)
                    Spacer()
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "clock").font(.system(size: 11))
                        Text(poll.closes).font(.mtrxCaption2)
                    }
                    .foregroundStyle(Color.labelTertiary)
                }

                Text(poll.question)
                    .font(.mtrxHeadline)
                    .foregroundStyle(Color.labelPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: Spacing.sm) {
                    ForEach(poll.options) { option in
                        pollOptionRow(poll: poll, option: option, voted: voted)
                    }
                }

                HStack(spacing: Spacing.xs) {
                    if voted {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.statusSuccess)
                        Text("Your response recorded · \(poll.totalVotes) participated")
                            .foregroundStyle(Color.statusSuccess)
                    } else {
                        Text("\(poll.totalVotes) people have weighed in · non-binding")
                            .foregroundStyle(Color.labelTertiary)
                    }
                }
                .font(.mtrxCaption2)
            }
        }
    }

    private func pollOptionRow(poll: CivicViewModel.Poll,
                               option: CivicViewModel.Poll.Option,
                               voted: Bool) -> some View {
        let pct = poll.totalVotes > 0 ? Double(option.votes) / Double(poll.totalVotes) : 0
        let isChosen = vm.chosenOption[poll.id] == option.id

        return Button {
            vm.vote(pollID: poll.id, option: option)
        } label: {
            ZStack(alignment: .leading) {
                // Result fill (shown once voted)
                if voted {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous)
                            .fill((isChosen ? Color.accentPrimary : Color.labelTertiary).opacity(0.18))
                            .frame(width: max(geo.size.width * pct, 6))
                    }
                }
                HStack {
                    Text(option.label)
                        .font(.mtrxCallout)
                        .foregroundStyle(Color.labelPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    if voted {
                        Text("\(Int((pct * 100).rounded()))%")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(isChosen ? Color.accentPrimary : Color.labelSecondary)
                    } else if isChosen {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentPrimary)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
            .frame(minHeight: 44)
            .background(Color.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous)
                    .stroke(isChosen ? Color.accentPrimary : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(voted)
    }

    // MARK: Representatives

    private var officialsSection: some View {
        VStack(spacing: Spacing.ms) {
            MtrxSectionHeader(title: "Your Representatives")
            ForEach(vm.officials) { official in
                MtrxCard(style: .standard) {
                    HStack(spacing: Spacing.md) {
                        Text(official.initials)
                            .font(.mtrxCalloutBold)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.accentPrimary.opacity(0.85))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: Spacing.xs) {
                                Text(official.name)
                                    .font(.mtrxHeadline)
                                    .foregroundStyle(Color.labelPrimary)
                                MtrxBadge(text: official.level, style: .neutral)
                            }
                            Text(official.office)
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelSecondary)
                            Text(official.recentAction)
                                .font(.mtrxCaption2)
                                .foregroundStyle(Color.labelTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // MARK: Elections info

    private var electionsSection: some View {
        VStack(spacing: Spacing.ms) {
            MtrxSectionHeader(title: "Elections & Ballot Info")
            ForEach(vm.elections) { e in
                MtrxCard(style: .outlined) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack {
                            MtrxBadge(text: e.type, style: .info)
                            Spacer()
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "calendar").font(.system(size: 12))
                                Text(e.date).font(.mtrxCaptionBold)
                            }
                            .foregroundStyle(Color.accentPrimary)
                        }
                        Text(e.title)
                            .font(.mtrxHeadline)
                            .foregroundStyle(Color.labelPrimary)
                        Text(e.detail)
                            .font(.mtrxSubheadline)
                            .foregroundStyle(Color.labelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.labelTertiary)
                Text("Always confirm registration, deadlines, and polling locations with your official election authority. MTRX surfaces information — it does not cast your official ballot.")
                    .font(.mtrxCaption2)
                    .foregroundStyle(Color.labelTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Spacing.xs)
        }
    }

    private var roadmapLink: some View {
        NavigationLink {
            VerifiableElectionsRoadmapView()
        } label: {
            MtrxCard(style: .glass) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.accentPrimary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Verifiable Elections Roadmap")
                            .font(.mtrxHeadline)
                            .foregroundStyle(Color.labelPrimary)
                        Text("How we're building toward secure, binding in-app voting — and the bars we must clear first.")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.labelTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Verifiable Elections Roadmap

struct VerifiableElectionsRoadmapView: View {

    struct Pillar: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
        let status: String
        let statusStyle: MtrxBadge.BadgeStyle
    }

    struct Phase: Identifiable {
        let id = UUID()
        let label: String
        let title: String
        let detail: String
        let done: Bool
    }

    private let pillars: [Pillar] = [
        .init(icon: "person.badge.shield.checkmark.fill",
              title: "Eligibility without de-anonymization",
              detail: "Strong multi-factor verification (including 3FA) proves a person is an eligible, unique voter — without ever linking them to the contents of their ballot.",
              status: "In design", statusStyle: .info),
        .init(icon: "eye.slash.fill",
              title: "The secret ballot & coercion resistance",
              detail: "No one — not even the voter — can prove how they voted, so votes cannot be bought or coerced. This is the hardest requirement and remains an open research problem for remote voting.",
              status: "Research", statusStyle: .warning),
        .init(icon: "checkmark.seal.fill",
              title: "End-to-end verifiability (E2E-V)",
              detail: "Every voter can independently confirm their vote was recorded as cast and counted as recorded — without having to trust the app or the servers.",
              status: "Research", statusStyle: .warning),
        .init(icon: "doc.text.magnifyingglass",
              title: "Software independence + audit trail",
              detail: "An undetected bug or attack must be unable to change the outcome. Voter-verifiable records enable risk-limiting audits and meaningful recounts.",
              status: "Required", statusStyle: .neutral),
        .init(icon: "iphone.gen3.radiowaves.left.and.right",
              title: "The trusted-endpoint problem",
              detail: "Defending the result against malware on a voter's own device — which can misreport what was submitted. No authentication alone solves this.",
              status: "Open problem", statusStyle: .warning),
        .init(icon: "doc.plaintext.fill",
              title: "Open protocol & adversarial review",
              detail: "A fully public specification, independent red-teaming, and published findings — before any binding use. Security through transparency, not obscurity.",
              status: "Committed", statusStyle: .success),
        .init(icon: "building.columns.fill",
              title: "Authority partnership & certification",
              detail: "Binding public elections are run under election law. Any official use must be authorized and certified by the relevant election authority — never shipped unilaterally by an app.",
              status: "Prerequisite", statusStyle: .neutral),
    ]

    private let phases: [Phase] = [
        .init(label: "Phase 1 · Now",
              title: "Non-binding civic participation",
              detail: "Community polls, representative transparency, and election information — live today, with zero binding-election risk.",
              done: true),
        .init(label: "Phase 2 · Next",
              title: "Verifiable pilots, low stakes",
              detail: "Pilot an E2E-verifiable, coercion-resistant protocol on opt-in, non-sovereign elections (communities, organizations) — fully open to public audit.",
              done: false),
        .init(label: "Phase 3 · Gated",
              title: "Certified, authority-run elections",
              detail: "Only after every bar above is cleared and independently certified, in partnership with election authorities, would any binding government vote be considered.",
              done: false),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                statusBanner
                requirementsSection
                phasesSection
                footerNote
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.bottom, Spacing.xxl)
        }
        .background(MtrxGradientBackground(style: .primary))
        .navigationTitle("Verifiable Elections")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusBanner: some View {
        MtrxCard(style: .glass) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentPrimary)
                    Text("Current status")
                        .font(.mtrxHeadline)
                        .foregroundStyle(Color.labelPrimary)
                    Spacer()
                    MtrxBadge(text: "Not yet certified", style: .warning)
                }
                Text("MTRX Civic is for engagement and non-binding participation today. Binding government elections are one of the hardest problems in security — the expert consensus is that remote app voting isn't safe for sovereign elections yet. These are the bars that must be cleared, with the security community and election authorities, before that could ever be responsible.")
                    .font(.mtrxSubheadline)
                    .foregroundStyle(Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var requirementsSection: some View {
        VStack(spacing: Spacing.ms) {
            MtrxSectionHeader(title: "What it must clear")
            ForEach(pillars) { pillar in
                MtrxCard(style: .standard) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: pillar.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(Color.accentPrimary)
                                .frame(width: 28)
                            Text(pillar.title)
                                .font(.mtrxCalloutBold)
                                .foregroundStyle(Color.labelPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: Spacing.xs)
                            MtrxBadge(text: pillar.status, style: pillar.statusStyle)
                        }
                        Text(pillar.detail)
                            .font(.mtrxSubheadline)
                            .foregroundStyle(Color.labelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var phasesSection: some View {
        VStack(spacing: Spacing.ms) {
            MtrxSectionHeader(title: "The path")
            ForEach(phases) { phase in
                MtrxCard(style: .outlined) {
                    HStack(alignment: .top, spacing: Spacing.md) {
                        Image(systemName: phase.done ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.system(size: 20))
                            .foregroundStyle(phase.done ? Color.statusSuccess : Color.labelTertiary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(phase.label)
                                .font(.mtrxCaption2)
                                .foregroundStyle(Color.labelTertiary)
                            Text(phase.title)
                                .font(.mtrxHeadline)
                                .foregroundStyle(Color.labelPrimary)
                            Text(phase.detail)
                                .font(.mtrxSubheadline)
                                .foregroundStyle(Color.labelSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var footerNote: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "text.book.closed.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.labelTertiary)
            Text("Grounded in election-security research (e.g. the U.S. National Academies' Securing the Vote and academic work on end-to-end-verifiable voting). Strong authentication is necessary but never sufficient — the secret ballot, verifiability, and software independence are what protect a democracy.")
                .font(.mtrxCaption2)
                .foregroundStyle(Color.labelTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Preview

#Preview("Civic") {
    NavigationStack { CivicGovernanceView() }
}
