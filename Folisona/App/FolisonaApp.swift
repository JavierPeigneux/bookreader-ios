import SwiftUI

@main
struct FolisonaApp: App {
    @State private var coordinator = AppCoordinator()
    init() {
        #if DEBUG
        // Keep XCTest independent of simulator context-menu animation completion.
        if ProcessInfo.processInfo.arguments.contains("--disable-animations") {
            UIView.setAnimationsEnabled(false)
        }
        #endif
    }
    var body: some Scene {
        WindowGroup {
            rootView
                .preferredColorScheme(.light)
                .tint(FolioPalette.forest)
                .foregroundStyle(FolioPalette.ink)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    coordinator.handleMemoryWarning()
                }
                .onOpenURL { url in Task { await coordinator.importDocument(url) } }
        }
    }
    @ViewBuilder private var rootView: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--launch-preview") {
            LaunchScreenPreview().ignoresSafeArea()
        } else { LibraryView(coordinator: coordinator) }
        #else
        LibraryView(coordinator: coordinator)
        #endif
    }

}

/// Shared palette inspired by the Folio icon: forest green and warm paper.
enum FolioPalette {
    static let forest = Color("AccentColor")
    static let paper = Color("FolioPaper")
    static let surface = Color("FolioSurface")
    static let ink = Color("FolioInk")
    static let secondary = Color("FolioSecondary")
    static let highlight = Color("FolioHighlight")
    static let border = Color("FolioBorder")
    static let warning = Color("FolioWarning")
}

#if DEBUG
private struct LaunchScreenPreview: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        UIStoryboard(name: "LaunchScreen", bundle: .main).instantiateInitialViewController()!
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}
#endif
