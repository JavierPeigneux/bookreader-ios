import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Bindable var coordinator: AppCoordinator
    @State private var showImporter = false
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar
    var body: some View {
        @Bindable var library = coordinator.library
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "library.tagline")).font(.caption.weight(.semibold)).tracking(3).foregroundStyle(FolioPalette.secondary)
                        Text(String(localized: "library.title")).font(.system(size: 38, weight: .medium, design: .serif)).foregroundStyle(FolioPalette.forest)
                        Text(String(localized: "library.subtitle")).foregroundStyle(FolioPalette.secondary)
                    }.padding(.top, 20)
                    Button { showImporter = true } label: {
                        Label(library.isImporting ? String(localized: "library.importing") : String(localized: "library.import"), systemImage: "plus")
                            .font(.headline).frame(maxWidth: .infinity).padding(8)
                    }.buttonStyle(.borderedProminent).foregroundStyle(FolioPalette.surface).disabled(library.isImporting)
                    Text(verbatim: "EPUB · PDF · TXT · MARKDOWN").font(.caption2.weight(.medium)).tracking(1.5).foregroundStyle(FolioPalette.secondary)
                    if library.isImporting { ProgressView().frame(maxWidth: .infinity) }
                    if library.books.isEmpty {
                        Button(String(localized: "library.sample.spanish")) {
                            if let url = Bundle.main.url(forResource: "Bienvenida", withExtension: "txt") {
                                Task { await coordinator.importDocument(url) }
                            }
                        }.frame(maxWidth: .infinity)
                        ContentUnavailableView(String(localized: "library.empty.title"), systemImage: "books.vertical", description: Text(String(localized: "library.empty.description")))
                    } else {
                        ForEach(library.books) { book in
                            Button { coordinator.open(book); compactColumn = .detail } label: {
                                HStack(spacing: 16) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 9).fill(FolioPalette.forest).frame(width: 58, height: 76)
                                        Image(systemName: "book.closed").font(.title2).foregroundStyle(FolioPalette.surface)
                                    }
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(book.title).font(.system(.headline, design: .serif)).foregroundStyle(FolioPalette.ink).lineLimit(2)
                                        Text(String.localizedStringWithFormat(String(localized: "library.book.sections"), book.format, Int64(book.blocks.count))).font(.caption).foregroundStyle(FolioPalette.secondary)
                                        ProgressView(value: Double(book.position), total: Double(max(book.blocks.count, 1)))
                                    }
                                    Image(systemName: "chevron.right").font(.caption)
                                }.padding(16).background(FolioPalette.surface, in: RoundedRectangle(cornerRadius: 16))
                                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(FolioPalette.border, lineWidth: 0.5))
                            }.buttonStyle(.plain)
                                .contextMenu { Button(String(localized: "common.delete"), role: .destructive) { coordinator.delete(book) } }
                        }
                    }
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .background(FolioPalette.paper)
            .toolbarBackground(FolioPalette.paper, for: .navigationBar)
            .navigationTitle(String(localized: "app.name")).navigationBarTitleDisplayMode(.inline)
            .navigationSplitViewColumnWidth(min: 280, ideal: 350, max: 440)
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .plainText, UTType(filenameExtension: "epub") ?? .data, UTType(filenameExtension: "md") ?? .plainText], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let url = urls.first { Task { await coordinator.importDocument(url) } }
                case .failure(let error): library.error = error.localizedDescription
                }
            }
            .alert(String(localized: "error.operation.title"), isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
                Button(String(localized: "common.ok")) { library.error = nil }
            } message: { Text(library.error ?? "") }
        } detail: {
            if let reader = coordinator.reader {
                ReaderView(model: reader).id(reader.book.id)
            } else {
                ContentUnavailableView(String(localized: "library.selection.title"), systemImage: "book.pages", description: Text(String(localized: "library.selection.description")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(FolioPalette.paper)
                    .navigationTitle(String(localized: "reader.title"))
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: coordinator.selection) { _, selection in
            if selection != nil { compactColumn = .detail }
        }
    }
}
