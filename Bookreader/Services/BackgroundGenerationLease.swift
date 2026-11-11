import BackgroundTasks
import UIKit

@MainActor
protocol BackgroundGenerationManaging: AnyObject {
    var canRunInBackground: Bool { get }
    func request(title: String, onChange: @escaping @MainActor () -> Void, onExpiration: @escaping @MainActor () -> Void)
    func report(completed: Int, total: Int)
    func finish(success: Bool)
}

/// One finite, user-initiated job. A lease is never reused for another book/job.
@MainActor
final class BackgroundGenerationLease: BackgroundGenerationManaging {
    private(set) var canRunInBackground = false
    private let permissionID = UUID()
    private var identifier: String?
    private var task: BGContinuedProcessingTask?
    private var finished = false
    private var expired = false
    private var completed = 0
    private var total = 1

    func request(title: String, onChange: @escaping @MainActor () -> Void, onExpiration: @escaping @MainActor () -> Void) {
        guard identifier == nil, !finished else { return }
        #if !targetEnvironment(simulator)
        guard UIApplication.shared.applicationState == .active,
              BGTaskScheduler.supportedResources.contains(.gpu) else { onChange(); return }
        let id = "com.javierpeigneux.Bookreader.audio.\(UUID().uuidString)"
        identifier = id
        let permissionID = self.permissionID
        GPUExecutionPolicy.shared.register(permissionID)
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { [weak self] received in
            guard let task = received as? BGContinuedProcessingTask else { received.setTaskCompleted(success: false); return }
            task.expirationHandler = { [weak self] in
                GPUExecutionPolicy.shared.revoke(permissionID)
                Task { @MainActor in
                    guard let self, !self.finished else { return }
                    self.expired = true
                    self.canRunInBackground = false
                    onExpiration()
                    // The native gate is already closed; a worker may now wait for
                    // foreground. Complete the expired system task without waiting.
                    self.finish(success: false)
                }
            }
            Task { @MainActor in
                guard let self, !self.finished else { task.setTaskCompleted(success: false); return }
                self.task = task
                guard !self.expired, GPUExecutionPolicy.shared.grant(permissionID) else { return }
                self.canRunInBackground = true
                self.report(completed: self.completed, total: self.total)
                onChange()
            }
        }
        guard registered else { GPUExecutionPolicy.shared.revoke(permissionID); identifier = nil; onChange(); return }
        let request = BGContinuedProcessingTaskRequest(identifier: id, title: title, subtitle: String(localized: "preparation.system.subtitle"))
        request.requiredResources = .gpu
        // Do not leave an orphaned request waiting after the user stops the job.
        request.strategy = .fail
        do { try BGTaskScheduler.shared.submit(request) }
        catch { GPUExecutionPolicy.shared.revoke(permissionID); onChange() } // Foreground preparation remains available.
        #else
        onChange()
        #endif
    }
    func report(completed: Int, total: Int) {
        self.completed = completed
        self.total = max(1, total)
        task?.progress.totalUnitCount = Int64(self.total)
        task?.progress.completedUnitCount = Int64(min(completed, self.total))
    }
    func finish(success: Bool) {
        guard !finished else { return }
        GPUExecutionPolicy.shared.revoke(permissionID)
        finished = true
        canRunInBackground = false
        if let task { task.setTaskCompleted(success: success) }
        else if let identifier { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier) }
        task = nil
    }
}
