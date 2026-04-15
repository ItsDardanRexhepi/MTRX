// WeatherManager.swift
// MTRX Apple Integration — Awareness
// WeatherKit integration for insurance triggers and risk assessment

import WeatherKit
import CoreLocation
import Foundation

// MARK: - Weather Manager

final class WeatherManager {

    // MARK: - Shared Instance

    static let shared = WeatherManager()

    // MARK: - Properties

    private let weatherService = WeatherService.shared

    // MARK: - Weather Context

    struct WeatherContext {
        let current: CurrentConditions
        let alerts: [WeatherAlert]
        let forecast: ForecastSummary
        let insuranceTriggers: [InsuranceTrigger]
        let riskLevel: WeatherRiskLevel
        let timestamp: Date
    }

    struct CurrentConditions {
        let temperature: Double
        let feelsLike: Double
        let humidity: Double
        let windSpeed: Double
        let windGust: Double?
        let uvIndex: Int
        let visibility: Double
        let pressure: Double
        let condition: String
        let isDaylight: Bool
    }

    struct WeatherAlert {
        let severity: AlertSeverity
        let event: String
        let headline: String
        let description: String
        let effectiveDate: Date
        let expirationDate: Date
        let affectedRegion: String
    }

    enum AlertSeverity: String {
        case minor, moderate, severe, extreme
    }

    struct ForecastSummary {
        let hourlyHighTemp: Double
        let hourlyLowTemp: Double
        let precipitationChance: Double
        let expectedCondition: String
        let snowfallAmount: Double?
        let rainfallAmount: Double?
    }

    // MARK: - Insurance Triggers

    struct InsuranceTrigger {
        let type: InsuranceTriggerType
        let severity: Double // 0.0 to 1.0
        let description: String
        let affectedProducts: [String]
        let timestamp: Date
    }

    enum InsuranceTriggerType: String {
        case extremeHeat
        case extremeCold
        case hurricane
        case tornado
        case flood
        case wildfire
        case hailstorm
        case earthquake // Not weather but included for parametric insurance
        case drought
        case frost
    }

    enum WeatherRiskLevel: String {
        case minimal, low, moderate, elevated, high, extreme
    }

    // MARK: - Fetch Weather Context

    func fetchContext(for location: CLLocation) async throws -> WeatherContext {
        let weather = try await weatherService.weather(for: location)

        let current = mapCurrentConditions(weather.currentWeather)
        let alerts = mapAlerts(weather.weatherAlerts)
        let forecast = mapForecast(weather.hourlyForecast)
        let triggers = evaluateInsuranceTriggers(current: current, alerts: alerts, forecast: forecast)
        let risk = calculateRiskLevel(current: current, alerts: alerts, triggers: triggers)

        return WeatherContext(
            current: current,
            alerts: alerts,
            forecast: forecast,
            insuranceTriggers: triggers,
            riskLevel: risk,
            timestamp: Date()
        )
    }

    // MARK: - Current Conditions Mapping

    private func mapCurrentConditions(_ weather: CurrentWeather) -> CurrentConditions {
        return CurrentConditions(
            temperature: weather.temperature.value,
            feelsLike: weather.apparentTemperature.value,
            humidity: weather.humidity,
            windSpeed: weather.wind.speed.value,
            windGust: weather.wind.gust?.value,
            uvIndex: weather.uvIndex.value,
            visibility: weather.visibility.value,
            pressure: weather.pressure.value,
            condition: weather.condition.description,
            isDaylight: weather.isDaylight
        )
    }

    // MARK: - Alert Mapping

    private func mapAlerts(_ alerts: [WeatherKit.WeatherAlert]?) -> [WeatherAlert] {
        guard let alerts = alerts else { return [] }
        return alerts.map { alert in
            let severity: AlertSeverity
            switch alert.severity {
            case .minor: severity = .minor
            case .moderate: severity = .moderate
            case .severe: severity = .severe
            case .extreme: severity = .extreme
            default: severity = .moderate
            }

            return WeatherAlert(
                severity: severity,
                event: alert.summary,
                headline: alert.summary,
                description: alert.detailsURL.absoluteString,
                effectiveDate: alert.metadata.date,
                expirationDate: alert.metadata.expirationDate,
                affectedRegion: alert.region ?? "Unknown"
            )
        }
    }

