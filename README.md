# MTRX iOS

Consumer iOS app for the [0pnMatrx](https://github.com/ItsDardanRexhepi/0pnMatrx) platform. This is the app end-users download from the App Store; 0pnMatrx is the separate backend platform developers build on.

Five tabs (Discover, Build, Home, Social, Account). Three agents (Neo, Trinity, Morpheus). SwiftUI throughout.

## Requirements

- Xcode 15+
- iOS 17.0 deployment target
- Apple Developer account for distribution

## Run It

```bash
git clone https://github.com/ItsDardanRexhepi/MTRX.git
cd MTRX
open MTRX.xcodeproj
```

Pick a simulator, Cmd+R. App boots into demo mode — every screen works without a backend.

On first build a Run Script phase auto-generates `Config/Secrets.swift` from
`Config/Secrets.example.swift` (placeholder values) if it's missing — `Secrets.swift`
is gitignored and never committed, so a fresh clone builds with no manual step.

## Point At A Backend

Backend configuration lives in `Config/PendingCredentials.swift`. Set the gateway
URL there:

```swift
enum Backend { static let gatewayURL = "https://your-gateway.example.com" }
```

The default is **empty**, so the app runs in demo mode until you point it at a
running gateway. There is no hosted endpoint today — see the
[0pnMatrx repo](https://github.com/ItsDardanRexhepi/0pnMatrx) for how to self-host one.

## Layout

```
Apple/          iOS-framework integrations
Blockchain/     30 component modules
Config/         Info.plist, entitlements, production config
Core/           Trinity, agent access, networking, packager
UI/             design system + views
Assets.xcassets App icon + asset catalog
Tests/          unit + integration tests
```

## License

MIT.
