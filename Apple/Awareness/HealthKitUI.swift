// HealthKitUI.swift
// MTRX Apple Integration — Awareness
// Native health data visualization with SwiftUI

import SwiftUI
import HealthKit

// MARK: - Health Dashboard View

struct HealthDashboardView: View {
    @StateObject private var viewModel = HealthDashboardViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // MARK: - Stress Level Card
                StressLevelCard(stressLevel: viewModel.stressLevel)

                // MARK: - Heart Rate Section
                HStack(spacing: 12) {
                    HealthMetricCard(
                        title: "Heart Rate",
                        value: viewModel.heartRate.map { String(format: "%.0f", $0) } ?? "--",
                        unit: "BPM",
                        icon: "heart.fill",
                        color: .red,
                        trend: viewModel.heartRateTrend
                    )
                    HealthMetricCard(
                        title: "HRV",
                        value: viewModel.hrv.map { String(format: "%.0f", $0) } ?? "--",
                        unit: "ms",
                        icon: "waveform.path.ecg",
                        color: .purple,
                        trend: viewModel.hrvTrend
                    )
                }

                // MARK: - Sleep Section
                if let sleep = viewModel.sleepSummary {
                    SleepCard(summary: sleep)
                }

                // MARK: - Activity Section
                if let activity = viewModel.activitySummary {
                    ActivityCard(summary: activity)
                }

                // MARK: - Trinity Context Impact
                TrinityContextImpactCard(snapshot: viewModel.latestSnapshot)
            }
            .padding()
        }
        .navigationTitle("Health Awareness")
        .task {
            await viewModel.loadData()
        }
    }
}

// MARK: - Stress Level Card

struct StressLevelCard: View {
    let stressLevel: HealthKitManager.StressLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(stressColor)
                Text("Stress Level")
                    .font(.headline)
                Spacer()
                Text(stressLevel.rawValue.capitalized)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(stressColor)
            }

            ProgressView(value: stressProgress)
                .tint(stressColor)

            Text(stressDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
        .shadow(radius: 2)
    }

    private var stressColor: Color {
        switch stressLevel {
        case .low: return .green
        case .moderate: return .yellow
        case .high: return .orange
        case .veryHigh: return .red
        }
    }

    private var stressProgress: Double {
        switch stressLevel {
        case .low: return 0.2
        case .moderate: return 0.45
        case .high: return 0.7
        case .veryHigh: return 0.95
        }
    }

    private var stressDescription: String {
        switch stressLevel {
        case .low: return "Trinity will present opportunities with full detail"
        case .moderate: return "Trinity will moderate alert frequency"
        case .high: return "Trinity will defer non-urgent alerts"
        case .veryHigh: return "Trinity is in calm mode — only critical alerts"
        }
    }
}

// MARK: - Health Metric Card

struct HealthMetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    let trend: MetricTrend

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 4) {
                Image(systemName: trend.icon)
                    .font(.caption2)
                Text(trend.description)
                    .font(.caption2)
            }
            .foregroundColor(trend.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
        .shadow(radius: 2)
    }
}

// MARK: - Sleep Card

struct SleepCard: View {
    let summary: HealthKitManager.SleepSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "bed.double.fill")
                    .foregroundColor(.indigo)
                Text("Sleep")
                    .font(.headline)
                Spacer()
                Text(String(format: "%.1fh", summary.totalSleepHours))
                    .font(.title2)
                    .fontWeight(.bold)
            }

            HStack(spacing: 16) {
                SleepStageBar(label: "Deep", hours: summary.deepSleepHours, color: .indigo)
                SleepStageBar(label: "REM", hours: summary.remSleepHours, color: .purple)
                SleepStageBar(label: "Quality", hours: summary.sleepQualityScore * 10, color: .blue)
            }

            Text("Awakenings: \(summary.awakenings)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
        .shadow(radius: 2)
    }
}

