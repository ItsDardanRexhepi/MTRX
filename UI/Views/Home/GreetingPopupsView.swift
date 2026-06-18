// GreetingPopupsView.swift
// MTRX -- Tappable greeting extras: an interactive liquid-glass calendar
// popup (tap the date) and a live local-weather popup (tap the greeting).
// Also hosts the shared loop-arrow glyph used by the Account workspace.
// Copyright 2026 OPN MATRX. All rights reserved.

import SwiftUI
import CoreLocation
#if canImport(WeatherKit)
import WeatherKit
#endif

// MARK: - Loop-arrow glyph (shared — used by the Account "Messaging" tile)

/// An infinity loop that resolves into an arrowhead — MTRX's messaging mark.
struct InfinityShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX, cy = rect.midY
        let lw = rect.width * 0.40
        let lh = rect.height * 0.34
        // Left loop.
        p.move(to: CGPoint(x: cx, y: cy))
        p.addCurve(to: CGPoint(x: cx, y: cy),
                   control1: CGPoint(x: cx - lw, y: cy - lh * 1.8),
                   control2: CGPoint(x: cx - lw, y: cy + lh * 1.8))
        // Right loop.
        p.move(to: CGPoint(x: cx, y: cy))
        p.addCurve(to: CGPoint(x: cx, y: cy),
                   control1: CGPoint(x: cx + lw, y: cy - lh * 1.8),
                   control2: CGPoint(x: cx + lw, y: cy + lh * 1.8))
        return p
    }
}

struct LoopArrowGlyph: View {
    var color: Color = .white
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                InfinityShape()
                    .stroke(color, style: StrokeStyle(lineWidth: max(2.4, w * 0.12),
                                                      lineCap: .round, lineJoin: .round))
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: w * 0.30, weight: .black))
                    .foregroundStyle(color)
                    .rotationEffect(.degrees(45))
                    .position(x: w * 0.82, y: h * 0.30)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Calendar popup

struct CalendarPopup: View {
    @Binding var date: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                Text("Calendar")
                    .font(.mtrxHeadline)
                    .foregroundStyle(Color.labelPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .accessibilityLabel("Close")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.labelSecondary)
                }
                .buttonStyle(.plain)
            }

            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(Color.trinityPrimary)

            Button {
                date = Date()
            } label: {
                Text("Today")
                    .font(.mtrxCalloutBold)
                    .foregroundStyle(Color.trinityPrimary)
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity)
        .mtrxLiquidGlass(cornerRadius: 30)
        .padding(Spacing.md)
    }
}

// MARK: - Weather popup (live, local)

