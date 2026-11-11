import SwiftUI

@main
struct BookreaderApp: App {
    @State private var coordinator = AppCoordinator()
    var body: some Scene {
        WindowGroup {
            LibraryView(coordinator: coordinator)
                .preferredColorScheme(.light)
                .tint(Color(red: 0.14, green: 0.38, blue: 0.32))
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    coordinator.handleMemoryWarning()
                }
                .onOpenURL { url in Task { await coordinator.importDocument(url) } }
        }
    }
}
