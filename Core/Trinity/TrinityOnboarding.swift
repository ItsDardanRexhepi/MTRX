//
//  TrinityOnboarding.swift
//  MTRX — Trinity
//
//  First boot message, permission requests, and onboarding flow management.
//

import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(HealthKit)
import HealthKit
#endif
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif
#if canImport(Intents)
import Intents
#endif

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
        // Persist so onboarding can resume correctly after a relaunch.
        defaults.set(status.rawValue, forKey: "trinity.permission.\(permission.rawValue)")
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

        // Foundation Models step — explain on-device intelligence
        if #available(iOS 26, *) {
            steps.append(OnboardingStep(
                order: order,
                title: "On-Device Intelligence",
                description: "Trinity can process your requests directly on this device using Apple Intelligence. Your conversations stay private — nothing leaves your phone unless you choose to connect to the full platform. You can enable Privacy Mode at any time in Settings.",
                type: .tutorial,
                isRequired: false
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

    // MARK: - Permission Request Implementations

    // Each helper wraps the iOS system call in a safe async shim and
    // maps the SDK-specific status type into our neutral
    // ``PermissionStatus`` so callers never need to import the system
    // frameworks. The ``#if canImport`` guards keep this file
    // compilable on macOS (for unit tests) where some frameworks
    // aren't available.

    private func requestNotificationPermission() async -> PermissionStatus {
        #if canImport(UserNotifications)
        do {
            let granted = try await UNUserNotificationCenter
                .current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            return granted ? .granted : .denied
        } catch {
            return .denied
        }
        #else
        return .notDetermined
        #endif
    }

    private func requestHealthKitPermission() async -> PermissionStatus {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return .restricted }
        let store = HKHealthStore()
        // Ask only for the read types Trinity context providers use.
        // Writing health data is not part of the MTRX capability set.
        let readTypes: Set<HKObjectType> = {
            var types: Set<HKObjectType> = []
            if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
                types.insert(hrv)
            }
            if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) {
                types.insert(steps)
            }
            if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
                types.insert(sleep)
            }
            return types
        }()
        return await withCheckedContinuation { (continuation: CheckedContinuation<PermissionStatus, Never>) in
            store.requestAuthorization(toShare: nil, read: readTypes) { success, _ in
                continuation.resume(returning: success ? .granted : .denied)
            }
        }
        #else
        return .notDetermined
        #endif
    }

    private func requestLocationPermission() async -> PermissionStatus {
        #if canImport(CoreLocation)
        let delegate = _LocationDelegate()
        let manager = CLLocationManager()
        manager.delegate = delegate
        manager.requestWhenInUseAuthorization()
        let status = await delegate.waitForResolution()
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
        #else
        return .notDetermined
        #endif
    }

    private func requestCameraPermission() async -> PermissionStatus {
        #if canImport(AVFoundation)
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .granted : .denied
        #else
        return .notDetermined
        #endif
    }

    private func requestMicrophonePermission() async -> PermissionStatus {
        #if canImport(AVFoundation)
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return granted ? .granted : .denied
        #else
        return .notDetermined
        #endif
    }

    private func requestFaceIDPermission() async -> PermissionStatus {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        var error: NSError?
        // ``canEvaluatePolicy`` doesn't trigger the prompt — it just
        // reports whether the device is capable. The real biometric
        // prompt happens on the first ``evaluatePolicy`` call during a
        // signing operation; onboarding's job is only to confirm the
        // capability is present on this device.
        let supported = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )
        if supported { return .granted }
        if let code = error?.code, code == LAError.biometryNotEnrolled.rawValue {
            return .denied
        }
        return .restricted
        #else
        return .notDetermined
        #endif
    }

    private func requestSiriPermission() async -> PermissionStatus {
        #if canImport(Intents)
        return await withCheckedContinuation { (continuation: CheckedContinuation<PermissionStatus, Never>) in
            INPreferences.requestSiriAuthorization { status in
                switch status {
                case .authorized: continuation.resume(returning: .granted)
                case .denied: continuation.resume(returning: .denied)
                case .restricted: continuation.resume(returning: .restricted)
                case .notDetermined: continuation.resume(returning: .notDetermined)
                @unknown default: continuation.resume(returning: .notDetermined)
                }
            }
        }
        #else
        return .notDetermined
        #endif
    }
}

// MARK: - Location Permission Delegate

#if canImport(CoreLocation)
/// Tiny one-shot delegate that bridges ``CLLocationManager``'s
/// callback-based authorization flow to ``async/await``.
///
/// Created, used once, then dropped — there's no reason to hold it on
/// the onboarding object because the user can only answer the iOS
/// alert a single time per permission.
private final class _LocationDelegate: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    func waitForResolution() async -> CLAuthorizationStatus {
        await withCheckedContinuation { cont in
            self.continuation = cont
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        continuation?.resume(returning: status)
        continuation = nil
    }
}
#endif

// MARK: - Welcome Message

/// The welcome message displayed on first boot.
struct WelcomeMessage: Sendable {
    let greeting: String
    let title: String
    let subtitle: String
    let body: String
    let ctaTitle: String
}