@MainActor
final class WeatherLoader: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Phase {
        case loading
        case error(String)
        case loaded(place: String, temp: Int, unit: String, desc: String, icon: String, wind: Int, windUnit: String)
    }

    @Published var phase: Phase = .loading
    private let manager = CLLocationManager()
    private var requested = false

    func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            phase = .error("Turn on Location in Settings to see your local weather.")
        default:
            requestOnce()
        }
    }

    private func requestOnce() {
        guard !requested else { return }
        requested = true
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: self.requestOnce()
            case .denied, .restricted: self.phase = .error("Turn on Location in Settings to see your local weather.")
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in await self.fetch(loc) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.phase = .error("Couldn't find your location right now.") }
    }

    // Real current conditions from Apple WeatherKit. Same `.loaded` interface as
    // before; honest error states when WeatherKit is unavailable (capability not
    // enabled) or a fetch fails — never fabricated weather.
    private func fetch(_ loc: CLLocation) async {
        let us = Locale.current.measurementSystem == .us
        var place = "Your area"
        if let pm = try? await CLGeocoder().reverseGeocodeLocation(loc).first {
            place = pm.locality ?? pm.administrativeArea ?? place
        }
        #if canImport(WeatherKit)
        guard #available(iOS 16.0, *) else {
            phase = .error("Weather needs iOS 16 or later on this device.")
            return
        }
        do {
            let weather = try await WeatherService.shared.weather(for: loc)
            let current = weather.currentWeather
            // Apple REQUIRES attribution wherever this data is shown.
            await WeatherKitAttribution.shared.recordProvided()
            let (desc, icon) = Self.describe(current.condition)
            let temp = current.temperature.converted(to: us ? .fahrenheit : .celsius).value
            let wind = current.wind.speed.converted(to: us ? .milesPerHour : .kilometersPerHour).value
            phase = .loaded(place: place,
                            temp: Int(temp.rounded()),
                            unit: us ? "°F" : "°C",
                            desc: desc, icon: icon,
                            wind: Int(wind.rounded()),
                            windUnit: us ? "mph" : "km/h")
        } catch {
            phase = .error("Couldn't load weather right now. The app's WeatherKit capability may not be enabled yet.")
        }
        #else
        phase = .error("Weather isn't available on this build.")
        #endif
    }

    #if canImport(WeatherKit)
    @available(iOS 16.0, *)
    static func describe(_ condition: WeatherCondition) -> (String, String) {
        switch condition {
        case .clear, .mostlyClear, .hot:
            return (condition.description, "sun.max.fill")
        case .partlyCloudy:
            return (condition.description, "cloud.sun.fill")
        case .cloudy, .mostlyCloudy:
            return (condition.description, "cloud.fill")
        case .foggy, .haze, .smoky:
            return (condition.description, "cloud.fog.fill")
        case .drizzle:
            return (condition.description, "cloud.drizzle.fill")
        case .rain, .heavyRain, .sunShowers:
            return (condition.description, "cloud.rain.fill")
        case .snow, .heavySnow, .flurries, .sunFlurries, .wintryMix, .freezingDrizzle, .freezingRain:
            return (condition.description, "cloud.snow.fill")
        case .sleet, .hail, .blizzard, .blowingSnow:
            return (condition.description, "cloud.sleet.fill")
        case .thunderstorms, .strongStorms, .isolatedThunderstorms, .scatteredThunderstorms, .tropicalStorm, .hurricane:
            return (condition.description, "cloud.bolt.rain.fill")
        case .windy, .breezy, .blowingDust:
            return (condition.description, "wind")
        case .frigid:
            return (condition.description, "thermometer.snowflake")
        @unknown default:
            return (condition.description, "cloud.fill")
        }
    }
    #endif
}

struct WeatherPopup: View {
    @StateObject private var loader = WeatherLoader()
    @State private var attribution = WeatherKitAttribution.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Spacing.sm) {
            content
            if case .loaded = loader.phase { weatherAttribution }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
        .overlay(alignment: .topLeading) {
            Text("Local Weather")
                .font(.mtrxHeadline)
                .foregroundStyle(Color.labelPrimary)
                .padding(Spacing.lg)
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .accessibilityLabel("Close")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.labelSecondary)
            }
            .buttonStyle(.plain)
            .padding(Spacing.lg)
        }
        .mtrxLiquidGlass(cornerRadius: 30)
        .padding(Spacing.md)
        .onAppear { loader.start() }
    }

    @ViewBuilder private var content: some View {
        switch loader.phase {
        case .loading:
            ProgressView()
                .tint(Color.trinityPrimary)
            Text("Finding your local weather…")
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)
        case .error(let message):
            Image(systemName: "location.slash.fill")
                .font(.system(size: 34))
                .foregroundStyle(Color.labelTertiary)
            Text(message)
                .font(.mtrxSubheadline)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        case let .loaded(place, temp, unit, desc, icon, wind, windUnit):
            Image(systemName: icon)
                .font(.system(size: 56))
                .symbolRenderingMode(.multicolor)
            Text("\(temp)\(unit)")
                .font(.system(size: 46, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.labelPrimary)
            Text(desc)
                .font(.mtrxHeadline)
                .foregroundStyle(Color.labelPrimary)
            Label(place, systemImage: "location.fill")
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)
            Text("Wind \(wind) \(windUnit)")
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelTertiary)
        }
    }

    // Apple Weather attribution — required wherever WeatherKit data is shown.
    private var weatherAttribution: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "applelogo").font(.system(size: 9, weight: .semibold))
                Text("Weather").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.labelTertiary)
            if let url = attribution.legalPageURL {
                Link("Other data sources", destination: url)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.labelTertiary)
            }
        }
        .padding(.top, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Weather data provided by Apple Weather")
    }
}
