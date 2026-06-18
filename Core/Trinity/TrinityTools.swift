// TrinityTools.swift
// MTRX — Trinity
//
// Tools the on-device model can call during a conversation
// (Foundation Models tool calling, iOS 26+):
//
//   getWeather — current conditions via Apple WeatherKit, using the device
//                location when permitted or a named city (with attribution).
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
#if canImport(WeatherKit)
import WeatherKit
#endif

// MARK: - Apple Weather attribution
//
// WeatherKit REQUIRES attribution wherever its data is surfaced: the "Apple
// Weather" mark plus a link to Apple's legal attribution page. This store is
// flipped on the first successful WeatherKit fetch; the agent chat shows the
// attribution footer (AppleWeatherAttributionView) whenever it's active.

@MainActor
@Observable
final class WeatherKitAttribution {
    static let shared = WeatherKitAttribution()

    /// True once Trinity has surfaced WeatherKit data this session.
    private(set) var isActive = false
    /// Apple's legal attribution page (the "other data sources" link).
    private(set) var legalPageURL: URL?

    private var fetchedLegal = false

    func recordProvided() async {
        isActive = true
        guard !fetchedLegal else { return }
        fetchedLegal = true
        #if canImport(WeatherKit)
        if #available(iOS 16.0, macOS 13.0, *) {
            if let attribution = try? await WeatherService.shared.attribution {
                legalPageURL = attribution.legalPageURL
            }
        }
        #endif
    }
}

// MARK: - Tool Networking

