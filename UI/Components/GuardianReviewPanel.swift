// GuardianReviewPanel.swift
// MTRX — Morpheus pre-transaction guardian: warning/recommend SURFACE (M-GUARDIAN, piece 2)
//
// A PRESENTATION-ONLY panel that shows the advisory observations from
// MorpheusGuardian.review(...) before a money action reaches the hard gate. Per
// MORPHEUS_ADVISOR_SPEC.md and the piece-2 constraints:
//
//   • ADVISORY ONLY. This view DISPLAYS observations; it owns no send/sign logic and
//     exposes no callback that changes whether an action proceeds. There is no
//     "acknowledge to continue", no required tap, no toggle the host must satisfy. The
//     user reads, then proceeds (or doesn't); the host's EXISTING gates run unchanged.
//   • READ-ONLY CONSUMPTION. It takes a plain [MorpheusGuardian.Observation] value and
//     renders it. It never calls an enforcement path and never feeds back into one.
//   • HONEST FRAMING. The observations already carry their grounding + price caveats; the
//     panel adds an explicit "this is advice, not a block" note so the advisory nature is
//     unmistakable. Nothing is shown unless the guardian grounded it.

import SwiftUI

struct GuardianReviewPanel: View {
    let observations: [MorpheusGuardian.Observation]

    var body: some View {
        if !observations.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentPrimary)
                    Text("Morpheus noticed")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.labelSecondary)
                }

                ForEach(Array(observations.enumerated()), id: \.offset) { _, obs in
                    GuardianObservationRow(observation: obs)
                }

                // Advisory, not a gate: the user decides; the existing security checks
                // (Face ID, chain lock, fail-closed send) run on every send regardless.
                Text("This is advice, not a block — you decide. Your usual security checks still run on every send.")
                    .font(.mtrxCaption2)
                    .foregroundStyle(Color.labelTertiary)
                    .padding(.top, Spacing.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .mtrxCardStyle()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Morpheus security notes. Advisory only.")
        }
    }
}

private struct GuardianObservationRow: View {
    let observation: MorpheusGuardian.Observation

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: glyph)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(observation.message)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelPrimary)
                if let rec = observation.recommendation {
                    Text(rec)
                        .font(.mtrxCaption2)
                        .foregroundStyle(Color.labelSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var glyph: String {
        switch observation.severity {
        case .info:    return "info.circle"
        case .caution: return "exclamationmark.triangle"
        case .high:    return "exclamationmark.octagon"
        }
    }
    private var tint: Color {
        switch observation.severity {
        case .info:    return Color.labelSecondary
        case .caution: return Color.statusWarning
        case .high:    return Color.statusError
        }
    }
}
