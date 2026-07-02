// GameLevelSelectView.swift
// MTRX — UI/Views/Gaming
//
// The one shared level-select surface for every levelled mini-game. Reads the
// shared GameProgress store, renders a 1…50 grid with locked / unlocked /
// completed states, and hands the chosen level back to the game. Built once;
// each game presents it and starts at the returned level.

import SwiftUI

struct GameLevelSelectView: View {
    let game: GameKitManager.GameID
    let title: String
    let accent: Color
    /// Called with the chosen (unlocked) level.
    let onSelect: (Int) -> Void
    /// Called to dismiss without choosing.
    let onClose: () -> Void

    @ObservedObject private var progress = GameProgress.shared

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: 5)

    private var total: Int { progress.totalLevels(for: game) }
    private var completed: Int { progress.completedCount(for: game) }
    private var unlocked: Int { progress.unlockedLevel(for: game) }

    var body: some View {
        ZStack {
            MtrxGradientBackground(style: .primary).ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    LazyVGrid(columns: columns, spacing: Spacing.sm) {
                        ForEach(1...max(total, 1), id: \.self) { level in
                            levelTile(level)
                        }
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.xxl)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Spacing.xs) {
            HStack {
                Text(title)
                    .font(.mtrxTitle2)
                    .foregroundStyle(Color.labelPrimary)
                Spacer()
                Button {
                    MtrxHaptics.impact(.light)
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .accessibilityLabel("Close")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.labelSecondary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: Spacing.xs) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(accent)
                Text("\(completed) of \(total) levels cleared")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
                Spacer()
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
        .padding(.top, Spacing.md)
    }

    // MARK: - Tile

    @ViewBuilder
    private func levelTile(_ level: Int) -> some View {
        let isUnlocked = progress.isUnlocked(level, in: game)
        let isCompleted = progress.isCompleted(level, in: game)
        let isCurrent = isUnlocked && !isCompleted && level == unlocked

        Button {
            guard isUnlocked else { MtrxHaptics.warning(); return }
            MtrxHaptics.impact(.medium)
            onSelect(level)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isCompleted ? accent.opacity(0.22)
                          : isUnlocked ? Color.white.opacity(0.06)
                          : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isCurrent ? accent
                                          : isCompleted ? accent.opacity(0.5)
                                          : Color.white.opacity(0.08),
                                          lineWidth: isCurrent ? 2 : 1)
                    )

                if !isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.labelTertiary)
                } else if isCompleted {
                    VStack(spacing: 2) {
                        Text("\(level)")
                            .font(.mtrxCalloutBold)
                            .foregroundStyle(Color.labelPrimary)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(accent)
                    }
                } else {
                    Text("\(level)")
                        .font(.mtrxCalloutBold)
                        .foregroundStyle(isCurrent ? accent : Color.labelPrimary)
                }
            }
            .frame(height: 56)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Level \(level)\(isCompleted ? ", cleared" : isUnlocked ? "" : ", locked")")
    }
}
