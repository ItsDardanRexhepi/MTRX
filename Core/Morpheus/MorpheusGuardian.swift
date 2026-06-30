// MorpheusGuardian.swift
// MTRX — Morpheus pre-transaction guardian: risk-REVIEW logic (M-GUARDIAN, piece 1)
//
// Reads the deterministic facts exposed by MorpheusSecurityState (§3c) and turns them
// into ADVISORY observations the user will later see BEFORE a risky money action reaches
// the hard gate. Per MORPHEUS_ADVISOR_SPEC.md:
//
//   • ADVISORY ONLY. review(...) returns [Observation] — things to SHOW the human. It
//     returns NO boolean, NO allow/deny, NO "shouldProceed". Nothing here is consumed by
//     a signing or money-moving decision. The deterministic walls (testnet chain lock,
//     biometric Secure-Enclave gate, gated-key refusal, fail-closed send) enforce
//     regardless of what — or whether — this produces. If Morpheus is wrong, silent, or
//     injected, the walls are unaffected.
//   • EVERY observation maps to a spec §5 in-scope (grounded) row. Nothing from the
//     deferred or forbidden lists is emitted: no "you've never sent here" (no send
//     history exists), no "unsafe/unaudited contract" (only record presence/absence), no
//     statistical anomaly, no address reputation.
//   • This is piece 1: the review LOGIC only. No UI, no surfacing — that is piece 2.

import Foundation

enum MorpheusGuardian {

    /// The kind of money action being composed (grounds "contract interaction /
    /// irreversible" and decides which observations apply).
    enum ActionKind: Equatable {
        case nativeSend, tokenSend          // value transfers to an address
        case swap, stake                    // DeFi value moves
        case contractCall, deployContract, nft

        /// Whether this action interacts with a smart contract (vs a plain transfer).
        var isContractInteraction: Bool {
            switch self {
            case .nativeSend, .tokenSend: return false
            case .swap, .stake, .contractCall, .deployContract, .nft: return true
            }
        }
    }

    /// What MTRX knows about the target contract's verification — strictly record
    /// presence/absence. NEVER asserts a contract is audited or safe.
    enum ContractRecordState: Equatable { case verified, noRecord, notApplicable }

    /// Advisory severity of an observation. Presentation metadata ONLY — it gates
    /// nothing; a `.high` observation blocks no action.
    enum Severity: Equatable { case info, caution, high }

    /// One thing Morpheus would SHOW the user. Advisory data; never a decision.
    struct Observation: Equatable {
        enum Kind: Equatable {
            case onTestnet, requiresFaceID
            case recipientNotInContacts
            case aboveExtraConfirmThreshold, triggersCoolingOff, aboveDailySoftLimit
            case contractInteraction, noContractVerificationRecord
        }
        let kind: Kind
        let severity: Severity
        /// Honest, grounded text shown to the user.
        let message: String
        /// What Morpheus recommends the human consider (advisory; nil if none).
        let recommendation: String?
        /// The spec §5 in-scope row this observation is grounded in.
        let grounding: String
    }

    /// The observed deterministic facts for one action. The caller fills this from
    /// MorpheusSecurityState (§3c) + the action being composed. Kept as a pure value so
    /// review() is deterministic and trivially testable — and so it is structurally
    /// impossible for review() to reach into, or change, any wall.
    struct Context: Equatable {
        var actionKind: ActionKind
        var onTestnet: Bool
        /// nil when the action has no single recipient (e.g. a deploy).
        var recipientInContacts: Bool?
        /// nil when the USD amount is unknown (no price). The threshold observations
        /// carry the spec §5 "at the current price" caveat because of this dependency.
        var thresholds: MorpheusSecurityState.ThresholdCrossings?
        var requiresFaceID: Bool
        /// Which biometric the device uses ("Face ID" / "Touch ID" / "biometrics"), so
        /// the requires-biometric observation names the right one (never assume Face ID).
        var biometryLabel: String = "biometrics"
        var contractRecord: ContractRecordState
    }

