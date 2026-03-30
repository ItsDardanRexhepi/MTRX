//
//  TrinityOnboarding.swift
//  MTRX — Trinity
//
//  First boot message, permission requests, and onboarding flow management.
//

import Foundation
import Combine

// MARK: - Onboarding Step

/// Represents a single step in the onboarding flow.
struct OnboardingStep: Identifiable, Sendable {
    let id: UUID
    let order: Int
    let title: String
    let description: String
    let type: StepType
    let isRequired: Bool
    var isCompleted: Bool
    var isSkipped: Bool

    enum StepType: String, Sendable {
        case welcome
        case permission
        case preference
        case tutorial
        case verification
        case completion
    }

    init(
        id: UUID = UUID(),
        order: Int,
        title: String,
        description: String,
        type: StepType,
        isRequired: Bool = true
    ) {
        self.id = id
        self.order = order
        self.title = title
        self.description = description
        self.type = type
        self.isRequired = isRequired
        self.isCompleted = false
        self.isSkipped = false
    }
}

// MARK: - Permission Type

/// System permissions MTRX may request during onboarding.
enum PermissionType: String, CaseIterable, Sendable {
    case notifications = "notifications"
    case healthKit = "healthKit"
    case location = "location"
    case camera = "camera"
    case microphone = "microphone"
    case faceID = "faceID"
    case siri = "siri"

    var displayName: String {
        switch self {
        case .notifications: return "Notifications"
        case .healthKit:     return "Health Data"
        case .location:      return "Location"
        case .camera:        return "Camera"
        case .microphone:    return "Microphone"
        case .faceID:        return "Face ID"
        case .siri:          return "Siri Integration"
        }
    }

    var description: String {
        switch self {
        case .notifications:
            return "Receive timely alerts about pivotal moments, portfolio changes, and Morpheus insights."
        case .healthKit:
            return "Integrate health data for context-aware intelligence that considers your wellbeing."
        case .location:
            return "Location-aware responses and security features like geo-fenced wallet access."
        case .camera:
            return "Scan QR codes, documents, and enable visual verification features."
        case .microphone:
            return "Voice interaction with Trinity, Morpheus, and Oracle layers."
        case .faceID:
            return "Biometric authentication for secure transactions and sensitive operations."
        case .siri:
            return "Quick access to MTRX features through Siri voice commands."
        }
    }

    /// Whether this permission is essential for core functionality.
    var isEssential: Bool {
        switch self {
        case .notifications, .faceID: return true
        default: return false
        }
    }

    /// The order in which permissions should be requested.
    var requestOrder: Int {
        switch self {
        case .notifications: return 0
        case .faceID:        return 1
        case .microphone:    return 2
        case .location:      return 3
        case .healthKit:     return 4
        case .camera:        return 5
        case .siri:          return 6
        }
    }
}

// MARK: - Permission Status

enum PermissionStatus: String, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted
}

// MARK: - Trinity Onboarding

/// Manages the first-launch onboarding flow including welcome messages,
/// permission requests, and initial user preference gathering.
@MainActor
final class TrinityOnboarding: ObservableObject {

    // MARK: - Published State

    @Published private(set) var currentStep: OnboardingStep?
    @Published private(set) var steps: [OnboardingStep] = []
    @Published private(set) var isOnboardingComplete: Bool = false
    @Published private(set) var permissionStatuses: [PermissionType: PermissionStatus] = [:]
    @Published private(set) var progress: Double = 0.0

    // MARK: - Properties

    private let defaults = UserDefaults.standard
    private let onboardingCompleteKey = "mtrx_onboarding_complete"
    private let onboardingVersionKey = "mtrx_onboarding_version"
    private let currentOnboardingVersion = 1

    // MARK: - Initialization

    init() {
        isOnboardingComplete = defaults.bool(forKey: onboardingCompleteKey)
        if !isOnboardingComplete {
            steps = buildOnboardingSteps()
            currentStep = steps.first
        }
    }

    // MARK: - Onboarding Flow

    /// Check if onboarding needs to be shown.
    var needsOnboarding: Bool {
        !isOnboardingComplete ||
        defaults.integer(forKey: onboardingVersionKey) < currentOnboardingVersion
    }

    /// Start the onboarding flow from the beginning.
    func startOnboarding() {
        steps = buildOnboardingSteps()
        currentStep = steps.first
        isOnboardingComplete = false
        updateProgress()
    }

    /// Advance to the next onboarding step.
    func advanceToNextStep() {
        guard let current = currentStep,
              let currentIndex = steps.firstIndex(where: { $0.id == current.id }) else {
            return
        }

        // Mark current step as completed
        steps[currentIndex].isCompleted = true

        let nextIndex = currentIndex + 1
        if nextIndex < steps.count {
            currentStep = steps[nextIndex]
        } else {
            completeOnboarding()
        }

        updateProgress()
    }

    /// Skip the current step (only if not required).
    func skipCurrentStep() {
        guard let current = currentStep,
              let currentIndex = steps.firstIndex(where: { $0.id == current.id }),
              !current.isRequired else {
            return
        }

        steps[currentIndex].isSkipped = true
        advanceToNextStep()
    }

