import SwiftUI

struct ReaderView: View {
    @Bindable var model: ReaderViewModel
    @AppStorage("reader.showListeningTimes") private var showListeningTimes = false
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

    private var preparationTimeLabel: String {
        guard let seconds = model.preparationRemainingSeconds else { return String(localized: "preparation.time.calculating") }
        if seconds < 60 { return String(localized: "preparation.time.less_than_minute") }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        let duration = formatter.string(from: ceil(seconds / 60) * 60) ?? ""
        return String.localizedStringWithFormat(String(localized: "preparation.time.remaining"), duration)
    }

    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    Text(model.book.title).font(.system(.largeTitle, design: .serif)).padding(.bottom, 4)
                    ForEach(visibleBlocks) { block in
                        VStack(alignment: .leading, spacing: 10) {
                            if block.id == currentChapter?.start {
                                Text(block.heading).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(.quaternary, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(String.localizedStringWithFormat(String(localized: "reader.history.heard_at"), date.formatted(date: .complete, time: .shortened)))
                                .accessibilityHint(String(localized: "reader.history.resume_hint"))
                                .accessibilityIdentifier("reader.listened.\(block.id)")
                            }
                            Text(block.text).font(.system(.title3, design: .serif)).lineSpacing(8)
                                .textSelection(.enabled)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(block.id == model.book.position ? Color.accentColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
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
        .background(Color(red: 0.98, green: 0.97, blue: 0.94))
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
                        Button(String(localized: "preparation.chapter")) { model.prepareChapter(currentChapter) }
                    }
                    Button(String(localized: "preparation.book")) { model.prepareBook() }
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
                            Text(verbatim: "\(chapter.id + 1)").monospacedDigit().foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(chapter.title).foregroundStyle(.primary)
                                Text(String.localizedStringWithFormat(String(localized: "reader.chapters.cached"),
                                    Int64(model.cachedBlocks.intersection(chapter.range).count), Int64(chapter.range.count)))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if chapter.range.contains(model.book.position) {
                                Image(systemName: model.isPlaying ? "speaker.wave.2.fill" : "bookmark.fill")
                            }
                        }.padding(.vertical, 5)
                    }.accessibilityIdentifier("chapter.\(chapter.id)")
                    .contextMenu {
                        Button(String(localized: "preparation.chapter")) {
                            model.prepareChapter(chapter)
                            showChapters = false
                        }
                    }
                }
                .navigationTitle(String(localized: "reader.chapters.title"))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "common.done")) { showChapters = false }
                    }
                }
            }
        }
        .onAppear {
            if !hasPresentedChapters && ["EPUB", "PDF"].contains(model.book.format) {
                hasPresentedChapters = true
                showChapters = true
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                HStack {
                    Picker(String(localized: "reader.voice"), selection: $model.voice) {
                        ForEach(ReaderVoice.allCases) { Text($0.title).tag($0) }
                    }.disabled(model.isGenerating)
                    Spacer()
                    Text(verbatim: "\(model.book.position + 1) / \(model.book.blocks.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if model.isGenerating {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(String(localized: "preparation.progress.title")).font(.caption.weight(.semibold))
                            Spacer()
                            Text(model.preparationProgress.fraction, format: .percent.precision(.fractionLength(0)))
                                .font(.caption.monospacedDigit())
                        }
                        ProgressView(value: model.preparationProgress.fraction)
                            .accessibilityLabel(String(localized: "preparation.progress.title"))
                            .accessibilityValue(model.preparationProgress.fraction.formatted(.percent.precision(.fractionLength(0))))
                            .accessibilityIdentifier("reader.preparation.progress")
                        Text(preparationTimeLabel).font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(String.localizedStringWithFormat(String(localized: "reader.chapters.cached"), Int64(model.preparationCompleted), Int64(model.preparationTotal))).font(.caption)
                    HStack {
                        ProgressView()
                        Text(model.generationPhase).font(.caption)
                        if let start = model.generationStartedAt {
                            Text(start, style: .timer).font(.caption.monospacedDigit())
                        }
                    }
                    Button(String(localized: "reader.generation.stop"), role: .cancel) { model.cancelGeneration() }
                }
                if !model.isGenerating || model.isPlaying || model.cachedBlocks.contains(model.book.position) {
                    HStack(spacing: 12) {
                        Button { model.select(model.book.position - 1) } label: { Image(systemName: "backward.end.fill") }
                            .frame(minWidth: 44, minHeight: 44).disabled(model.book.position == 0).accessibilityLabel(String(localized: "reader.section.previous"))
                        Button { model.prepareAndPlay() } label: {
                            Label(model.isPlaying ? String(localized: "reader.pause") : String(localized: "reader.play"), systemImage: model.isPlaying ? "pause.fill" : "play.fill")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent)
                        Button { model.select(model.book.position + 1) } label: { Image(systemName: "forward.end.fill") }
                            .frame(minWidth: 44, minHeight: 44).disabled(model.book.position + 1 == model.book.blocks.count).accessibilityLabel(String(localized: "reader.section.next"))
                    }
                }
                Text(model.status).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if model.isGenerating {
                    Text(model.backgroundGenerationAllowed ? String(localized: "preparation.background.active") : String(localized: "preparation.background.unavailable"))
                        .font(.caption2).foregroundStyle(.secondary)
                } else if model.pendingPreparation != nil {
                    Button(String(localized: "preparation.resume")) { model.resumePreparation() }
                }
                #if targetEnvironment(simulator)
                Text(String(localized: "reader.simulator.notice")).font(.caption2).foregroundStyle(.orange)
                #endif
            }.padding().frame(maxWidth: 720).frame(maxWidth: .infinity).background(.regularMaterial)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.didBecomeActive() } else { model.willResignActive() }
        }
        .alert(String(localized: "reader.audio.title"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(String(localized: "common.ok")) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
