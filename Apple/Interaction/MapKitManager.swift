// MapKitManager.swift
// MTRX Apple Integration — Interaction
//
// MapKit integration for property locations and supply chain visualization

import MapKit
import Foundation
import Combine

// MARK: - MapKitManager

final class MapKitManager: ObservableObject {

    static let shared = MapKitManager()

    @Published private(set) var propertyAnnotations: [PropertyAnnotation] = []
    @Published private(set) var supplyChainRoute: [SupplyChainWaypoint] = []
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )

    // MARK: - Property Locations

    func addPropertyAnnotation(title: String, tokenId: String, coordinate: CLLocationCoordinate2D, value: Double, status: String) {
        let annotation = PropertyAnnotation(
            id: UUID().uuidString,
            title: title,
            tokenId: tokenId,
            coordinate: coordinate,
            estimatedValue: value,
            status: status
        )
        propertyAnnotations.append(annotation)
    }

    func removePropertyAnnotation(id: String) {
        propertyAnnotations.removeAll { $0.id == id }
    }

    func centerOnProperty(id: String) {
        guard let annotation = propertyAnnotations.first(where: { $0.id == id }) else { return }
        region = MKCoordinateRegion(
            center: annotation.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    }

    // MARK: - Supply Chain Visualization

    func setSupplyChainRoute(waypoints: [SupplyChainWaypoint]) {
        supplyChainRoute = waypoints
    }

    func addWaypoint(name: String, coordinate: CLLocationCoordinate2D, status: WaypointStatus, timestamp: Date) {
        let waypoint = SupplyChainWaypoint(
            id: UUID().uuidString,
            name: name,
            coordinate: coordinate,
            status: status,
            timestamp: timestamp
        )
        supplyChainRoute.append(waypoint)
    }

    // MARK: - Geocoding

    func geocode(address: String) async throws -> CLLocationCoordinate2D {
        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.geocodeAddressString(address)
        guard let location = placemarks.first?.location else {
            throw MapKitError.geocodingFailed
        }
        return location.coordinate
    }

    func reverseGeocode(coordinate: CLLocationCoordinate2D) async throws -> String {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        guard let placemark = placemarks.first else {
            throw MapKitError.geocodingFailed
        }
        return [placemark.name, placemark.locality, placemark.country]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    // MARK: - Route Calculation

    func calculateRoute(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = .automobile

        let directions = MKDirections(request: request)
        let response = try await directions.calculate()
        guard let route = response.routes.first else {
            throw MapKitError.routeNotFound
        }
        return route
    }

    // MARK: - Search

    func searchNearby(query: String, region: MKCoordinateRegion) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region

        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        return response.mapItems
    }
}

// MARK: - Models

struct PropertyAnnotation: Identifiable {
    let id: String
    let title: String
    let tokenId: String
    let coordinate: CLLocationCoordinate2D
    let estimatedValue: Double
    let status: String
}

struct SupplyChainWaypoint: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let status: WaypointStatus
    let timestamp: Date
}

enum WaypointStatus: String {
    case origin, inTransit, checkpoint, delivered, delayed
}

enum MapKitError: LocalizedError {
    case geocodingFailed
    case routeNotFound
    case searchFailed

    var errorDescription: String? {
        switch self {
        case .geocodingFailed: return "Geocoding failed."
        case .routeNotFound: return "Route not found."
        case .searchFailed: return "Location search failed."
        }
    }
}