/// Short-timeout session for all tool networking — one stalled request
/// must never eat the model's tool-call execution window.
enum TrinityToolNet {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 8
        return URLSession(configuration: config)
    }()
}

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
                #if DEBUG
                print("[Trinity.weather] explicit city: \(city)")
                #endif
                guard let geocoded = try await Self.geocode(city: city) else {
                    return "Couldn't find a city called \(city)."
                }
                place = geocoded
            } else if let located = await TrinityLocationProvider.shared.coordinates(maxWait: 6) {
                // Precise GPS fix (or a recently cached one).
                #if DEBUG
                print("[Trinity.weather] CL fix: \(located.latitude), \(located.longitude)")
                #endif
                let label = await Self.placeName(for: located) ?? "your current location"
                place = (located.latitude, located.longitude, label)
            } else if let approx = await TrinityLocationProvider.approximateByIP() {
                // GPS wasn't ready fast enough (or permission isn't
                // granted yet) — network-based location is city-level at
                // best and the ISP can place it in a neighboring city,
                // so it is labelled as approximate, never stated as fact.
                #if DEBUG
                print("[Trinity.weather] IP fallback: \(approx.label)")
                #endif
                place = (approx.latitude, approx.longitude,
                         "the \(approx.label) area (approximate network location — if this is the wrong city, the user can name theirs)")
            } else if !(await TrinityLocationProvider.servicesEnabled()) {
                #if DEBUG
                print("[Trinity.weather] FAIL: Location Services globally off, IP failed")
                #endif
                return """
                Location Services are turned off for this whole iPhone, and \
                the network lookup also failed. Tell the user to turn on \
                Location Services in Settings > Privacy & Security > Location \
                Services, or ask which city they want weather for. Do NOT \
                pick or guess a city yourself.
                """
            } else if await TrinityLocationProvider.shared.isAuthorizationDenied {
                #if DEBUG
                print("[Trinity.weather] FAIL: permission denied, IP failed")
                #endif
                return """
                Location permission is denied for this app. Tell the user to \
                enable it in Settings > Privacy & Security > Location Services \
                > MTRX, or ask which city they want weather for. Do NOT pick \
                or guess a city yourself.
                """
            } else {
                #if DEBUG
                print("[Trinity.weather] FAIL: no CL fix, no IP result")
                #endif
                return """
                The user's location is unavailable right now. Tell them you \
                can't see their location and ask which city they want weather \
                for. Do NOT pick, assume, or guess a city yourself.
                """
            }

            let weather = try await Self.fetchWeather(lat: place.lat, lon: place.lon)
            #if DEBUG
            print("[Trinity.weather] OK: \(place.label)")
            #endif
            return "Weather for \(place.label): \(weather)"
        } catch {
            #if DEBUG
            print("[Trinity.weather] ERROR: \(error)")
            #endif
            // Honest failure — never invent conditions. Most commonly this is
            // WeatherKit not yet enabled on the App ID, or a transient outage.
            return """
            I couldn't pull live weather right now — Apple Weather (WeatherKit) \
            may not be enabled for this app yet, or the service is briefly \
            unreachable. Tell the user honestly that you can't get current \
            conditions at the moment; do NOT make up the weather.
            """
        }
    }

    /// Reverse-geocode to a human place name so the answer names the
    /// user's real city rather than leaving the model room to guess.
    /// Hard 3s cap — a slow geocoder must not stall the tool window.
    private static func placeName(for coordinate: CLLocationCoordinate2D) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
                    return nil
                }
                let city = mark.locality ?? mark.subAdministrativeArea ?? mark.administrativeArea
                guard let city else { return nil }
                if let region = mark.administrativeArea, region != city {
                    return "\(city), \(region)"
                }
                return city
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: Geocoding (Apple CLGeocoder)

    private static func geocode(city: String) async throws -> (lat: Double, lon: Double, label: String)? {
        guard let placemark = try? await CLGeocoder().geocodeAddressString(city).first,
              let location = placemark.location else { return nil }
        let name = placemark.locality ?? placemark.name ?? city
        let label: String
        if let admin = placemark.administrativeArea, admin != name {
            label = "\(name), \(admin)"
        } else if let country = placemark.country {
            label = "\(name), \(country)"
        } else {
            label = name
        }
        return (location.coordinate.latitude, location.coordinate.longitude, label)
    }

    // MARK: Weather data — Apple WeatherKit

    /// Real current conditions from Apple WeatherKit. Throws if WeatherKit is
    /// unavailable (capability not enabled on the App ID, or a transient
    /// failure) — the caller surfaces that honestly rather than inventing data.
    private static func fetchWeather(lat: Double, lon: Double) async throws -> String {
        #if canImport(WeatherKit)
        guard #available(iOS 16.0, macOS 13.0, *) else {
            throw WeatherToolError.unavailable
        }
        let location = CLLocation(latitude: lat, longitude: lon)
        let weather = try await WeatherService.shared.weather(for: location)
        let current = weather.currentWeather

        // Apple REQUIRES attribution wherever this data is shown — record it so
        // the chat surfaces the Apple Weather mark + legal link.
        await WeatherKitAttribution.shared.recordProvided()

        let temp = current.temperature.converted(to: .fahrenheit).value
        let feels = current.apparentTemperature.converted(to: .fahrenheit).value
        let wind = current.wind.speed.converted(to: .milesPerHour).value
        let today = weather.dailyForecast.forecast.first
        let high = today?.highTemperature.converted(to: .fahrenheit).value ?? temp
        let low = today?.lowTemperature.converted(to: .fahrenheit).value ?? temp

        return String(
            format: "%@, %.0f°F (feels like %.0f°F), wind %.0f mph, today's high %.0f°F / low %.0f°F. (Source: Apple Weather.)",
            current.condition.description, temp, feels, wind, high, low
        )
        #else
        throw WeatherToolError.unavailable
        #endif
    }
}