    /// Complete the onboarding flow.
    func completeOnboarding() {
        isOnboardingComplete = true
        currentStep = nil
        defaults.set(true, forKey: onboardingCompleteKey)
        defaults.set(currentOnboardingVersion, forKey: onboardingVersionKey)
    }

    // MARK: - Permission Requests

    /// Request a specific permission.
    /// - Parameter permission: The permission to request.
    /// - Returns: The resulting permission status.
    func requestPermission(_ permission: PermissionType) async -> PermissionStatus {
        // TODO: Implement actual permission requests using system APIs
        // - Notifications: UNUserNotificationCenter
        // - HealthKit: HKHealthStore
        // - Location: CLLocationManager
        // - Camera/Microphone: AVCaptureDevice
        // - FaceID: LAContext
        // - Siri: INPreferences

        let status: PermissionStatus

        switch permission {
        case .notifications:
            status = await requestNotificationPermission()
        case .healthKit:
            status = await requestHealthKitPermission()
        case .location:
            status = await requestLocationPermission()
        case .camera:
            status = await requestCameraPermission()
        case .microphone:
            status = await requestMicrophonePermission()
        case .faceID:
            status = await requestFaceIDPermission()
        case .siri:
            status = await requestSiriPermission()
        }

        permissionStatuses[permission] = status
        return status
    }

    /// Request all permissions in the recommended order.
    func requestAllPermissions() async {
        let sortedPermissions = PermissionType.allCases.sorted { $0.requestOrder < $1.requestOrder }
        for permission in sortedPermissions {
            _ = await requestPermission(permission)
        }
    }

    // MARK: - Welcome Message

    /// Generate the welcome message for first boot.
    /// - Returns: The personalized welcome message.
    func generateWelcomeMessage() -> WelcomeMessage {
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting: String
        switch hour {
        case 5..<12:  greeting = "Good morning"
        case 12..<17: greeting = "Good afternoon"
        case 17..<22: greeting = "Good evening"
        default:       greeting = "Welcome"
        }

        return WelcomeMessage(
            greeting: greeting,
            title: "Welcome to MTRX",
            subtitle: "Your intelligent financial companion",
            body: """
                I'm Trinity, your primary interface to the MTRX ecosystem. \
                I'll help you navigate your financial world with intelligence, clarity, and precision.

                Before we begin, I'll need a few permissions to provide you with the best experience. \
                Each permission enhances a specific capability — I'll explain why each one matters.
                """,
            ctaTitle: "Let's Get Started"
        )
    }

    // MARK: - Private Helpers

    private func buildOnboardingSteps() -> [OnboardingStep] {
        var steps: [OnboardingStep] = []
        var order = 0

        // Welcome step
        steps.append(OnboardingStep(
            order: order,
            title: "Welcome to MTRX",
            description: "Meet Trinity, your intelligent financial companion.",
            type: .welcome,
            isRequired: true
        ))
        order += 1

        // Permission steps
        for permission in PermissionType.allCases.sorted(by: { $0.requestOrder < $1.requestOrder }) {
            steps.append(OnboardingStep(
                order: order,
                title: permission.displayName,
                description: permission.description,
                type: .permission,
                isRequired: permission.isEssential
            ))
            order += 1
        }

        // Preference step
        steps.append(OnboardingStep(
            order: order,
            title: "Your Preferences",
            description: "Tell us about your risk tolerance and communication preferences.",
            type: .preference,
            isRequired: false
        ))
        order += 1

        // Completion step
        steps.append(OnboardingStep(
            order: order,
            title: "You're All Set",
            description: "MTRX is ready to assist you.",
            type: .completion,
            isRequired: true
        ))

        return steps
    }

    private func updateProgress() {
        let completedCount = steps.filter { $0.isCompleted || $0.isSkipped }.count
        progress = steps.isEmpty ? 0 : Double(completedCount) / Double(steps.count)
    }

    // MARK: - Permission Request Stubs

    private func requestNotificationPermission() async -> PermissionStatus {
        // TODO: Implement with UNUserNotificationCenter.current().requestAuthorization
        return .notDetermined
    }

    private func requestHealthKitPermission() async -> PermissionStatus {
        // TODO: Implement with HKHealthStore().requestAuthorization
        return .notDetermined
    }

    private func requestLocationPermission() async -> PermissionStatus {
        // TODO: Implement with CLLocationManager
        return .notDetermined
    }

    private func requestCameraPermission() async -> PermissionStatus {
        // TODO: Implement with AVCaptureDevice.requestAccess(for: .video)
        return .notDetermined
    }

    private func requestMicrophonePermission() async -> PermissionStatus {
        // TODO: Implement with AVCaptureDevice.requestAccess(for: .audio)
        return .notDetermined
    }

    private func requestFaceIDPermission() async -> PermissionStatus {
        // TODO: Implement with LAContext().canEvaluatePolicy
        return .notDetermined
    }

    private func requestSiriPermission() async -> PermissionStatus {
        // TODO: Implement with INPreferences.requestSiriAuthorization
        return .notDetermined
    }
}

// MARK: - Welcome Message

/// The welcome message displayed on first boot.
struct WelcomeMessage: Sendable {
    let greeting: String
    let title: String
    let subtitle: String
    let body: String
    let ctaTitle: String
}