struct SleepStageBar: View {
    let label: String
    let hours: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(String(format: "%.1f", hours))
                .font(.caption)
                .fontWeight(.bold)
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(height: CGFloat(hours * 10))
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Activity Card

struct ActivityCard: View {
    let summary: HealthKitManager.ActivitySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "figure.run")
                    .foregroundColor(.green)
                Text("Activity")
                    .font(.headline)
            }

            HStack(spacing: 20) {
                ActivityRing(label: "Calories", value: summary.activeCalories, goal: 500, color: .red)
                ActivityRing(label: "Exercise", value: summary.exerciseMinutes, goal: 30, color: .green)
                ActivityRing(label: "Steps", value: Double(summary.stepCount), goal: 10000, color: .blue)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
        .shadow(radius: 2)
    }
}

struct ActivityRing: View {
    let label: String
    let value: Double
    let goal: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: min(CGFloat(value / goal), 1.0))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(String(format: "%.0f", value))
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            .frame(width: 50, height: 50)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Trinity Context Impact Card

struct TrinityContextImpactCard: View {
    let snapshot: HealthKitManager.HealthSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "brain")
                    .foregroundColor(.cyan)
                Text("Trinity Context Impact")
                    .font(.headline)
            }

            if let snapshot = snapshot {
                Text("Based on your current health data, Trinity is adjusting:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    ContextAdjustmentRow(label: "Alert Threshold", adjustment: alertAdjustment(for: snapshot.stressLevel))
                    ContextAdjustmentRow(label: "Response Tone", adjustment: toneAdjustment(for: snapshot.stressLevel))
                    ContextAdjustmentRow(label: "Detail Level", adjustment: detailAdjustment(for: snapshot.stressLevel))
                }
            } else {
                Text("No health data available")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
        .shadow(radius: 2)
    }

    private func alertAdjustment(for stress: HealthKitManager.StressLevel) -> String {
        switch stress {
        case .low: return "Normal"
        case .moderate: return "Reduced"
        case .high: return "Critical only"
        case .veryHigh: return "Emergency only"
        }
    }

    private func toneAdjustment(for stress: HealthKitManager.StressLevel) -> String {
        switch stress {
        case .low: return "Standard"
        case .moderate: return "Calmer"
        case .high: return "Reassuring"
        case .veryHigh: return "Minimal"
        }
    }

    private func detailAdjustment(for stress: HealthKitManager.StressLevel) -> String {
        switch stress {
        case .low: return "Full"
        case .moderate: return "Moderate"
        case .high: return "Summary"
        case .veryHigh: return "Headlines"
        }
    }
}

struct ContextAdjustmentRow: View {
    let label: String
    let adjustment: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
            Spacer()
            Text(adjustment)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.cyan)
        }
    }
}

// MARK: - Metric Trend

struct MetricTrend {
    let direction: Direction
    let description: String

    enum Direction {
        case up, down, stable
    }

    var icon: String {
        switch direction {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }

    var color: Color {
        switch direction {
        case .up: return .red
        case .down: return .green
        case .stable: return .secondary
        }
    }
}

// MARK: - View Model

@MainActor
final class HealthDashboardViewModel: ObservableObject {
    @Published var heartRate: Double?
    @Published var hrv: Double?
    @Published var sleepSummary: HealthKitManager.SleepSummary?
    @Published var activitySummary: HealthKitManager.ActivitySummary?
    @Published var stressLevel: HealthKitManager.StressLevel = .low
    @Published var heartRateTrend = MetricTrend(direction: .stable, description: "Stable")
    @Published var hrvTrend = MetricTrend(direction: .stable, description: "Stable")
    @Published var latestSnapshot: HealthKitManager.HealthSnapshot?

    func loadData() async {
        do {
            let snapshot = try await HealthKitManager.shared.currentSnapshot()
            heartRate = snapshot.heartRate
            hrv = snapshot.heartRateVariability
            sleepSummary = snapshot.sleepAnalysis
            activitySummary = snapshot.activitySummary
            stressLevel = snapshot.stressLevel
            latestSnapshot = snapshot
        } catch {
            // Handle gracefully — health data is optional
        }
    }
}
