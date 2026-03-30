// LocationManager.swift
// MTRX Apple Integration — Awareness
// CoreLocation GPS context with significant location monitoring

import CoreLocation
import Foundation

// MARK: - Location Manager

final class LocationManager: NSObject, CLLocationManagerDelegate {

    // MARK: - Shared Instance

    static let shared = LocationManager()

    // MARK: - Properties

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private(set) var currentLocation: CLLocation?
    private(set) var currentPlacemark: CLPlacemark?
    private var locationHistory: [LocationRecord] = []
    private var significantLocations: [SignificantLocation] = []

    private var onLocationUpdate: ((LocationContext) -> Void)?

    // MARK: - Data Models

    struct LocationContext {
        let coordinate: CLLocationCoordinate2D
        let altitude: CLLocationDistance
        let speed: CLLocationSpeed
        let placemark: CLPlacemark?
        let locationType: LocationType
        let isSignificantLocation: Bool
        let timestamp: Date
    }

    enum LocationType: String {
        case home
        case work
        case exchange // Near known crypto exchange offices
        case bank
        case retail
        case travel
        case unknown
    }

    struct LocationRecord {
        let location: CLLocation
        let placemark: CLPlacemark?
        let timestamp: Date
    }

    struct SignificantLocation {
        let coordinate: CLLocationCoordinate2D
        let label: String
        let type: LocationType
        let visitCount: Int
        let lastVisit: Date
    }

    // MARK: - Initialization

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.distanceFilter = 50 // meters
    }

    // MARK: - Authorization

    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }

    // MARK: - Location Updates

    func startUpdating(onUpdate: @escaping (LocationContext) -> Void) {
        self.onLocationUpdate = onUpdate
        locationManager.startUpdatingLocation()
    }

    func stopUpdating() {
        locationManager.stopUpdatingLocation()
        onLocationUpdate = nil
    }

    // MARK: - Significant Location Monitoring

    func startSignificantLocationMonitoring() {
        locationManager.startMonitoringSignificantLocationChanges()
    }

    func stopSignificantLocationMonitoring() {
        locationManager.stopMonitoringSignificantLocationChanges()
    }

    // MARK: - Geofencing

    func monitorRegion(center: CLLocationCoordinate2D, radius: CLLocationDistance, identifier: String) {
        let region = CLCircularRegion(center: center, radius: radius, identifier: identifier)
        region.notifyOnEntry = true
        region.notifyOnExit = true
        locationManager.startMonitoring(for: region)
    }

    func stopMonitoringRegion(identifier: String) {
        for region in locationManager.monitoredRegions {
            if region.identifier == identifier {
                locationManager.stopMonitoring(for: region)
            }
        }
    }

    // MARK: - Reverse Geocoding

    func reverseGeocode(_ location: CLLocation) async throws -> CLPlacemark? {
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        return placemarks.first
    }

    // MARK: - Current Context

    func currentContext() async -> LocationContext? {
        guard let location = currentLocation else { return nil }

        let placemark = try? await reverseGeocode(location)
        let locationType = classifyLocation(placemark: placemark)
        let isSignificant = isSignificantLocation(location.coordinate)

        return LocationContext(
            coordinate: location.coordinate,
            altitude: location.altitude,
            speed: location.speed,
            placemark: placemark,
            locationType: locationType,
            isSignificantLocation: isSignificant,
            timestamp: Date()
        )
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location

        Task {
            let placemark = try? await reverseGeocode(location)
            currentPlacemark = placemark
            let locationType = classifyLocation(placemark: placemark)

            locationHistory.append(LocationRecord(location: location, placemark: placemark, timestamp: Date()))
            if locationHistory.count > 1000 {
                locationHistory.removeFirst(500)
            }

            let context = LocationContext(
                coordinate: location.coordinate,
                altitude: location.altitude,
                speed: location.speed,
                placemark: placemark,
                locationType: locationType,
                isSignificantLocation: isSignificantLocation(location.coordinate),
                timestamp: Date()
            )

            await MainActor.run {
                onLocationUpdate?(context)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        NotificationCenter.default.post(name: .trinityGeofenceEntered, object: region)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        NotificationCenter.default.post(name: .trinityGeofenceExited, object: region)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Log but don't crash — location is supplementary
    }

    // MARK: - Location Classification

    private func classifyLocation(placemark: CLPlacemark?) -> LocationType {
        guard let placemark = placemark else { return .unknown }

        // Check against known significant locations
        if let name = placemark.name?.lowercased() {
            if name.contains("bank") || name.contains("finance") { return .bank }
            if name.contains("exchange") || name.contains("trading") { return .exchange }
        }

        if placemark.areasOfInterest?.contains(where: { $0.lowercased().contains("airport") }) == true {
            return .travel
        }

        return .unknown
    }

    private func isSignificantLocation(_ coordinate: CLLocationCoordinate2D) -> Bool {
        for significant in significantLocations {
            let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: CLLocation(latitude: significant.coordinate.latitude, longitude: significant.coordinate.longitude))
            if distance < 200 { return true }
        }
        return false
    }

    // MARK: - Distance Calculation

    func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDistance {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLocation.distance(from: toLocation)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let trinityGeofenceEntered = Notification.Name("com.mtrx.trinity.geofence.entered")
    static let trinityGeofenceExited = Notification.Name("com.mtrx.trinity.geofence.exited")
}
