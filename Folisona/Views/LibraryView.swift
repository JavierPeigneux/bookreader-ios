import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Bindable var coordinator: AppCoordinator
    @State private var showImporter = false
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar
    @State private var query = ""
    @State private var selectedFolder: UUID?
    @State private var editor: LibraryNameTarget?
    private var library: LibraryViewModel { coordinator.library }
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
                    if let selectedFolder {
                        Button { self.selectedFolder = nil; query = "" } label: {
                            Label(String(localized: "library.all"), systemImage: "chevron.left")
                        }
                        Text(library.folders.first { $0.id == selectedFolder }?.name ?? "").font(.title2.bold())
                    } else {
                        ForEach(library.folders.filter { query.isEmpty || $0.name.localizedStandardContains(query) }) { folder in
                            folderRow(folder)
                        }
                    }
                    if library.books.isEmpty {
                        Button(String(localized: "library.sample.spanish")) {
                            if let url = Bundle.main.url(forResource: "Bienvenida", withExtension: "txt") {
                                Task { await coordinator.importDocument(url, folder: selectedFolder) }
                            }
                        }.frame(maxWidth: .infinity)
                        ContentUnavailableView(String(localized: "library.empty.title"), systemImage: "books.vertical", description: Text(String(localized: "library.empty.description")))
                    } else {
                        ForEach(library.visibleBooks(folder: selectedFolder, query: query)) { book in
                            HStack(spacing: 16) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 9).fill(FolioPalette.forest).frame(width: 58, height: 76)
                                    Image(systemName: "book.closed").font(.title2).foregroundStyle(FolioPalette.surface)
                                }
                                .onTapGesture { openBook(book) }
                                .accessibilityElement(children: .ignore)
                                .accessibilityAddTraits(.isImage)
                                .accessibilityLabel(Text(book.title))
                                .accessibilityIdentifier("book.cover." + book.id.uuidString)
                                .draggable("folisona-book:\(book.id.uuidString)")

                                Button { openBook(book) } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(book.title).font(.system(.headline, design: .serif)).foregroundStyle(FolioPalette.ink).lineLimit(2)
                                            Text(String.localizedStringWithFormat(String(localized: "library.book.sections"), book.format, Int64(book.blocks.count))).font(.caption).foregroundStyle(FolioPalette.secondary)
                                            Text(String.localizedStringWithFormat(String(localized: "reader.status.section"), Int64(book.position + 1), Int64(book.blocks.count))).font(.caption2).foregroundStyle(FolioPalette.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").font(.caption)
                                    }.contentShape(Rectangle())
                                }
                                .contextMenu {
                                    Button(String(localized: "library.book.rename")) {
                                        library.error = nil
                                        editor = LibraryNameTarget(book: book)
                                    }
                                    Menu(String(localized: "library.folder.move")) {
                                        Button(String(localized: "library.folder.unfiled")) { library.move(book.id, to: nil) }
                                        ForEach(library.folders) { folder in
                                            Button(folder.name) { library.move(book.id, to: folder.id) }
                                        }
                                    }
                                    Button(String(localized: "common.delete"), role: .destructive) { coordinator.delete(book) }
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(16).background(FolioPalette.surface, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(FolioPalette.border, lineWidth: 0.5))
                            .contentShape(Rectangle())
                            .dropDestination(for: String.self) { items, _ in
                                guard let id = droppedBook(items), id != book.id else { return false }
                                editFolder(books: [id, book.id]); return true
                            }
                        }
                    }
                    if !library.books.isEmpty && library.visibleBooks(folder: selectedFolder, query: query).isEmpty && (selectedFolder != nil || !query.isEmpty) {
                        ContentUnavailableView(String(localized: "library.no_results"), systemImage: "doc.text.magnifyingglass")
                    }
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .searchable(text: $query, prompt: String(localized: "library.search"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editFolder() } label: { Image(systemName: "folder.badge.plus") }
                        .accessibilityLabel(String(localized: "library.folder.new"))
                        .accessibilityIdentifier("folder.new")
                }
            }
            .background(FolioPalette.paper)
            .toolbarBackground(FolioPalette.paper, for: .navigationBar)
            .navigationTitle(String(localized: "app.name")).navigationBarTitleDisplayMode(.inline)
            .navigationSplitViewColumnWidth(min: 280, ideal: 350, max: 440)
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .plainText, UTType(filenameExtension: "epub") ?? .data, UTType(filenameExtension: "md") ?? .plainText], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let url = urls.first { Task { await coordinator.importDocument(url, folder: selectedFolder) } }
                case .failure(let error): library.error = error.localizedDescription
                }
            }
            .alert(String(localized: "error.operation.title"), isPresented: Binding(get: { library.error != nil && editor == nil }, set: { if !$0 { library.error = nil } })) {
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
        .sheet(item: $editor) { target in LibraryNameEditor(coordinator: coordinator, target: target) }
        .alert(String(localized: "library.duplicate.title"), isPresented: Binding(get: { library.duplicateBook != nil }, set: { if !$0 { library.duplicateBook = nil } })) {
            Button(String(localized: "library.duplicate.open")) {
                if let book = library.duplicateBook { coordinator.open(book) }
                library.duplicateBook = nil
            }
            Button(String(localized: "common.cancel"), role: .cancel) { library.duplicateBook = nil }
        } message: { Text(library.duplicateBook?.title ?? "") }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: coordinator.selection) { _, selection in
            if selection != nil { compactColumn = .detail }
        }
    }

    private func openBook(_ book: Book) {
        coordinator.open(book)
        compactColumn = .detail
    }

    private func editFolder(_ folder: LibraryFolder? = nil, books: [UUID] = []) {
        library.error = nil
        editor = LibraryNameTarget(folder: folder, grouping: books)
    }
    private func droppedBook(_ items: [String]) -> UUID? {
        guard items.count == 1, let item = items.first, item.hasPrefix("folisona-book:"),
              let id = UUID(uuidString: String(item.dropFirst("folisona-book:".count))),
              library.books.contains(where: { $0.id == id }) else { return nil }
        return id
    }
    private func folderRow(_ folder: LibraryFolder) -> some View {
        Button { selectedFolder = folder.id; query = "" } label: {
            HStack(spacing: 16) {
                Image(systemName: "folder.fill").font(.title).foregroundStyle(FolioPalette.forest)
                Text(folder.name).font(.headline).foregroundStyle(FolioPalette.ink)
                Spacer()
                Text(library.books.filter { library.folderID(for: $0) == folder.id }.count.formatted())
                    .foregroundStyle(FolioPalette.secondary)
                Image(systemName: "chevron.right").font(.caption)
            }.padding(20).background(FolioPalette.surface, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
        .contextMenu {
            Button(String(localized: "library.folder.rename")) { editFolder(folder) }
            Button(String(localized: "library.folder.remove"), role: .destructive) { library.removeFolder(folder) }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let id = droppedBook(items) else { return false }
            return library.move(id, to: folder.id)
        }
    }
}

private struct LibraryNameTarget: Identifiable {
    let id = UUID()
    var book: Book? = nil
    var folder: LibraryFolder? = nil
    var grouping: [UUID] = []
    var name: String { book?.title ?? folder?.name ?? "" }
    var title: String {
        if book != nil { return String(localized: "library.book.rename") }
        return folder == nil ? String(localized: "library.folder.new") : String(localized: "library.folder.rename")
    }
}

private struct LibraryNameEditor: View {
    @Bindable var coordinator: AppCoordinator
    let target: LibraryNameTarget
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    private var library: LibraryViewModel { coordinator.library }
    init(coordinator: AppCoordinator, target: LibraryNameTarget) {
        self.coordinator = coordinator; self.target = target
        _name = State(initialValue: target.name)
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField(target.book == nil ? String(localized: "library.folder.name") : String(localized: "library.book.name"), text: $name)
                    .accessibilityIdentifier(target.book == nil ? "folder.name" : "book.name")
                if let error = library.error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(target.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { library.error = nil; dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "library.folder.save")) {
                        library.error = nil
                        let saved: Bool
                        if let book = target.book { saved = coordinator.renameBook(book.id, name: name) }
                        else if let folder = target.folder { saved = library.renameFolder(folder, name: name) }
                        else { saved = library.createFolder(name: name, books: target.grouping) != nil }
                        if saved { dismiss() }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier(target.book == nil ? "folder.save" : "book.save")
                }
            }
        }.presentationDetents([.medium, .large])
    }
}
