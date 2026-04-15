// ComputeView.swift
// MTRX
//
// Decentralized compute — GPU provider marketplace, job submission, job tracking.

import SwiftUI

// MARK: - Data Models

struct ProviderItem: Identifiable {
    let id = UUID()
    let name: String
    let gpuType: String
    let pricePerHour: String
    let availability: String
    let rating: Double
}

struct JobItem: Identifiable {
    let id = UUID()
    let type: String
    let status: String
    let provider: String
    let cost: String
    let submittedAt: String
}

// MARK: - View Model

@MainActor
class ComputeViewModel: ObservableObject {
    @Published var providers: [ProviderItem] = []
    @Published var jobs: [JobItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showSubmit: Bool = false

    // Submit form
    @Published var jobType: String = "Inference"
    @Published var selectedProvider: ProviderItem?
    @Published var isSubmitting: Bool = false

    let jobTypes = ["Inference", "Training", "Fine-tuning", "Rendering"]

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            try await Task.sleep(for: .milliseconds(700))
            providers = ComputeViewModel.sampleProviders
            jobs = ComputeViewModel.sampleJobs
            isLoading = false
        } catch {
            errorMessage = "Unable to load compute data."
            isLoading = false
        }
    }

    func submitJob() async {
        guard let provider = selectedProvider else { return }
        isSubmitting = true
        do {
            try await Task.sleep(for: .seconds(1.5))
            let job = JobItem(
                type: jobType,
                status: "Queued",
                provider: provider.name,
                cost: provider.pricePerHour,
                submittedAt: "Just now"
            )
            jobs.insert(job, at: 0)
            isSubmitting = false
            showSubmit = false
            selectedProvider = nil
        } catch {
            isSubmitting = false
        }
    }

    static let sampleProviders: [ProviderItem] = [
        ProviderItem(name: "Akash Node Alpha", gpuType: "A100 80GB", pricePerHour: "$1.20/hr", availability: "High", rating: 4.8),
        ProviderItem(name: "Render Network #42", gpuType: "RTX 4090", pricePerHour: "$0.65/hr", availability: "Medium", rating: 4.5),
        ProviderItem(name: "io.net Cluster 7", gpuType: "H100 SXM", pricePerHour: "$2.50/hr", availability: "High", rating: 4.9),
        ProviderItem(name: "Nosana Worker 18", gpuType: "A6000", pricePerHour: "$0.45/hr", availability: "Low", rating: 4.2)
    ]

    static let sampleJobs: [JobItem] = [
        JobItem(type: "Inference", status: "Running", provider: "Akash Node Alpha", cost: "$3.60", submittedAt: "3h ago"),
        JobItem(type: "Training", status: "Completed", provider: "io.net Cluster 7", cost: "$48.00", submittedAt: "1d ago"),
        JobItem(type: "Fine-tuning", status: "Failed", provider: "Render Network #42", cost: "$12.35", submittedAt: "2d ago")
    ]
}

// MARK: - Compute View

