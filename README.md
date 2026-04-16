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

## Point At A Backend

In `Config/ProductionConfig.swift`:

```swift
static let productionGatewayURL: String? = "https://your-gateway.example.com"
```

Default is `https://openmatrix-ai.com`. See the [0pnMatrx repo](https://github.com/ItsDardanRexhepi/0pnMatrx) for how to deploy one.

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
