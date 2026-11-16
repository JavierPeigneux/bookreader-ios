import SwiftUI
import AVFoundation

struct ReaderView: View {
    @Bindable var model: ReaderViewModel
    @AppStorage("reader.showListeningTimes") private var showListeningTimes = false
    @State private var availableVoices = ReaderVoice.available
    @State private var showVoiceSettings = false
    @State private var settingsOpenFailed = false
    @State private var listeningSessionID: UUID?
    @State private var showChapters = false
    @State private var hasPresentedChapters = false
    private var currentChapter: ReadingChapter? { model.chapters.first { $0.range.contains(model.book.position) } }
    private var visibleBlocks: [ReadingBlock] {
        guard let chapter = currentChapter else { return model.book.blocks }
        return Array(model.book.blocks[chapter.range])
    }
    private func resumeFromHistory(_ index: Int) {
        // Freeze the historical session before replay creates a new timestamp.
        if listeningSessionID == nil {
            listeningSessionID = (model.book.listeningSessions ?? []).reversed().first { $0.blocks[index] != nil }?.id
        }
        model.resumeFromHistory(index)
    }

    private func refreshVoices() {
        availableVoices = ReaderVoice.available
    }
    private var selectedVoiceMissing: Bool { !availableVoices.contains(model.voice) }

    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    Text(model.book.title).font(.system(.largeTitle, design: .serif)).foregroundStyle(FolioPalette.forest).padding(.bottom, 4)
                    ForEach(visibleBlocks) { block in
                        VStack(alignment: .leading, spacing: 10) {
                            if block.id == currentChapter?.start {
                                Text(block.heading).font(.caption.weight(.semibold)).foregroundStyle(FolioPalette.secondary)
                            }
                            if showListeningTimes, let date = model.book.lastListenedAt(block: block.id, sessionID: listeningSessionID) {
                                Button {
                                    resumeFromHistory(block.id)
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "clock")
                                        Text(date, format: .dateTime.day().month(.abbreviated).hour().minute())
                                    }
                                    .font(.caption2).monospacedDigit()
                                    .foregroundStyle(FolioPalette.secondary)
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(FolioPalette.highlight, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(String.localizedStringWithFormat(String(localized: "reader.history.heard_at"), date.formatted(date: .complete, time: .shortened)))
                                .accessibilityHint(String(localized: "reader.history.resume_hint"))
                                .accessibilityIdentifier("reader.listened.\(block.id)")
                            }
                            Text(block.text).foregroundStyle(FolioPalette.ink).font(.system(.title3, design: .serif)).lineSpacing(8)
                                .textSelection(.enabled)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(block.id == model.book.position ? FolioPalette.highlight : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                        .id(block.id)
                        .onTapGesture {
                            if showListeningTimes { resumeFromHistory(block.id) }
                            else { model.select(block.id) }
                        }
                    }
                }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .onAppear { proxy.scrollTo(model.book.position, anchor: .top) }
            .onChange(of: model.book.position) { _, position in withAnimation { proxy.scrollTo(position, anchor: .top) } }
        }
        .background(FolioPalette.paper)
        .toolbarBackground(FolioPalette.paper, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(model.book.format)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle(String(localized: "reader.history.show"), isOn: $showListeningTimes)
                    if !(model.book.listeningSessions ?? []).isEmpty {
                        Picker(String(localized: "reader.history.session"), selection: $listeningSessionID) {
                            Text(String(localized: "reader.history.latest")).tag(UUID?.none)
                            ForEach((model.book.listeningSessions ?? []).reversed()) { session in
                                Text(session.startedAt, format: .dateTime.day().month(.abbreviated).hour().minute().second())
                                    .tag(Optional(session.id))
                            }
                        }
                    } else {
                        Text(String(localized: "reader.history.empty"))
                    }
                    if model.positionBeforeHistoryJump != nil {
                        Button(String(localized: "reader.history.return")) { model.returnFromHistory() }
                    }
                } label: {
                    Label(String(localized: "reader.history.title"), systemImage: showListeningTimes ? "clock.fill" : "clock")
                }.accessibilityIdentifier("reader.history")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let currentChapter {
                        Button(String(localized: "preparation.chapter")) { model.prepareChapter(currentChapter) }.disabled(selectedVoiceMissing)
                    }
                    Button(String(localized: "preparation.book")) { model.prepareBook() }.disabled(selectedVoiceMissing)
                    Button(String(localized: "voice.download")) { showVoiceSettings = true }
                    if model.pendingPreparation != nil && !model.isGenerating {
                        Button(String(localized: "preparation.resume")) { model.resumePreparation() }
                    }
                } label: {
                    Label(String(localized: "preparation.menu"), systemImage: "arrow.down.circle")
                }.accessibilityIdentifier("reader.prepare")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showChapters = true } label: {
                    Label(String(localized: "reader.chapters.title"), systemImage: "list.bullet")
                }.accessibilityIdentifier("reader.chapters")
            }
        }
        .sheet(isPresented: $showChapters) {
            NavigationStack {
                List(model.chapters) { chapter in
                    Button {
                        model.selectChapter(chapter)
                        showChapters = false
                    } label: {
                        HStack(spacing: 12) {
                            Text(verbatim: "\(chapter.id + 1)").monospacedDigit().foregroundStyle(FolioPalette.secondary)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(chapter.title).foregroundStyle(FolioPalette.ink)
                                Text(String.localizedStringWithFormat(String(localized: "reader.chapters.cached"),
                                    Int64(model.cachedBlocks.intersection(chapter.range).count), Int64(chapter.range.count)))
                                    .font(.caption).foregroundStyle(FolioPalette.secondary)
                            }
                            Spacer()
                            if chapter.range.contains(model.book.position) {
                                Image(systemName: model.isPlaying ? "speaker.wave.2.fill" : "bookmark.fill")
                            }
                        }.padding(.vertical, 5)
                    }.listRowBackground(FolioPalette.surface)
                    .accessibilityIdentifier("chapter.\(chapter.id)")
                    .contextMenu {
                        Button(String(localized: "preparation.chapter")) {
                            model.prepareChapter(chapter)
                            showChapters = false
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(FolioPalette.paper)
                .toolbarBackground(FolioPalette.paper, for: .navigationBar)
                .navigationTitle(String(localized: "reader.chapters.title"))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "common.done")) { showChapters = false }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in
            availableVoices = ReaderVoice.available
        }
        .onAppear {
            availableVoices = ReaderVoice.available
            if !hasPresentedChapters && ["EPUB", "PDF"].contains(model.book.format) {
                hasPresentedChapters = true
                showChapters = true
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                HStack {
                    Picker(String(localized: "reader.voice"), selection: $model.voice) {
                        ForEach(availableVoices) { Text($0.title).tag($0) }
                        if !availableVoices.contains(model.voice) { Text(model.voice.title).tag(model.voice) }
                    }.disabled(model.isGenerating)
                    Spacer()
                    Text(verbatim: "\(model.book.position + 1) / \(model.book.blocks.count)").font(.caption.monospacedDigit()).foregroundStyle(FolioPalette.secondary)
                }
                if selectedVoiceMissing && !model.cachedBlocks.contains(model.book.position) {
                    VStack(spacing: 8) {
                        Text(String(localized: "voice.missing.title")).font(.subheadline.weight(.semibold))
                        Button(String(localized: "voice.download")) { showVoiceSettings = true }
                            .buttonStyle(.borderedProminent).foregroundStyle(FolioPalette.surface).accessibilityIdentifier("reader.voice.download")
                    }.frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 12) {
                        Button { model.select(model.book.position - 1) } label: { Image(systemName: "backward.end.fill") }
                            .frame(minWidth: 44, minHeight: 44).disabled(model.book.position == 0).accessibilityLabel(String(localized: "reader.section.previous"))
                        Button {
                            if model.isWaitingForPlayback { model.cancelPlaybackRequest() }
                            else { model.prepareAndPlay() }
                        } label: {
                            HStack {
                                if model.isWaitingForPlayback { ProgressView().tint(FolioPalette.surface) }
                                else { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill") }
                                Text(model.isWaitingForPlayback ? String(localized: "reader.audio.cancel") : model.isPlaying ? String(localized: "reader.pause") : String(localized: "reader.play"))
                            }.frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).foregroundStyle(FolioPalette.surface)
                            .accessibilityIdentifier("reader.playback")
                        Button { model.select(model.book.position + 1) } label: { Image(systemName: "forward.end.fill") }
                            .frame(minWidth: 44, minHeight: 44).disabled(model.book.position + 1 == model.book.blocks.count).accessibilityLabel(String(localized: "reader.section.next"))
                    }
                    Text(model.audioStatus).font(.caption).foregroundStyle(FolioPalette.secondary)
                        .multilineTextAlignment(.center).accessibilityIdentifier("reader.audio.status")
                }
                if model.isGenerating && !model.isWaitingForPlayback {
                    HStack {
                        Text(String.localizedStringWithFormat(String(localized: "reader.audio.saved"), Int64(model.preparationCompleted), Int64(model.preparationTotal)))
                        Spacer()
                        Button(String(localized: "reader.audio.stop_preparing")) { model.cancelGeneration() }
                    }.font(.caption).foregroundStyle(FolioPalette.secondary)
                } else if model.pendingPreparation != nil && !model.isWaitingForPlayback {
                    Button(String(localized: "preparation.resume")) { model.resumePreparation() }.font(.caption)
                }

            }.padding().frame(maxWidth: 720).frame(maxWidth: .infinity).background(FolioPalette.paper)
                .overlay(alignment: .top) { Rectangle().fill(FolioPalette.border).frame(height: 0.5) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshVoices(); model.didBecomeActive() } else { model.willResignActive() }
        }
        .sheet(isPresented: $showVoiceSettings) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 20) {
                    Text(String(localized: "voice.settings.route")).font(.title3.weight(.semibold))
                    Text(String(localized: "voice.settings.instructions"))
                    Button(String(localized: "voice.settings.open")) {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url) { success in settingsOpenFailed = !success }
                    }.buttonStyle(.borderedProminent).foregroundStyle(FolioPalette.surface).accessibilityIdentifier("reader.voice.openSettings")
                    if settingsOpenFailed { Text(String(localized: "voice.settings.failed")).foregroundStyle(FolioPalette.warning) }
                    Spacer()
                }.padding(24)
                    .navigationTitle(String(localized: "voice.download"))
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "common.done")) { showVoiceSettings = false } } }
            }.presentationDetents([.medium, .large])
        }
        .alert(String(localized: "reader.audio.title"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(String(localized: "voice.download")) { model.error = nil; showVoiceSettings = true }
            Button(String(localized: "common.ok")) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