enum WeatherToolError: Error { case unavailable }

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
        // 3 — Real web results: top snippets from a live search, for
        // the everyday questions instant answers don't cover.
        if let results = try? await Self.duckDuckGoWeb(query: query), !results.isEmpty {
            return results
        }
        return """
        The quick lookup returned nothing for "\(query)". Call searchWeb \
        once more with different, simpler terms. If that also comes back \
        empty, answer from your own knowledge with your best reasoned \
        answer — never reply that you can't answer.
        """
    }

    /// Scrapes the top snippets from DuckDuckGo's HTML results — no API
    /// key, works for news, how-tos, local facts, and anything current.
    private static func duckDuckGoWeb(query: String) async throws -> String? {
        var comps = URLComponents(string: "https://html.duckduckgo.com/html/")!
        comps.queryItems = [URLQueryItem(name: "q", value: query)]
        var request = URLRequest(url: comps.url!)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 19_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, _) = try await TrinityToolNet.session.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else { return nil }

        let pattern = #"class="result__snippet"[^>]*>(.*?)</a>"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let range = NSRange(html.startIndex..., in: html)
        var snippets: [String] = []
        regex.enumerateMatches(in: html, options: [], range: range) { match, _, stop in
            if let m = match, let r = Range(m.range(at: 1), in: html) {
                let stripped = html[r]
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&#x27;", with: "'")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&#39;", with: "'")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !stripped.isEmpty { snippets.append(stripped) }
                if snippets.count >= 3 { stop.pointee = true }
            }
        }
        guard !snippets.isEmpty else { return nil }
        return "Top web results for \"\(query)\":\n- " + snippets.joined(separator: "\n- ")
    }

    private static func duckDuckGo(query: String) async throws -> String? {
        var comps = URLComponents(string: "https://api.duckduckgo.com/")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1"),
        ]
        let (data, _) = try await TrinityToolNet.session.data(from: comps.url!)
        struct IA: Decodable { let AbstractText: String?; let Answer: String? }
        let ia = try JSONDecoder().decode(IA.self, from: data)
        if let answer = ia.Answer, !answer.isEmpty { return answer }
        if let abstract = ia.AbstractText, !abstract.isEmpty { return abstract }
        return nil
    }

    private static func wikipedia(query: String) async throws -> String? {
        // Find the best-matching page title — exact-prefix match first,
        // then full-text search for looser questions.
        var title: String?

        var search = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        search.queryItems = [
            URLQueryItem(name: "action", value: "opensearch"),
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "format", value: "json"),
        ]
        if let (data, _) = try? await TrinityToolNet.session.data(from: search.url!),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [Any],
           parsed.count > 1,
           let titles = parsed[1] as? [String] {
            title = titles.first
        }

        if title == nil {
            var fullText = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
            fullText.queryItems = [
                URLQueryItem(name: "action", value: "query"),
                URLQueryItem(name: "list", value: "search"),
                URLQueryItem(name: "srsearch", value: query),
                URLQueryItem(name: "srlimit", value: "1"),
                URLQueryItem(name: "format", value: "json"),
            ]
            struct SearchResponse: Decodable {
                struct Query: Decodable {
                    struct Hit: Decodable { let title: String }
                    let search: [Hit]
                }
                let query: Query?
            }
            if let (data, _) = try? await TrinityToolNet.session.data(from: fullText.url!) {
                title = (try? JSONDecoder().decode(SearchResponse.self, from: data))?
                    .query?.search.first?.title
            }
        }

        guard let title else { return nil }

        // …then pull that page's summary.
        let escaped = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(escaped)")!
        let (summaryData, _) = try await TrinityToolNet.session.data(from: url)
        struct Summary: Decodable { let extract: String? }
        return try JSONDecoder().decode(Summary.self, from: summaryData).extract
    }
}

// MARK: - Crypto Price Tool

@available(iOS 26.0, macOS 26.0, *)
struct TrinityCryptoPriceTool: Tool {
    let name = "getCryptoPrice"
    let description = """
    Get the live price and 24-hour change of a cryptocurrency in USD. \
    Call whenever the user asks about a coin or token price, how the \
    market is doing, or anything price-sensitive. Never quote a crypto \
    price from memory.
    """

    @Generable
    struct Arguments {
        @Guide(description: "Coin name or ticker, e.g. 'bitcoin', 'ETH', 'solana'.")
        var coin: String
    }

