import SwiftUI

@main
struct BookreaderApp: App {
    @UIApplicationDelegateAdaptor(ReaderAppDelegate.self) private var appDelegate
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

/// Install before the first scene. UIKit app notifications are also delivered
/// for SwiftUI scenes, unlike the legacy UIApplicationDelegate lifecycle methods.
@MainActor
final class ReaderAppDelegate: NSObject, UIApplicationDelegate {
    private let gpuLifecycle = GPUApplicationLifecycle()
}

@MainActor
final class GPUApplicationLifecycle {
    private let center: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    init(policy: GPUExecutionPolicy = .shared, center: NotificationCenter = .default) {
        self.center = center
        policy.setActive(false)
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
            // nil queue: execute synchronously on the posting thread. No Task hop.
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { _ in
                policy.setActive(false)
            })
        }
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { _ in
            policy.setActive(true)
        })
    }
    deinit { for observer in observers { center.removeObserver(observer) } }
}
