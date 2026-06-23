# PENDING privacy/legal item — Tier-2 extended-language (third-party data) disclosure

**Status: NOT YET ACTIVE. Internal tracking only — do NOT add to the live policy until the
feature ships.** Tied to the existing legal work in `Resources/Legal/Privacy.md` and
`Resources/Legal/Terms.md`.

## What this is
The Trinity multilingual feature has two tiers:
- **Tier 1 (default, all users, free):** 100% on-device — `NLLanguageRecognizer` detection,
  `SFSpeechRecognizer` STT, `AVSpeechSynthesizer` TTS, on-device/gateway LLM. **No user voice or
  text leaves the device for the on-device path.** (V0/V1.)
- **Tier 2 (Enterprise + explicit opt-in, V2+):** extended-language coverage via a **third-party
  cloud service** (Whisper-class STT / multilingual neural TTS). This path **sends the user's
  voice and/or text off-device to a third party.**

## The disclosure that must exist BEFORE Tier 2 ships real value
When V2 (the paywall + privacy toggle) and V3/V4 (the actual API voice wiring) are built:

- [ ] **Privacy policy (`Resources/Legal/Privacy.md`)** updated with explicit language: when the
      user enables Extended Language Support, their voice/text is transmitted to a named
      third-party processor for transcription/synthesis/translation; what is sent, retention, and
      the processor's identity.
- [ ] **The in-settings toggle disclosure text** (the toggle itself, `PrivacyView.swift`, default
      OFF) states the same in plain language at the point of consent — the user must actively
      acknowledge that enabling this sends their data to a third party.
- [ ] **Terms (`Resources/Legal/Terms.md`)** reflect the Enterprise-tier feature + third-party
      processing.
- [ ] **Legal review** of the third-party processor's DPA / sub-processor terms before go-live.
- [ ] Gate is **both-conditions**: active Enterprise entitlement (`FeatureGate` → `.enterprise`,
      product `com.opnmatrx.mtrx.enterprise.monthly`) **AND** the toggle ON. Neither alone enables it.

## Why it's logged here and not in the live policy now
The on-device default (Tier 1) sends nothing to third parties, so the current policy is accurate.
Stating "we share your voice with a third party" before the feature exists/can-be-enabled would be
a false disclosure. This item ensures the real language is written + legally reviewed at V2, not
forgotten.