    /// Common tickers → CoinGecko ids; anything else goes through
    /// CoinGecko's own search.
    private static let knownIds: [String: String] = [
        "btc": "bitcoin", "bitcoin": "bitcoin",
        "eth": "ethereum", "ethereum": "ethereum",
        "sol": "solana", "solana": "solana",
        "usdc": "usd-coin", "usdt": "tether", "tether": "tether",
        "link": "chainlink", "chainlink": "chainlink",
        "uni": "uniswap", "uniswap": "uniswap",
        "aave": "aave",
        "ada": "cardano", "cardano": "cardano",
        "doge": "dogecoin", "dogecoin": "dogecoin",
        "xrp": "ripple", "ripple": "ripple",
        "matic": "polygon-ecosystem-token", "polygon": "polygon-ecosystem-token",
        "bnb": "binancecoin",
        "dot": "polkadot", "polkadot": "polkadot",
        "avax": "avalanche-2", "avalanche": "avalanche-2",
        "ltc": "litecoin", "litecoin": "litecoin",
    ]

    func call(arguments: Arguments) async throws -> String {
        let raw = arguments.coin.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !raw.isEmpty else { return "Which coin?" }

        do {
            guard let id = try await Self.resolveId(for: raw) else {
                return "Couldn't find a cryptocurrency called \(arguments.coin)."
            }

            var comps = URLComponents(string: "https://api.coingecko.com/api/v3/simple/price")!
            comps.queryItems = [
                URLQueryItem(name: "ids", value: id),
                URLQueryItem(name: "vs_currencies", value: "usd"),
                URLQueryItem(name: "include_24hr_change", value: "true"),
            ]
            let (data, _) = try await TrinityToolNet.session.data(from: comps.url!)
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: [String: Double]],
                  let entry = parsed[id],
                  let price = entry["usd"] else {
                return "Price for \(arguments.coin) is unavailable right now."
            }

            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = price >= 1 ? 2 : 4
            formatter.maximumFractionDigits = price >= 1 ? 2 : 4
            let priceText = "$" + (formatter.string(from: NSNumber(value: price)) ?? String(price))
            if let change = entry["usd_24h_change"] {
                let direction = change >= 0 ? "up" : "down"
                return "\(id.capitalized): \(priceText), \(direction) \(String(format: "%.1f", abs(change)))% in the last 24h."
            }
            return "\(id.capitalized): \(priceText)."
        } catch {
            return "Price lookup failed: \(error.localizedDescription)"
        }
    }

    private static func resolveId(for query: String) async throws -> String? {
        if let known = knownIds[query] { return known }

        var comps = URLComponents(string: "https://api.coingecko.com/api/v3/search")!
        comps.queryItems = [URLQueryItem(name: "query", value: query)]
        let (data, _) = try await TrinityToolNet.session.data(from: comps.url!)
        struct SearchResult: Decodable {
            struct Coin: Decodable { let id: String }
            let coins: [Coin]
        }
        return try JSONDecoder().decode(SearchResult.self, from: data).coins.first?.id
    }
}

#endif

// MARK: - One-shot Location Provider

/// Async wrapper over CLLocationManager: request permission if needed,
/// deliver one fix, never block longer than a few seconds.
///
/// Everything touches the manager on the main thread — CLLocationManager
/// delegate callbacks silently never fire when the manager lives on a
/// run-loop-less background thread, which is exactly where Swift
/// concurrency may land a tool call.
///
/// The last good fix is persisted so Siri turns running in the
/// background (where iOS may refuse a fresh when-in-use fix) can still
/// answer for the user's real area instead of failing.
final class TrinityLocationProvider: NSObject, CLLocationManagerDelegate {

    static let shared = TrinityLocationProvider()

    private static let persistKey = "com.mtrx.trinity.lastLocationFix"
    /// A GPS fix names the right city for hours — far better than the
    /// network fallback, whose ISP routing can land a city over.
    private static let persistedFixMaxAge: TimeInterval = 6 * 60 * 60

    private var manager: CLLocationManager?
    private var continuations: [CheckedContinuation<CLLocationCoordinate2D?, Never>] = []
    private var authContinuations: [CheckedContinuation<CLAuthorizationStatus, Never>] = []