    /// Pure risk review: deterministic facts → advisory observations. Returns ADVISORY
    /// DATA ONLY — never a value that gates the action. (See the file header.)
    static func review(_ ctx: Context) -> [Observation] {
        var out: [Observation] = []

        if ctx.onTestnet {
            out.append(Observation(
                kind: .onTestnet, severity: .info,
                message: "You're on testnet, so this won't move real funds.",
                recommendation: nil,
                grounding: "§5 You're on testnet"))
        }

        if ctx.requiresFaceID {
            out.append(Observation(
                kind: .requiresFaceID, severity: .info,
                message: "This will require \(ctx.biometryLabel) to sign.",
                recommendation: nil,
                grounding: "§5 This send will require Face ID"))
        }

        if ctx.recipientInContacts == false {
            out.append(Observation(
                kind: .recipientNotInContacts, severity: .caution,
                message: "This address isn't in your contacts.",
                recommendation: "Double-check the address before you send.",
                grounding: "§5 This address isn't in your contacts"))
        }

        if let t = ctx.thresholds {
            if t.crossesExtraConfirm {
                out.append(Observation(
                    kind: .aboveExtraConfirmThreshold, severity: .caution,
                    message: "At the current price, this looks above your extra-confirmation threshold.",
                    recommendation: "Take a second to confirm the amount.",
                    grounding: "§5 above your $X confirmation threshold"))
            }
            if t.crossesCoolingOff {
                // Ground ONLY the fact we can prove — the user's own cooling-off
                // threshold is crossed. Do NOT promise a delay or a cancel window:
                // no send-path code consumes coolingOffDelay() yet, so neither exists.
                out.append(Observation(
                    kind: .triggersCoolingOff, severity: .caution,
                    message: "At the current price, this is above the amount you set for your cooling-off rule.",
                    recommendation: "You can review that limit in Security settings.",
                    grounding: "§5 your cooling-off threshold"))
            }
            if t.crossesDailySoft {
                out.append(Observation(
                    kind: .aboveDailySoftLimit, severity: .caution,
                    message: "At the current price, this looks above your daily soft limit.",
                    recommendation: nil,
                    grounding: "§5 your daily soft limit"))
            }
        }

        if ctx.actionKind.isContractInteraction {
            out.append(Observation(
                kind: .contractInteraction, severity: .info,
                message: "This interacts with a smart contract and may be irreversible.",
                recommendation: nil,
                grounding: "§5 contract interaction / irreversible"))
            if ctx.contractRecord == .noRecord {
                out.append(Observation(
                    kind: .noContractVerificationRecord, severity: .caution,
                    message: "We don't have a verification record for this contract.",
                    recommendation: "We can't confirm what it does, so review it before you approve.",
                    grounding: "§5 no verification record for this contract"))
            }
        }

        return out
    }

    /// Convenience that gathers the §3c facts for a SEND from MorpheusSecurityState and
    /// runs the pure review. Still returns advisory data only; calls no enforcement path.
    @MainActor
    static func reviewSend(recipient: String,
                           amountUSD: Double?,
                           todayOutgoingUSD: Double,
                           kind: ActionKind = .nativeSend,
                           contractRecord: ContractRecordState = .notApplicable) -> [Observation] {
        let ctx = Context(
            actionKind: kind,
            onTestnet: MorpheusSecurityState.posture().onTestnet,
            recipientInContacts: MorpheusSecurityState.isRecipientInContacts(recipient),
            thresholds: amountUSD.map {
                MorpheusSecurityState.thresholdCrossings(amountUSD: $0, todayOutgoingUSD: todayOutgoingUSD)
            },
            requiresFaceID: MorpheusSecurityState.nativeSendRequiresFaceID(),
            biometryLabel: MorpheusSecurityState.biometryLabel(),
            contractRecord: contractRecord
        )
        return review(ctx)
    }
}
