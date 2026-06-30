// MorpheusNarrator.swift
// MTRX — Morpheus whole-app security narrator: narration LOGIC (M-NARRATOR, piece 1)
//
// Turns the read-only deterministic posture (MorpheusSecurityState §3a/§3b) into plain,
// honest statements about what is protecting the user. Per MORPHEUS_ADVISOR_SPEC.md:
//
//   • NARRATION ONLY. narrate(...) returns [Statement] — display data. It owns no
//     send/sign logic, gates nothing, and changes no wall. If all of Core/Morpheus were
//     deleted, security is byte-for-byte identical.
//   • GROUNDED IN TRUE STATE. Every statement maps to a real value the façade actually
//     read (§3a/§3b). It never claims "secure"/"fully protected" as a blanket — only
//     specific, provable facts. Honest in the nil/empty cases: an identity-only cloud
//     restore (a wallet record with NO local signing key, ownerKeyBiometricGated == nil)
//     is narrated as "recovery needed", NEVER as "an ungated key".
//   • This is piece 1: the narration LOGIC only. No UI, no surfacing — that is piece 2.

import Foundation

enum MorpheusNarrator {

    /// One plain-language statement about the user's security posture. Display data only.
    struct Statement: Equatable {
        /// Presentation metadata only — it gates nothing.
        enum Tone: Equatable {
            case protective   // something is actively protecting the user
            case neutral      // a true fact, neither good nor bad
            case attention    // something the user may want to address
        }
        let title: String
        let detail: String
        let tone: Tone
        /// The §3a/§3b read this statement is grounded in.
        let grounding: String
    }

    /// Pure narration: deterministic posture/wallet snapshots → grounded statements.
    /// Returns DISPLAY DATA only — never a value any wall consumes.
    static func narrate(posture: MorpheusSecurityState.PostureSnapshot,
                        wallet: MorpheusSecurityState.WalletSecuritySnapshot) -> [Statement] {
        var out: [Statement] = []

        // MARK: Network / chain lock (§3a). onTestnet is EXACTLY the signing-lock predicate
        // (configured chain == the only permitted signing chain). So onTestnet == false does
        // NOT mean "funds move" — it means the wall fails CLOSED on the configured chain and
        // every send is refused before signing.
        if posture.onTestnet {
            out.append(Statement(
                title: "On testnet",
                detail: "You're on the test network (the only chain this build signs on), so nothing here moves real funds.",
                tone: .protective,
                grounding: "§3a onTestnet == true (configured chain is the permitted signing chain)"))
        } else {
            out.append(Statement(
                title: "Signing locked to testnet",
                detail: "This build only signs on the test network (Base Sepolia). On the configured chain, every send is refused before signing — nothing moves.",
                tone: .protective,
                grounding: "§3a onTestnet == false (configured chain isn't the permitted signing chain → signOperation fails closed)"))
        }

        // MARK: Owner key / signing protection (§3b) — exhaustive, identity-only handled honestly
        if !wallet.hasActiveWallet {
            out.append(Statement(
                title: "No wallet yet",
                detail: "You haven't set up a wallet on this device yet.",
                tone: .neutral,
                grounding: "§3b hasActiveWallet == false"))
        } else if !wallet.hasLocalSigningKey {
            // Identity-only cloud restore: the address is known but there's no local
            // signing key. This is NOT an ungated key — it's a recovery state.
            out.append(Statement(
                title: "Recovery needed",
                detail: "This device has your wallet's identity but not its signing key yet. Finish recovery to sign here.",
                tone: .attention,
                grounding: "§3b hasActiveWallet == true && hasLocalSigningKey == false"))
        } else if wallet.ownerKeyBiometricGated == true {
            out.append(Statement(
                title: "Signing key protected",
                detail: "Your signing key is \(wallet.biometryLabel)-protected — moving funds needs your \(wallet.biometryLabel).",
                tone: .protective,
                grounding: "§3b ownerKeyBiometricGated == true"))
        } else if wallet.ownerKeyBiometricGated == false {
            out.append(Statement(
                title: "Key not biometric-gated",
                detail: "Your signing key isn't biometric-gated. You can reset to a protected key in Security settings.",
                tone: .attention,
                grounding: "§3b ownerKeyBiometricGated == false"))
        } else {
            // Indeterminate: a local key exists but its gated state couldn't be read. Match
            // the grounding to the condition — do NOT assert it's ungated; recommend a check.
            out.append(Statement(
                title: "Signing key needs a check",
                detail: "We couldn't confirm your signing key's protection. Open Security settings to review or reset it.",
                tone: .attention,
                grounding: "§3b ownerKeyBiometricGated == nil with a local key (indeterminate)"))
        }

        guard wallet.hasActiveWallet else {
            // Without a wallet, the remaining wallet-scoped statements don't apply.
            if !posture.backendConfigured { out.append(Self.backendOffline) }
            return out
        }

        // MARK: Biometric availability (§3b)
        if !wallet.biometricsAvailable {
            out.append(Statement(
                title: "Biometrics off",
                detail: "Face ID / Touch ID isn't set up on this device.",
                tone: .neutral,
                grounding: "§3b biometricsAvailable == false"))
        }

        // MARK: Recovery guardians (§3b)
        if wallet.guardianCount == 0 {
            out.append(Statement(
                title: "No recovery guardians",
                detail: "You haven't added any recovery guardians yet.",
                tone: .attention,
                grounding: "§3b guardianCount == 0"))
        } else {
            let n = wallet.guardianCount
            out.append(Statement(
                title: "\(n) recovery guardian\(n == 1 ? "" : "s")",
                detail: "You have \(n) recovery guardian\(n == 1 ? "" : "s") set up.",
                tone: .protective,
                grounding: "§3b guardianCount > 0"))
        }

        // MARK: Cloud recovery backup (§3b)
        if wallet.hasCloudBackup {
            out.append(Statement(
                title: "Recovery backup saved",
                detail: "A recovery backup is stored in your iCloud Keychain.",
                tone: .protective,
                grounding: "§3b hasCloudBackup == true"))
        } else {
            out.append(Statement(
                title: "No recovery backup",
                detail: "You don't have a recovery backup saved yet.",
                tone: .neutral,
                grounding: "§3b hasCloudBackup == false"))
        }

        // MARK: Backend security service (§3a)
        if !posture.backendConfigured { out.append(Self.backendOffline) }

        return out
    }

    private static let backendOffline = Statement(
        title: "Security service offline",
        detail: "The backend security service isn't connected on this build.",
        tone: .neutral,
        grounding: "§3a backendConfigured == false")

    /// Convenience: read the live façade and narrate. Still display data only.
    @MainActor
    static func narrate() -> [Statement] {
        narrate(posture: MorpheusSecurityState.posture(), wallet: MorpheusSecurityState.wallet())
    }
}