    private override init() {
        super.init()
    }

    /// Lazily create the manager on the main thread only.
    private func managerOnMain() -> CLLocationManager {
        dispatchPrecondition(condition: .onQueue(.main))
        if let manager { return manager }
        let fresh = CLLocationManager()
        fresh.delegate = self
        fresh.desiredAccuracy = kCLLocationAccuracyKilometer
        manager = fresh
        return fresh
    }

    /// Fire-and-forget refresh; call while the app is in the foreground.
    /// This is where the location-permission prompt is meant to appear,
    /// and where a long enough wait lets a cold GPS fix land and cache,
    /// so later tool calls (which must be fast) can read it instantly.
    func warmUp() {
        Task { _ = await coordinates(maxWait: 20) }
    }

    /// Current coordinates: fresh cached fix → new request (capped) →
    /// persisted recent fix → nil.
    ///
    /// `maxWait` is short for in-conversation tool calls (the model
    /// abandons a tool that blocks too long) and long for `warmUp`.
    func coordinates(maxWait: TimeInterval = 4) async -> CLLocationCoordinate2D? {
        // Master switch off → no dialog, no fix, ever. Skip straight to
        // the persisted fallback. (Must be read off the main thread.)
        guard await Self.servicesEnabled() else {
            #if DEBUG
            print("[Trinity.location] Location Services globally OFF")
            #endif
            return Self.persistedFix()
        }

        let live: CLLocationCoordinate2D? = await withCheckedContinuation { cont in
            DispatchQueue.main.async {
                let manager = self.managerOnMain()
                #if DEBUG
                print("[Trinity.location] auth=\(manager.authorizationStatus.rawValue) cached=\(String(describing: manager.location?.timestamp))")
                #endif

                // A fix from the last few minutes is plenty for weather.
                if let recent = manager.location,
                   recent.timestamp.timeIntervalSinceNow > -300 {
                    Self.persist(recent.coordinate)
                    cont.resume(returning: recent.coordinate)
                    return
                }

                switch manager.authorizationStatus {
                case .denied, .restricted:
                    cont.resume(returning: nil)
                    return
                case .notDetermined:
                    // Shows the permission dialog; the grant lands in
                    // locationManagerDidChangeAuthorization, which then
                    // starts the fix while we stay queued.
                    manager.requestWhenInUseAuthorization()
                default:
                    // Continuous updates, stopped on the first fix —
                    // requestLocation() gives up too easily on cold starts.
                    manager.startUpdatingLocation()
                }

                self.continuations.append(cont)

                DispatchQueue.main.asyncAfter(deadline: .now() + maxWait) {
                    self.finish(with: self.manager?.location?.coordinate)
                }
            }
        }

        if let live {
            Self.persist(live)
            return live
        }
        // No fresh fix in time — fall back to the last real fix from
        // when the app was open (background Siri turns, cold GPS).
        return Self.persistedFix()
    }

    /// Must run on main. Resumes every waiter exactly once.
    private func finish(with coordinate: CLLocationCoordinate2D?) {
        guard !continuations.isEmpty else { return }
        manager?.stopUpdatingLocation()
        let waiting = continuations
        continuations = []
        waiting.forEach { $0.resume(returning: coordinate) }
    }

    /// Whether the iPhone-wide Location Services switch is on. Read off
    /// the main thread — the system call can block.
    static func servicesEnabled() async -> Bool {
        await Task.detached { CLLocationManager.locationServicesEnabled() }.value
    }

    /// Ask for when-in-use authorization — shows the system dialog when
    /// status is undetermined — and resolve once the user decides.
    /// The single safe entry point for permission prompts (onboarding,
    /// settings): a throwaway CLLocationManager never sees the answer.
    func requestAuthorization() async -> CLAuthorizationStatus {
        await withCheckedContinuation { cont in
            DispatchQueue.main.async {
                let manager = self.managerOnMain()
                let status = manager.authorizationStatus
                guard status == .notDetermined else {
                    cont.resume(returning: status)
                    return
                }
                self.authContinuations.append(cont)
                manager.requestWhenInUseAuthorization()
            }
        }
    }

