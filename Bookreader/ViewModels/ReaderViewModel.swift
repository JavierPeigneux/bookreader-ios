import Foundation
import AVFoundation
import MediaPlayer
import Observation
import UIKit

@MainActor @Observable
final class ReaderViewModel: NSObject, AVAudioPlayerDelegate {
    private(set) var book: Book
    var voice: ReaderVoice = .dora { didSet { if oldValue != voice { changeVoice() } } }
    private(set) var isGenerating = false
    private(set) var isPlaying = false
    var error: String?
    var status = String(localized: "reader.status.ready")
    let chapters: [ReadingChapter]
    private(set) var generationStartedAt: Date?
    private(set) var generationPhase = ""
    private(set) var cachedBlocks: Set<Int> = []
    private(set) var preparationCompleted = 0
    private(set) var preparationTotal = 0
    private(set) var pendingPreparation: AudioPreparation?
    private(set) var backgroundGenerationAllowed = false
    private let audioStore: PreparedAudioStore
    private let isAppActive: @MainActor () -> Bool
    private let makeLease: @MainActor () -> any BackgroundGenerationManaging
    private var lease: (any BackgroundGenerationManaging)?
    private var wantsPlayback = false
    private var generationID = UUID()
    private let service: any SpeechGenerating
    private let save: (Book) -> Void
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    private var playbackID = UUID()
    @ObservationIgnored private var remoteTargets: [(MPRemoteCommand, Any)] = []
    @ObservationIgnored private var interruption: NSObjectProtocol?
    private var playbackVoice: ReaderVoice = .dora
    var current: ReadingBlock { book.blocks[book.position] }

