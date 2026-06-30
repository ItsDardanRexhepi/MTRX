// SecurityNarrationView.swift
// MTRX — Morpheus whole-app security narrator: display SURFACE (M-NARRATOR, piece 2)
//
// Renders the grounded statements from MorpheusNarrator.narrate() so the user can see
// what is protecting them. Per MORPHEUS_ADVISOR_SPEC.md and the piece-2 constraints:
//
//   • DISPLAY ONLY. It renders a [Statement] list; it owns no send/sign logic, exposes
//     no callback that affects anything, gates nothing, and changes no wall.
//   • READ-ONLY CONSUMPTION. The host reads MorpheusNarrator.narrate() and hands the
//     statements in; this view only displays them.
//   • NO FALSE REASSURANCE AT THE UI LAYER. It shows the INDIVIDUAL grounded statements,
//     each with its own tone. It must NOT add an aggregate "all secure" banner or any
//     summary that overstates the individual facts — there is no rollup here.

import SwiftUI

/// Renders the narrator's statements as rows. Designed to drop into a List Section (each
/// statement becomes a row) — but it adds NO aggregate/summary claim of its own.
struct SecurityNarrationView: View {
    let statements: [MorpheusNarrator.Statement]

    var body: some View {
        ForEach(Array(statements.enumerated()), id: \.offset) { _, statement in
            SecurityNarrationRow(statement: statement)
        }
    }
}

struct SecurityNarrationRow: View {
    let statement: MorpheusNarrator.Statement

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(statement.title)
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelPrimary)
                Text(statement.detail)
                    .font(.mtrxCaption2)
                    .foregroundStyle(Color.labelTertiary)
            }
        } icon: {
            Image(systemName: glyph)
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // Carry the visual tone cue (the warning glyph) into VoiceOver so an attention row
    // doesn't sound identical to a neutral one. Per-statement only — no aggregate phrasing.
    private var accessibilityText: String {
        let prefix = statement.tone == .attention ? "Needs attention: " : ""
        return "\(prefix)\(statement.title). \(statement.detail)"
    }

    // Per-statement tone styling. There is intentionally no aggregate "all secure" state —
    // each row reflects only the single grounded fact it carries.
    private var glyph: String {
        switch statement.tone {
        case .protective: return "checkmark.shield"
        case .neutral:    return "info.circle"
        case .attention:  return "exclamationmark.triangle"
        }
    }
    private var tint: Color {
        switch statement.tone {
        case .protective: return Color.statusSuccess
        case .neutral:    return Color.labelSecondary
        case .attention:  return Color.statusWarning
        }
    }
}