    // MARK: - Forecast Mapping

    private func mapForecast(_ hourly: Forecast<HourWeather>) -> ForecastSummary {
        let next24Hours = hourly.forecast.prefix(24)
        let temps = next24Hours.map { $0.temperature.value }
        let precipChances = next24Hours.map { $0.precipitationChance }

        return ForecastSummary(
            hourlyHighTemp: temps.max() ?? 0,
            hourlyLowTemp: temps.min() ?? 0,
            precipitationChance: precipChances.max() ?? 0,
            expectedCondition: next24Hours.first?.condition.description ?? "Unknown",
            snowfallAmount: nil,
            rainfallAmount: nil
        )
    }

    // MARK: - Insurance Trigger Evaluation

    private func evaluateInsuranceTriggers(
        current: CurrentConditions,
        alerts: [WeatherAlert],
        forecast: ForecastSummary
    ) -> [InsuranceTrigger] {
        var triggers: [InsuranceTrigger] = []
        let now = Date()

        // Extreme heat trigger (> 40C / 104F)
        if current.temperature > 40 {
            triggers.append(InsuranceTrigger(
                type: .extremeHeat,
                severity: min((current.temperature - 40) / 10, 1.0),
                description: "Temperature exceeds extreme heat threshold",
                affectedProducts: ["crop-insurance", "property-insurance", "health-parametric"],
                timestamp: now
            ))
        }

        // Extreme cold trigger (< -20C / -4F)
        if current.temperature < -20 {
            triggers.append(InsuranceTrigger(
                type: .extremeCold,
                severity: min((-20 - current.temperature) / 20, 1.0),
                description: "Temperature below extreme cold threshold",
                affectedProducts: ["pipe-freeze-insurance", "crop-insurance"],
                timestamp: now
            ))
        }

        // High wind trigger (> 100 km/h)
        if current.windSpeed > 100 {
            triggers.append(InsuranceTrigger(
                type: .hurricane,
                severity: min((current.windSpeed - 100) / 100, 1.0),
                description: "Wind speed exceeds hurricane-force threshold",
                affectedProducts: ["property-insurance", "travel-insurance"],
                timestamp: now
            ))
        }

        // Frost trigger (temperature near or below freezing with high humidity)
        if current.temperature <= 2 && current.humidity > 0.7 {
            triggers.append(InsuranceTrigger(
                type: .frost,
                severity: 0.6,
                description: "Frost conditions detected",
                affectedProducts: ["crop-insurance"],
                timestamp: now
            ))
        }

        // Alert-based triggers
        for alert in alerts where alert.severity == .extreme || alert.severity == .severe {
            let event = alert.event.lowercased()
            if event.contains("tornado") {
                triggers.append(InsuranceTrigger(
                    type: .tornado, severity: 1.0,
                    description: alert.headline,
                    affectedProducts: ["property-insurance", "vehicle-insurance"],
                    timestamp: now
                ))
            }
            if event.contains("flood") {
                triggers.append(InsuranceTrigger(
                    type: .flood, severity: 0.9,
                    description: alert.headline,
                    affectedProducts: ["flood-insurance", "property-insurance"],
                    timestamp: now
                ))
            }
        }

        return triggers
    }

    // MARK: - Risk Level Calculation

    private func calculateRiskLevel(
        current: CurrentConditions,
        alerts: [WeatherAlert],
        triggers: [InsuranceTrigger]
    ) -> WeatherRiskLevel {
        if triggers.contains(where: { $0.severity > 0.8 }) { return .extreme }
        if alerts.contains(where: { $0.severity == .extreme }) { return .high }
        if alerts.contains(where: { $0.severity == .severe }) { return .elevated }
        if !triggers.isEmpty { return .moderate }
        if alerts.contains(where: { $0.severity == .moderate }) { return .low }
        return .minimal
    }
}
