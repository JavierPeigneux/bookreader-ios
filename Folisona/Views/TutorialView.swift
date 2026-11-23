import SwiftUI
import AVFoundation

enum TutorialSchedule {
    static func isDue(lastUse: Double, now: Date) -> Bool {
        lastUse == 0 || now.timeIntervalSince1970 - lastUse >= 20 * 24 * 60 * 60
    }

    static func hasBothLanguages(_ voices: [(String, AVSpeechSynthesisVoiceQuality)]) -> Bool {
        let languages = voices.compactMap { language, quality -> String? in
            guard quality == .enhanced || quality == .premium else { return nil }
            return language.split(separator: "-").first.map(String.init)
        }
        return Set(languages).isSuperset(of: ["es", "en"])
    }
}

struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @ScaledMetric private var artworkHeight: CGFloat = 240

    private struct Slide {
        let image: String
        let title: LocalizedStringKey
        let body: LocalizedStringKey
    }

    private let slides = [
        Slide(image: "LaunchArtwork", title: "tutorial.welcome.title", body: "tutorial.welcome.body"),
        Slide(image: "TutorialSettings", title: "tutorial.settings.title", body: "tutorial.settings.body"),
        Slide(image: "TutorialAccessibility", title: "tutorial.access.title", body: "tutorial.access.body"),
        Slide(image: "TutorialVoices", title: "tutorial.language.title", body: "tutorial.language.body"),
        Slide(image: "TutorialDownload", title: "tutorial.download.title", body: "tutorial.download.body"),
        Slide(image: "folder.badge.plus", title: "tutorial.group.title", body: "tutorial.group.body"),
        Slide(image: "pencil.line", title: "tutorial.rename.title", body: "tutorial.rename.body")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(slides.indices, id: \.self) { index in
                        Capsule().fill(index <= page ? FolioPalette.forest : FolioPalette.border)
                            .frame(width: index == page ? 20 : 7, height: 5)
                    }
                }.accessibilityHidden(true)
                Text(verbatim: "\(page + 1) / \(slides.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(FolioPalette.secondary)
                Spacer()
                Button("tutorial.skip") { dismiss() }
                    .font(.subheadline).frame(minHeight: 44)
                    .accessibilityIdentifier("tutorial.skip")
            }.padding(.horizontal, 24)

            TabView(selection: $page) {
                ForEach(slides.indices, id: \.self) { index in
                    let slide = slides[index]
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            artwork(slide, index: index)
                                .frame(height: min(artworkHeight, 270))
                                .frame(maxWidth: .infinity)
                                .background(FolioPalette.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 24))
                                .accessibilityHidden(true)
                                .padding(.bottom, 6)
                            Text(slide.title)
                                .font(.system(.largeTitle, design: .serif).weight(.medium))
                                .accessibilityAddTraits(.isHeader)
                            Text(slide.body).font(.body).lineSpacing(4)
                        }
                        .frame(maxWidth: 480, alignment: .leading)
                        .padding(.horizontal, 24).padding(.vertical, 16)
                    }.tag(index)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 12) {
                if page > 0 {
                    Button { withAnimation { page -= 1 } } label: {
                        Image(systemName: "arrow.backward").frame(width: 52, height: 52)
                            .overlay { Circle().strokeBorder(FolioPalette.border, lineWidth: 1.5) }
                    }
                    .accessibilityLabel(Text("tutorial.back"))
                    .accessibilityIdentifier("tutorial.back")
                }
                Button {
                    if page == slides.count - 1 { dismiss() } else { withAnimation { page += 1 } }
                } label: {
                    HStack {
                        Text(nextTitle).font(.headline)
                        Spacer()
                        Image(systemName: "arrow.forward").accessibilityHidden(true)
                    }
                    .padding(.horizontal, 22).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(FolioPalette.forest, in: Capsule()).foregroundStyle(.white)
                }.accessibilityIdentifier("tutorial.next")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 480).padding(.horizontal, 24).padding(.vertical, 12)
        }
        .padding(.top, 14).background(FolioPalette.paper).foregroundStyle(FolioPalette.ink)
    }

    private var nextTitle: LocalizedStringKey {
        if page == 0 { return "tutorial.start" }
        return page == slides.count - 1 ? "tutorial.finish" : "tutorial.next"
    }

    @ViewBuilder
    private func artwork(_ slide: Slide, index: Int) -> some View {
        if index < 5 {
            GeometryReader { geometry in
                Image(slide.image).resizable()
                    .aspectRatio(contentMode: index == 0 ? .fill : .fit)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
        } else {
            ZStack {
                Circle().fill(FolioPalette.highlight.opacity(0.45)).frame(width: 146, height: 146)
                Image(systemName: slide.image).font(.system(size: 62, weight: .light))
                    .foregroundStyle(FolioPalette.forest)
            }
        }
    }
}
