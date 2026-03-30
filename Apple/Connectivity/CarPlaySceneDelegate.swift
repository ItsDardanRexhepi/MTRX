// CarPlaySceneDelegate.swift
// MTRX — Connectivity
//
// CPTemplateApplicationSceneDelegate: CarPlay dashboard showing portfolio and Trinity AI

import CarPlay
import Combine
import Foundation

// MARK: - Data Models

struct CarPlayPortfolioItem: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let value: Decimal
    let changePercent: Double
}

struct CarPlayTrinityResponse {
    let text: String
    let timestamp: Date
    let category: ResponseCategory

    enum ResponseCategory {
        case portfolioSummary
        case marketUpdate
        case contractAlert
        case general
    }
}

// MARK: - Portfolio Data Provider Protocol

protocol CarPlayPortfolioProvider: AnyObject {
    func fetchPortfolio() async throws -> [CarPlayPortfolioItem]
    func fetchAlerts() async throws -> [String]
}

// MARK: - Trinity Voice Provider Protocol

protocol CarPlayTrinityProvider: AnyObject {
    func processQuery(_ query: String) async throws -> CarPlayTrinityResponse
}

// MARK: - CarPlaySceneDelegate

@available(iOS 16.0, *)
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?
    private var cancellables = Set<AnyCancellable>()
    private let portfolioSubject = CurrentValueSubject<[CarPlayPortfolioItem], Never>([])
    private let alertsSubject = CurrentValueSubject<[String], Never>([])

    weak var portfolioProvider: CarPlayPortfolioProvider?
    weak var trinityProvider: CarPlayTrinityProvider?

    private var portfolioTemplate: CPListTemplate?
    private var trinityTemplate: CPListTemplate?
    private var alertsTemplate: CPListTemplate?

    // MARK: - CPTemplateApplicationSceneDelegate

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        let tabBar = buildTabBarTemplate()
        interfaceController.setRootTemplate(tabBar, animated: true, completion: nil)
        startPeriodicRefresh()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
        cancellables.removeAll()
    }

    // MARK: - Tab Bar

    private func buildTabBarTemplate() -> CPTabBarTemplate {
        let portfolio = buildPortfolioTab()
        let trinity = buildTrinityTab()
        let alerts = buildAlertsTab()
        self.portfolioTemplate = portfolio
        self.trinityTemplate = trinity
        self.alertsTemplate = alerts

        let tabBar = CPTabBarTemplate(templates: [portfolio, trinity, alerts])
        tabBar.delegate = self
        return tabBar
    }

    // MARK: - Portfolio Tab

    private func buildPortfolioTab() -> CPListTemplate {
        let template = CPListTemplate(title: "Portfolio", sections: [])
        template.tabTitle = "Portfolio"
        template.tabSystemItem = .featured

        portfolioSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.refreshPortfolioUI(template, items: items)
            }
            .store(in: &cancellables)

        return template
    }

    private func refreshPortfolioUI(_ template: CPListTemplate, items: [CarPlayPortfolioItem]) {
        let listItems: [CPListItem] = items.map { item in
            let sign = item.changePercent >= 0 ? "+" : ""
            let detail = "\(sign)\(String(format: "%.2f", item.changePercent))%  •  $\(item.value)"
            let listItem = CPListItem(text: "\(item.name) (\(item.symbol))", detailText: detail)
            listItem.handler = { [weak self] _, completion in
                self?.showAssetDetail(item)
                completion()
            }
            return listItem
        }
        let totalValue = items.reduce(Decimal.zero) { $0 + $1.value }
        let headerItem = CPListItem(text: "Total Portfolio", detailText: "$\(totalValue)")
        let summarySection = CPListSection(items: [headerItem], header: "Summary", sectionIndexTitle: nil)
        let holdingsSection = CPListSection(items: listItems, header: "Holdings", sectionIndexTitle: nil)
        template.updateSections([summarySection, holdingsSection])
    }

    private func showAssetDetail(_ item: CarPlayPortfolioItem) {
        let rows: [CPListItem] = [
            CPListItem(text: "Value", detailText: "$\(item.value)"),
            CPListItem(text: "24h Change", detailText: "\(String(format: "%.2f", item.changePercent))%"),
            CPListItem(text: "Symbol", detailText: item.symbol),
        ]
        let section = CPListSection(items: rows, header: item.name, sectionIndexTitle: nil)
        let detail = CPListTemplate(title: item.name, sections: [section])
        interfaceController?.pushTemplate(detail, animated: true, completion: nil)
    }

    // MARK: - Trinity Tab

    private func buildTrinityTab() -> CPListTemplate {
        let voiceItem = CPListItem(text: "Talk to Trinity", detailText: "Voice-activated AI assistant")
        voiceItem.handler = { [weak self] _, completion in
            self?.startTrinityVoice()
            completion()
        }

        let quickActions: [CPListItem] = [
            ("Portfolio Summary", "Summarize current holdings"),
            ("Market Update", "Latest market conditions"),
            ("Pending Contracts", "Contracts needing review"),
            ("Gas Estimates", "Current network fees"),
        ].map { title, detail in
            let item = CPListItem(text: title, detailText: detail)
            item.handler = { [weak self] _, completion in
                self?.sendTrinityQuery(title)
                completion()
            }
            return item
        }

        let voiceSection = CPListSection(items: [voiceItem], header: "Voice", sectionIndexTitle: nil)
        let actionsSection = CPListSection(items: quickActions, header: "Quick Actions", sectionIndexTitle: nil)
        let template = CPListTemplate(title: "Trinity", sections: [voiceSection, actionsSection])
        template.tabTitle = "Trinity"
        template.tabSystemItem = .search
        return template
    }

    private func startTrinityVoice() {
        let listening = CPVoiceControlState(
            identifier: "listening",
            titleVariants: ["Listening..."],
            image: UIImage(systemName: "mic.fill") ?? UIImage()
        )
        let processing = CPVoiceControlState(
            identifier: "processing",
            titleVariants: ["Processing..."],
            image: UIImage(systemName: "brain") ?? UIImage()
        )
        let template = CPVoiceControlTemplate(voiceControlStates: [listening, processing])
        interfaceController?.presentTemplate(template, animated: true, completion: nil)
    }

    private func sendTrinityQuery(_ query: String) {
        Task {
            guard let provider = trinityProvider else { return }
            do {
                let response = try await provider.processQuery(query)
                await MainActor.run {
                    showTrinityResponse(response)
                }
            } catch {
                await MainActor.run {
                    showTrinityError(error)
                }
            }
        }
    }

    private func showTrinityResponse(_ response: CarPlayTrinityResponse) {
        let item = CPListItem(text: "Trinity", detailText: response.text)
        let section = CPListSection(items: [item], header: "Response", sectionIndexTitle: nil)
        let template = CPListTemplate(title: "Trinity", sections: [section])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    private func showTrinityError(_ error: Error) {
        let item = CPListItem(text: "Error", detailText: error.localizedDescription)
        let section = CPListSection(items: [item], header: "Trinity", sectionIndexTitle: nil)
        let template = CPListTemplate(title: "Error", sections: [section])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    // MARK: - Alerts Tab

    private func buildAlertsTab() -> CPListTemplate {
        let template = CPListTemplate(title: "Alerts", sections: [])
        template.tabTitle = "Alerts"
        template.tabSystemItem = .history

        alertsSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] alerts in
                self?.refreshAlertsUI(template, alerts: alerts)
            }
            .store(in: &cancellables)

        return template
    }

    private func refreshAlertsUI(_ template: CPListTemplate, alerts: [String]) {
        let items: [CPListItem] = alerts.isEmpty
            ? [CPListItem(text: "No Alerts", detailText: "All clear")]
            : alerts.map { CPListItem(text: $0, detailText: nil) }

        let section = CPListSection(items: items, header: "Recent", sectionIndexTitle: nil)
        template.updateSections([section])
    }

    // MARK: - Periodic Refresh

    private func startPeriodicRefresh() {
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshAllData()
            }
            .store(in: &cancellables)

        refreshAllData()
    }

    private func refreshAllData() {
        Task {
            if let provider = portfolioProvider {
                if let items = try? await provider.fetchPortfolio() {
                    portfolioSubject.send(items)
                }
                if let alerts = try? await provider.fetchAlerts() {
                    alertsSubject.send(alerts)
                }
            }
        }
    }
}

// MARK: - CPTabBarTemplateDelegate

@available(iOS 16.0, *)
extension CarPlaySceneDelegate: CPTabBarTemplateDelegate {
    func tabBarTemplate(_ tabBarTemplate: CPTabBarTemplate, didSelect selectedTemplate: CPTemplate) {
        // Analytics / state tracking on tab switch
    }
}