struct ComputeView: View {
    @StateObject private var viewModel = ComputeViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.providers.isEmpty {
                    MtrxLoadingView()
                } else if let error = viewModel.errorMessage, viewModel.providers.isEmpty {
                    MtrxErrorView(message: error) {
                        Task { await viewModel.load() }
                    }
                } else {
                    computeContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Compute")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showSubmit = true
                    } label: {
                        Image(systemName: Symbols.addCircle)
                            .foregroundStyle(Color.accentPrimary)
                    }
                }
            }
            .task { await viewModel.load() }
            .sheet(isPresented: $viewModel.showSubmit) {
                submitJobSheet
            }
        }
    }

    // MARK: - Content

    private var computeContent: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionGap) {
                providersSection
                if !viewModel.jobs.isEmpty {
                    jobsSection
                }
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - Providers Section

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "GPU Providers")
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.providers) { provider in
                providerCard(provider)
            }
        }
    }

    private func providerCard(_ provider: ProviderItem) -> some View {
        MtrxCard(style: .standard) {
            VStack(spacing: Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(provider.name)
                            .font(.mtrxBodyBold)
                            .foregroundStyle(Color.labelPrimary)
                        Text(provider.gpuType)
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text(provider.pricePerHour)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.accentPrimary)
                        HStack(spacing: 2) {
                            Image(systemName: Symbols.reward)
                                .font(.system(size: 10))
                            Text(String(format: "%.1f", provider.rating))
                                .font(.mtrxCaptionBold)
                        }
                        .foregroundStyle(Color.accentTertiary)
                    }
                }

                HStack {
                    HStack(spacing: Spacing.xs) {
                        Circle()
                            .fill(availabilityColor(provider.availability))
                            .frame(width: 8, height: 8)
                        Text(provider.availability)
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                    }
                    Spacer()
                    Button {
                        viewModel.selectedProvider = provider
                        viewModel.showSubmit = true
                    } label: {
                        Text("Select")
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .compact))
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Jobs Section

    private var jobsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "My Jobs")
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.jobs) { job in
                jobCard(job)
            }
        }
    }

    private func jobCard(_ job: JobItem) -> some View {
        MtrxCard(style: .standard) {
            HStack(spacing: Spacing.ms) {
                MtrxAvatar(
                    symbol: jobIcon(for: job.status),
                    color: jobColor(for: job.status),
                    size: 40
                )

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.xs) {
                        Text(job.type)
                            .font(.mtrxBodyBold)
                            .foregroundStyle(Color.labelPrimary)
                        MtrxBadge(text: job.status, style: jobBadgeStyle(for: job.status))
                    }
                    HStack(spacing: Spacing.sm) {
                        Text(job.provider)
                            .font(.mtrxCaption1)
                        Text(job.submittedAt)
                            .font(.mtrxCaption1)
                    }
                    .foregroundStyle(Color.labelSecondary)
                }

                Spacer()

                Text(job.cost)
                    .font(.mtrxMonoSmall)
                    .foregroundStyle(Color.labelPrimary)
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Submit Job Sheet

    private var submitJobSheet: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                MtrxSheetHeader(title: "Submit Job", subtitle: "Run a compute job on the network") {
                    viewModel.showSubmit = false
                }

                VStack(spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Job Type")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Spacing.sm) {
                                ForEach(viewModel.jobTypes, id: \.self) { type in
                                    MtrxChip(
                                        label: type,
                                        isSelected: viewModel.jobType == type
                                    ) {
                                        viewModel.jobType = type
                                    }
                                }
                            }
                        }
                    }

                    if let provider = viewModel.selectedProvider {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Selected Provider")
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(Color.labelSecondary)

                            MtrxCard(style: .glass, accentEdge: .leading) {
                                HStack {
                                    VStack(alignment: .leading, spacing: Spacing.xs) {
                                        Text(provider.name)
                                            .font(.mtrxBodyBold)
                                            .foregroundStyle(Color.labelPrimary)
                                        Text("\(provider.gpuType) \u{2022} \(provider.pricePerHour)")
                                            .font(.mtrxCaption1)
                                            .foregroundStyle(Color.labelSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: Symbols.complete)
                                        .foregroundStyle(Color.statusSuccess)
                                }
                            }
                        }
                    } else {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: Symbols.alertInfo)
                                .font(.system(size: 14))
                                .foregroundStyle(Color.statusInfo)
                            Text("Select a provider from the list to continue.")
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelSecondary)
                        }
                        .padding(Spacing.ms)
                        .background(Color.statusInfo.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)

                Spacer()

                Button {
                    Task { await viewModel.submitJob() }
                } label: {
                    Text(viewModel.isSubmitting ? "Submitting..." : "Submit Job")
                }
                .buttonStyle(MtrxButtonStyle(
                    variant: .primary,
                    size: .large,
                    isLoading: viewModel.isSubmitting,
                    fullWidth: true
                ))
                .disabled(viewModel.selectedProvider == nil || viewModel.isSubmitting)
                .opacity(viewModel.selectedProvider == nil ? 0.5 : 1)
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.bottom, Spacing.lg)
            }
            .background(MtrxGradientBackground(style: .primary))
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Helpers

    private func availabilityColor(_ availability: String) -> Color {
        switch availability {
        case "High": return .statusSuccess
        case "Medium": return .statusWarning
        case "Low": return .statusError
        default: return .labelTertiary
        }
    }

    private func jobIcon(for status: String) -> String {
        switch status {
        case "Running": return Symbols.processing
        case "Completed": return Symbols.complete
        case "Failed": return Symbols.failed
        case "Queued": return Symbols.pending
        default: return Symbols.pending
        }
    }

    private func jobColor(for status: String) -> Color {
        switch status {
        case "Running": return .statusInfo
        case "Completed": return .statusSuccess
        case "Failed": return .statusError
        case "Queued": return .statusWarning
        default: return .labelSecondary
        }
    }

    private func jobBadgeStyle(for status: String) -> MtrxBadge.BadgeStyle {
        switch status {
        case "Running": return .info
        case "Completed": return .success
        case "Failed": return .error
        case "Queued": return .warning
        default: return .neutral
        }
    }
}

// MARK: - Preview

#Preview {
    ComputeView()
        .preferredColorScheme(.dark)
}