    init(book: Book, service: any SpeechGenerating,
         audioStore: PreparedAudioStore = PreparedAudioStore(),
         isAppActive: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active },
         makeLease: @escaping @MainActor () -> any BackgroundGenerationManaging = { BackgroundGenerationLease() },
         save: @escaping (Book) -> Void) {
        self.book = book
        self.chapters = book.chapters
        self.service = service
        self.audioStore = audioStore
        self.isAppActive = isAppActive
        self.makeLease = makeLease
        self.pendingPreparation = audioStore.pending(book: book.id)
        self.save = save
        super.init()
        self.book.position = min(max(0, book.position), max(0, book.blocks.count - 1))
        refreshCache()
        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pause() }
        }
    }
    deinit { if let interruption { NotificationCenter.default.removeObserver(interruption) } }

    func audioURL(index: Int, voice: ReaderVoice) -> URL {
        audioStore.playbackURL(book: book.id, voice: voice, index: index)
    }

    func prepareAndPlay() {
        if isPlaying { pause(); return }
        wantsPlayback = true
        playbackVoice = voice
        error = nil
        if (task == nil || pendingPreparation?.range.contains(book.position) != true),
           !(book.position..<book.blocks.count).allSatisfy(cachedBlocks.contains), isAppActive() {
            prepare(range: book.position..<book.blocks.count)
        }
        ensureAudio()
    }

    func prepareChapter(_ chapter: ReadingChapter) { prepare(range: chapter.range) }
    func prepareBook() { prepare(range: book.blocks.indices) }
    func resumePreparation() {
        guard let pendingPreparation else { return }
        if voice != pendingPreparation.voice { pause(); player = nil; voice = pendingPreparation.voice; refreshCache() }
        prepare(range: pendingPreparation.range)
    }

    private func prepare(range: Range<Int>) {
        guard !range.isEmpty, range.lowerBound >= 0, range.upperBound <= book.blocks.count else { return }
        guard isAppActive() else { status = String(localized: "preparation.reopen"); return }
        stopPreparation()
        let job = AudioPreparation(voice: voice, lowerBound: range.lowerBound, upperBound: range.upperBound)
        do { try audioStore.save(job, book: book.id) }
        catch { self.error = error.localizedDescription; return }
        pendingPreparation = job
        refreshCache()
        preparationTotal = range.count
        preparationCompleted = range.filter(cachedBlocks.contains).count
        let ticket = UUID()
        generationID = ticket
        let session = makeLease()
        lease = session
        isGenerating = true
        generationStartedAt = Date()
        UIApplication.shared.isIdleTimerDisabled = true
        session.request(title: book.title, onChange: { [weak self, weak session] in
            guard let self, self.generationID == ticket else { return }
            self.backgroundGenerationAllowed = session?.canRunInBackground == true
        }, onExpiration: { [weak self] in
            guard let self, self.generationID == ticket else { return }
            self.stopPreparation()
            self.status = String(localized: "preparation.interrupted")
        })
        session.report(completed: preparationCompleted, total: preparationTotal)
        task = Task { [weak self, service] in
            var success = false
            defer {
                session.finish(success: success)
                if let self, self.generationID == ticket { self.finishGeneration() }
            }
            do {
                guard let self else { return }
                while let needed = range.first(where: { !self.cachedBlocks.contains($0) }) {
                    try Task.checkCancellation()
                    guard self.isAppActive() || session.canRunInBackground else {
                        throw ReaderError.message(String(localized: "preparation.reopen"))
                    }
                    self.generationPhase = String(localized: "reader.generation.loading")
                    let destination = self.audioStore.destination(book: self.book.id, voice: job.voice, index: needed)
                    // Migrate legacy cache while preparing offline; Caches is purgeable.
                    let existing = self.audioURL(index: needed, voice: job.voice)
                    if FileManager.default.fileExists(atPath: existing.path) {
                        try self.persistCachedAudio(from: existing, to: destination)
                    } else {
                        _ = try await service.generate(text: self.book.blocks[needed].text, voice: job.voice, destination: destination) { [weak self] phase in
                            Task { @MainActor in
                                guard let self, self.generationID == ticket else { return }
                                switch phase {
                                case .loading: self.generationPhase = String(localized: "reader.generation.loading")
                                case .synthesizing: self.generationPhase = String(localized: "reader.generation.synthesizing")
                                case .saving: self.generationPhase = String(localized: "reader.generation.saving")
                                }
                            }
                        }
                    }
                    try Task.checkCancellation()
                    guard self.generationID == ticket else { return }
                    self.cachedBlocks.insert(needed)
                    self.preparationCompleted = range.filter(self.cachedBlocks.contains).count
                    session.report(completed: self.preparationCompleted, total: self.preparationTotal)
                    self.ensureAudio()
                }
                // Existing legacy audio also needs promotion before declaring it offline-ready.
                for index in range {
                    try Task.checkCancellation()
                    try self.persistCachedAudio(from: self.audioURL(index: index, voice: job.voice),
                        to: self.audioStore.destination(book: self.book.id, voice: job.voice, index: index))
                }
                try self.audioStore.complete(book: self.book.id)
                self.pendingPreparation = nil
                success = true
                self.status = String(localized: "preparation.ready")
                self.ensureAudio()
            } catch {
                guard let self, self.generationID == ticket else { return }
                if !(error is CancellationError) { self.error = error.localizedDescription }
                self.status = String(localized: "preparation.interrupted")
                // Playback remains independent and can consume everything already saved.
            }
        }
    }

    private func persistCachedAudio(from source: URL, to destination: URL) throws {
        guard source != destination else { return }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try FileManager.default.copyItem(at: source, to: destination)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
    }

    private func ensureAudio() {
        guard wantsPlayback, playbackTask == nil else { return }
        if !isPlaying, cachedBlocks.contains(book.position) { startPlayback() }
        else if !isPlaying, task == nil { status = String(localized: "preparation.reopen") }
    }

    private func finishGeneration() {
        task = nil
        isGenerating = false
        generationStartedAt = nil
        backgroundGenerationAllowed = false
        lease = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func stopPreparation() {
        generationID = UUID()
        task?.cancel()
        // A running task retains its lease until the current inference has stopped.
        if task == nil { lease?.finish(success: false) }
        finishGeneration()
    }

    func cancelGeneration() {
        stopPreparation()
        status = String(localized: "preparation.interrupted")
    }

    func willResignActive() {
        if isGenerating && lease?.canRunInBackground != true {
            stopPreparation()
            status = String(localized: "preparation.reopen")
        }
    }

    func didBecomeActive() { refreshCache(); if wantsPlayback { ensureAudio() } }

    private func refreshCache() { cachedBlocks = audioStore.available(book: book.id, voice: voice) }

    private func cancelPlaybackStart() {
        playbackID = UUID()
        playbackTask?.cancel()
        playbackTask = nil
    }

    func selectChapter(_ chapter: ReadingChapter) {
        let resume = wantsPlayback || isPlaying
        select(chapter.start)
        if resume { prepareAndPlay() }
    }

    private func startPlayback() {
        let ticket = UUID()
        playbackID = ticket
        let url = audioURL(index: book.position, voice: playbackVoice)
        // Enqueue synchronously so a subsequent close() cannot overtake activation.
        let activation = ReaderAudioSession.activate()
        playbackTask = Task { [weak self] in
            do {
                try await activation.value
                try Task.checkCancellation()
                guard let self, self.playbackID == ticket, self.wantsPlayback else { return }
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw ReaderError.message(String(localized: "error.audio.missing_section"))
                }
                // Transfer exclusive ownership while preparing off-main. This also
                // prepares a paused player again after an audio-session interruption.
                let suspendedPlayer = self.player
                self.player = nil
                let prepared = try await Task.detached {
                    let player: AVAudioPlayer
                    if let suspendedPlayer { player = suspendedPlayer }
                    else { player = try AVAudioPlayer(contentsOf: url) }
                    guard player.prepareToPlay() else { throw ReaderError.message(String(localized: "error.audio.play")) }
                    return player
                }.value
                try Task.checkCancellation()
                guard self.playbackID == ticket, self.wantsPlayback else { return }
                self.player = prepared
                self.player?.delegate = self
                guard self.player?.play() == true else { throw ReaderError.message(String(localized: "error.audio.play")) }
                self.isPlaying = true
                self.status = String.localizedStringWithFormat(String(localized: "reader.status.playing"), self.playbackVoice.title)
                self.registerRemoteCommands()
                self.updateNowPlaying()
                self.playbackTask = nil
                self.ensureAudio()
            } catch {
                guard let self, self.playbackID == ticket else { return }
                self.playbackTask = nil
                self.wantsPlayback = false
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }

    func pause() {
        wantsPlayback = false
        cancelPlaybackStart()
        player?.pause()
        isPlaying = false
        status = String(localized: "reader.status.paused")
        updateNowPlaying()
    }
    func select(_ index: Int) {
        guard book.blocks.indices.contains(index) else { return }
        cancelGeneration()
        wantsPlayback = false
        cancelPlaybackStart()
        player?.stop(); player = nil; isPlaying = false
        book.position = index
        save(book)
        status = String.localizedStringWithFormat(String(localized: "reader.status.section"), Int64(index + 1), Int64(book.blocks.count))
        updateNowPlaying()
    }
    func changeVoice() { cancelGeneration(); pause(); player = nil; refreshCache() }
    func close() {
        cancelGeneration()
        pause()
        player = nil
        for (command, target) in remoteTargets { command.removeTarget(target) }
        remoteTargets.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        ReaderAudioSession.deactivate()
        save(book)
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.player = nil
            self.isPlaying = false
            guard flag else { self.error = String(localized: "error.audio.interrupted"); return }
            guard self.wantsPlayback else { self.updateNowPlaying(); return }
            if self.book.position + 1 < self.book.blocks.count {
                self.book.position += 1
                self.save(self.book)
                self.ensureAudio()
            } else {
                self.wantsPlayback = false
                self.status = String(localized: "reader.status.finished")
                self.save(self.book)
                self.updateNowPlaying()
            }
        }
    }
    private func registerRemoteCommands() {
        guard remoteTargets.isEmpty else { return }
        let commands = MPRemoteCommandCenter.shared()
        remoteTargets.append((commands.pauseCommand, commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }; return .success
        }))
        remoteTargets.append((commands.playCommand, commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.prepareAndPlay() }; return .success
        }))
    }
    private func updateNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: book.title,
            MPMediaItemPropertyArtist: current.heading,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPMediaItemPropertyPlaybackDuration: player?.duration ?? 0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player?.currentTime ?? 0
        ]
    }
}

/// Serializes the process-wide session across readers without blocking the UI.
/// Awaiting a system callback is reentrant; an explicit queue prevents an old
/// reader's deactivation from racing a new reader's activation.
@MainActor
private enum ReaderAudioSession {
    private static var tail: Task<Void, Never>?

    static func activate() -> Task<Void, Error> {
        let previous = tail
        let operation = Task.detached {
            await previous?.value
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                session.activate(options: []) { activated, error in
                    if let error { continuation.resume(throwing: error) }
                    else if activated { continuation.resume() }
                    else { continuation.resume(throwing: ReaderError.message(String(localized: "error.audio.play"))) }
                }
            }
        }
        tail = Task { _ = await operation.result }
        return operation
    }

    static func deactivate() {
        let previous = tail
        tail = Task.detached {
            await previous?.value
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                AVAudioSession.sharedInstance().deactivate(options: .notifyOthersOnDeactivation) { _, _ in
                    continuation.resume()
                }
            }
        }
    }
}