    /// Whether the user has explicitly denied location access.
    var isAuthorizationDenied: Bool {
        get async {
            await withCheckedContinuation { cont in
                DispatchQueue.main.async {
                    let status = self.managerOnMain().authorizationStatus
                    cont.resume(returning: status == .denied || status == .restricted)
                }
            }
        }
    }

    // MARK: Network-based approximate location (no permission needed)

    struct ApproximateLocation {
        let latitude: Double
        let longitude: Double
        let label: String
    }

    /// City-level location derived from the internet connection — the
    /// last resort so weather still works when Core Location can't
    /// deliver (permission denied, background Siri turn, no GPS).
    static func approximateByIP() async -> ApproximateLocation? {
        // Keyless HTTPS providers, tried in order; either one suffices.
        if let hit = await ipWhoIs() { return hit }
        #if DEBUG
        print("[Trinity.location] ipwho.is failed — trying ipapi.co")
        #endif
        if let hit = await ipApiCo() { return hit }
        #if DEBUG
        print("[Trinity.location] ipapi.co failed too — no IP location")
        #endif
        return nil
    }

    private static func ipWhoIs() async -> ApproximateLocation? {
        struct Who: Decodable {
            let success: Bool?
            let latitude: Double?
            let longitude: Double?
            let city: String?
            let region: String?
        }
        guard let url = URL(string: "https://ipwho.is/"),
              let (data, _) = try? await TrinityToolNet.session.data(from: url),
              let who = try? JSONDecoder().decode(Who.self, from: data),
              who.success != false,
              let lat = who.latitude, let lon = who.longitude else { return nil }
        let label = [who.city, who.region].compactMap { $0 }.joined(separator: ", ")
        return ApproximateLocation(latitude: lat, longitude: lon,
                                   label: label.isEmpty ? "your area" : label)
    }

    private static func ipApiCo() async -> ApproximateLocation? {
        struct Api: Decodable {
            let latitude: Double?
            let longitude: Double?
            let city: String?
            let region: String?
        }
        guard let url = URL(string: "https://ipapi.co/json/"),
              let (data, _) = try? await TrinityToolNet.session.data(from: url),
              let api = try? JSONDecoder().decode(Api.self, from: data),
              let lat = api.latitude, let lon = api.longitude else { return nil }
        let label = [api.city, api.region].compactMap { $0 }.joined(separator: ", ")
        return ApproximateLocation(latitude: lat, longitude: lon,
                                   label: label.isEmpty ? "your area" : label)
    }

    private static func persist(_ coordinate: CLLocationCoordinate2D) {
        UserDefaults.standard.set(
            ["lat": coordinate.latitude, "lon": coordinate.longitude,
             "at": Date().timeIntervalSince1970],
            forKey: persistKey
        )
    }

    private static func persistedFix() -> CLLocationCoordinate2D? {
        guard let dict = UserDefaults.standard.dictionary(forKey: persistKey),
              let lat = dict["lat"] as? Double,
              let lon = dict["lon"] as? Double,
              let at = dict["at"] as? Double,
              Date().timeIntervalSince1970 - at < persistedFixMaxAge else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // MARK: CLLocationManagerDelegate (delivered on main)

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus

        // Resolve anyone waiting on the permission dialog itself.
        if status != .notDetermined, !authContinuations.isEmpty {
            let waiting = authContinuations
            authContinuations = []
            waiting.forEach { $0.resume(returning: status) }
        }

        guard !continuations.isEmpty else { return }
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            finish(with: nil)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let coordinate = locations.last?.coordinate {
            Self.persist(coordinate)
        }
        finish(with: locations.last?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // kCLErrorLocationUnknown is transient — Core Location keeps
        // trying after it, so keep waiting for the fix or the timeout.
        if let clError = error as? CLError, clError.code == .locationUnknown {
            return
        }
        finish(with: nil)
    }
}
