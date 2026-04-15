import SwiftUI
import WatchConnectivity

/// Minimal Trinity conversation interface on Apple Watch
struct WatchTrinityView: View {
    @StateObject private var viewModel = WatchTrinityViewModel()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.messages) { message in
                        WatchMessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 4)
            }
            .onChange(of: viewModel.messages.count) { _ in
                if let last = viewModel.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button { viewModel.startDictation() } label: {
                    Image(systemName: "mic.fill")
                }
            }
        }
        .navigationTitle("Trinity")
    }
}

struct WatchMessageBubble: View {
    let message: WatchMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer() }
            Text(message.text)
                .font(.caption2)
                .padding(6)
                .background(message.isUser ? Color.blue : Color.gray.opacity(0.3))
                .cornerRadius(8)
                .foregroundColor(.white)
            if !message.isUser { Spacer() }
        }
    }
}

struct WatchMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let timestamp: Date
}

@MainActor
final class WatchTrinityViewModel: NSObject, ObservableObject {
    @Published var messages: [WatchMessage] = [
        WatchMessage(text: "Hey. What do you need?", isUser: false, timestamp: Date())
    ]

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(handleResponse(_:)), name: .watchDataReceived, object: nil)
    }

    func startDictation() {
        // watchOS dictation handled by system text input controller
    }

    func sendMessage(_ text: String) {
        messages.append(WatchMessage(text: text, isUser: true, timestamp: Date()))
        guard WCSession.default.isReachable else {
            messages.append(WatchMessage(text: "Phone not reachable.", isUser: false, timestamp: Date()))
            return
        }
        WCSession.default.sendMessage(["trinity_query": text], replyHandler: { [weak self] reply in
            if let response = reply["trinity_response"] as? String {
                Task { @MainActor in
                    self?.messages.append(WatchMessage(text: response, isUser: false, timestamp: Date()))
                }
            }
        }, errorHandler: nil)
    }

    @objc private func handleResponse(_ notification: Notification) {
        if let data = notification.object as? [String: Any], let text = data["trinity_response"] as? String {
            messages.append(WatchMessage(text: text, isUser: false, timestamp: Date()))
        }
    }
}
