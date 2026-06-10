// TrinityTools.swift
// MTRX — Trinity
//
// Tools the on-device model can call during a conversation
// (Foundation Models tool calling, iOS 26+):
//
//   getWeather — current conditions via Open-Meteo (no API key), using
//                the device location when permitted or a named city.
//   searchWeb  — live factual lookups via Wikipedia + DuckDuckGo
//                instant answers (no API key).
//
// Both tools are network-backed, HTTPS-only, and fail soft: on any
// error they return a plain explanation the model can relay naturally.

import CoreLocation
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)

// MARK: - Weather Tool

@available(iOS 26.0, macOS 26.0, *)
struct TrinityWeatherTool: Tool {
    let name = "getWeather"
    let description = """
    Get current weather. Call when the user asks about weather, \
    temperature, rain, or conditions. Pass a city name if the user \
    named one; omit it to use the user's current location.
    """

    @Generable
    struct Arguments {
        @Guide(description: "City name, e.g. 'New York'. Omit for the user's current location.")
        var city: String?
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            let place: (lat: Double, lon: Double, label: String)
            if let city = arguments.city, !city.isEmpty {
                guard let geocoded = try await Self.geocode(city: city) else {
                    return "Couldn't find a city called \(city)."
                }
                place = geocoded
            } else if let located = await TrinityLocationProvider.shared.coordinates() {
                place = (located.latitude, located.longitude, "your location")
            } else {
                return "Location unavailable (no permission). Ask the user which city they want weather for."
            }

            let weather = try await Self.fetchWeather(lat: place.lat, lon: place.lon)
            return "Weather for \(place.label): \(weather)"
        } catch {
            return "Weather lookup failed: \(error.localizedDescription)"
        }
    }

    // MARK: Open-Meteo

    private static func geocode(city: String) async throws -> (lat: Double, lon: Double, label: String)? {
        var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        struct Geo: Decodable {
            struct Hit: Decodable { let latitude: Double; let longitude: Double; let name: String; let country: String? }
            let results: [Hit]?
        }
        guard let hit = try JSONDecoder().decode(Geo.self, from: data).results?.first else { return nil }
        let label = hit.country.map { "\(hit.name), \($0)" } ?? hit.name
        return (hit.latitude, hit.longitude, label)
    }

    private static func fetchWeather(lat: Double, lon: Double) async throws -> String {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,wind_speed_10m"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "wind_speed_unit", value: "mph"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        struct Forecast: Decodable {
            struct Current: Decodable {
                let temperature_2m: Double
                let apparent_temperature: Double
                let weather_code: Int
                let wind_speed_10m: Double
            }
            struct Daily: Decodable {
                let temperature_2m_max: [Double]
                let temperature_2m_min: [Double]
            }
            let current: Current
            let daily: Daily
        }
        let f = try JSONDecoder().decode(Forecast.self, from: data)
        let condition = Self.describe(code: f.current.weather_code)
        let high = f.daily.temperature_2m_max.first ?? f.current.temperature_2m
        let low = f.daily.temperature_2m_min.first ?? f.current.temperature_2m
        return String(
            format: "%@, %.0f°F (feels like %.0f°F), wind %.0f mph, today's high %.0f°F / low %.0f°F.",
            condition, f.current.temperature_2m, f.current.apparent_temperature,
            f.current.wind_speed_10m, high, low
        )
    }

    /// WMO weather code → plain English.
    private static func describe(code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1, 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Foggy"
        case 51...57: return "Drizzle"
        case 61...67: return "Rain"
        case 71...77: return "Snow"
        case 80...82: return "Rain showers"
        case 85, 86: return "Snow showers"
        case 95...99: return "Thunderstorms"
        default: return "Mixed conditions"
        }
    }
}

// MARK: - Web Lookup Tool

@available(iOS 26.0, macOS 26.0, *)
struct TrinityWebSearchTool: Tool {
    let name = "searchWeb"
    let description = """
    Look up live facts on the internet. Call when the user asks about \
    people, places, events, definitions, or anything you might not know \
    or that could have changed recently. Returns a short factual summary.
    """

    @Generable
    struct Arguments {
        @Guide(description: "What to look up, e.g. 'Ethereum', 'Eiffel Tower height'.")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        let query = arguments.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return "Empty query." }

        // 1 — DuckDuckGo instant answer (great for definitions/abstracts)
        if let abstract = try? await Self.duckDuckGo(query: query), !abstract.isEmpty {
            return abstract
        }
        // 2 — Wikipedia search + summary
        if let summary = try? await Self.wikipedia(query: query), !summary.isEmpty {
            return summary
        }
        return "No reliable result found for \"\(query)\". Say so honestly rather than guessing."
    }

    private static func duckDuckGo(query: String) async throws -> String? {
        var comps = URLComponents(string: "https://api.duckduckgo.com/")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1"),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        struct IA: Decodable { let AbstractText: String?; let Answer: String? }
        let ia = try JSONDecoder().decode(IA.self, from: data)
        if let answer = ia.Answer, !answer.isEmpty { return answer }
        if let abstract = ia.AbstractText, !abstract.isEmpty { return abstract }
        return nil
    }

    private static func wikipedia(query: String) async throws -> String? {
        // Find the best-matching page title…
        var search = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        search.queryItems = [
            URLQueryItem(name: "action", value: "opensearch"),
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "format", value: "json"),
        ]
        let (data, _) = try await URLSession.shared.data(from: search.url!)
        guard let parsed = try JSONSerialization.jsonObject(with: data) as? [Any],
              parsed.count > 1,
              let titles = parsed[1] as? [String],
              let title = titles.first else { return nil }

        // …then pull its summary.
        let escaped = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(escaped)")!
        let (summaryData, _) = try await URLSession.shared.data(from: url)
        struct Summary: Decodable { let extract: String? }
        return try JSONDecoder().decode(Summary.self, from: summaryData).extract
    }
}

#endif

// MARK: - One-shot Location Provider

/// Minimal async wrapper over CLLocationManager: request permission if
/// needed, deliver one fix, never block longer than a few seconds.
final class TrinityLocationProvider: NSObject, CLLocationManagerDelegate {

    static let shared = TrinityLocationProvider()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Current coordinates, or nil when permission is denied/unavailable.
    func coordinates() async -> CLLocationCoordinate2D? {
        // Cached fix from the last few minutes is plenty for weather.
        if let recent = manager.location,
           recent.timestamp.timeIntervalSinceNow > -300 {
            return recent.coordinate
        }

        switch manager.authorizationStatus {
        case .denied, .restricted:
            return nil
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }

        return await withCheckedContinuation { cont in
            continuation = cont
            manager.requestLocation()
            // Hard timeout so a missing fix can't hang the model turn.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.finish(with: self?.manager.location?.coordinate)
            }
        }
    }

    private func finish(with coordinate: CLLocationCoordinate2D?) {
        continuation?.resume(returning: coordinate)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(with: locations.last?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: nil)
    }
}
