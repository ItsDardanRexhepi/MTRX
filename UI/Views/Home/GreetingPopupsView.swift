// GreetingPopupsView.swift
// MTRX -- Tappable greeting extras: an interactive liquid-glass calendar
// popup (tap the date) and a live local-weather popup (tap the greeting).
// Also hosts the shared loop-arrow glyph used by the Account workspace.
// Copyright 2026 OPN MATRX. All rights reserved.

import SwiftUI
import CoreLocation

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

    private func fetch(_ loc: CLLocation) async {
        let us = Locale.current.measurementSystem == .us
        let tUnit = us ? "fahrenheit" : "celsius"
        let wUnit = us ? "mph" : "kmh"
        var place = "Your area"
        if let pm = try? await CLGeocoder().reverseGeocodeLocation(loc).first {
            place = pm.locality ?? pm.administrativeArea ?? place
        }
        let lat = loc.coordinate.latitude, lon = loc.coordinate.longitude
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code,wind_speed_10m&temperature_unit=\(tUnit)&wind_speed_unit=\(wUnit)") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let r = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            let (desc, icon) = Self.describe(r.current.weather_code)
            phase = .loaded(place: place,
                            temp: Int(r.current.temperature_2m.rounded()),
                            unit: us ? "°F" : "°C",
                            desc: desc, icon: icon,
                            wind: Int(r.current.wind_speed_10m.rounded()),
                            windUnit: us ? "mph" : "km/h")
        } catch {
            phase = .error("Couldn't load weather right now.")
        }
    }

    static func describe(_ code: Int) -> (String, String) {
        switch code {
        case 0:            return ("Clear", "sun.max.fill")
        case 1, 2:         return ("Partly cloudy", "cloud.sun.fill")
        case 3:            return ("Cloudy", "cloud.fill")
        case 45, 48:       return ("Fog", "cloud.fog.fill")
        case 51, 53, 55, 56, 57: return ("Drizzle", "cloud.drizzle.fill")
        case 61, 63, 65, 66, 67: return ("Rain", "cloud.rain.fill")
        case 71, 73, 75, 77: return ("Snow", "cloud.snow.fill")
        case 80, 81, 82:   return ("Showers", "cloud.heavyrain.fill")
        case 85, 86:       return ("Snow showers", "cloud.snow.fill")
        case 95, 96, 99:   return ("Thunderstorm", "cloud.bolt.rain.fill")
        default:           return ("—", "cloud.fill")
        }
    }
}

private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
        let wind_speed_10m: Double
    }
    let current: Current
}

struct WeatherPopup: View {
    @StateObject private var loader = WeatherLoader()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Spacing.sm) {
            content
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
}
