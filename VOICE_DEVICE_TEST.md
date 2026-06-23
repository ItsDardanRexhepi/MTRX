# Voice features — DEVICE-TEST sign-off gate (standing)

The voice track (Trinity STT/TTS) carries its **own device-sign-off requirement**, the same
standing-gate pattern as the Phase-3 key biometric gate (§14.8c in `Matrix-Security-System/
SECURITY_REVIEW_CHECKLIST.md`). **A green Simulator build is necessary but NOT sufficient** —
mic capture, audio output, and the real iOS permission prompts only fully exercise on a **real
device** (the Simulator routes the Mac mic/speakers and does not reproduce the iOS permission flow
or Secure-Enclave/AVAudioSession behavior precisely).

## Must verify on a real device before voice ships to users
- [ ] **V3 STT:** the mic permission prompt appears; speech streams into the input as you talk; the
      final result lands clean; **denial shows the honest message** ("Settings → Privacy → Speech
      Recognition"); stop works; nothing is captured when not listening.
- [ ] **V4 TTS:** Trinity's reply is spoken in the reply's language with a real voice; stop/mute
      works; a language with no on-device voice degrades **honestly** (basic-voice / no-voice note),
      not silently.
- [ ] **V5 turn-taking:** the `.record` (STT) ↔ `.playback` (TTS) audio-session handoff is clean
      across turns; barge-in (tap mic while Trinity speaks) stops TTS; no stuck/duplicated session.
- [ ] **Tier-2 (when wired, V3.5/V4):** with Enterprise + the privacy toggle ON, extended-language
      voice works; with either OFF, the honest offer message shows — confirmed on device.

This gate is independent of the Phase-3 security gate but logged for the same reason: so the
feature can't be called "done" off a Simulator build alone. Flags OFF · OBSERVE · testnet.
