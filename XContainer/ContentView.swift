import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

// Root: 5 fixed tabs + one extra tab per pinned module ("panel in your tab").
struct ContentView: View {
    @StateObject private var store = ModuleStore()
    @State private var selection = "home"

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                HomeView(selection: $selection)
            }
            .tabItem { Label("Home", systemImage: "square.grid.2x2") }
            .tag("home")

            NavigationStack {
                ModulesView(selection: $selection)
            }
            .tabItem { Label("Modules", systemImage: "square.stack") }
            .tag("modules")

            NavigationStack {
                TemplatesView(selection: $selection)
            }
            .tabItem { Label("Templates", systemImage: "doc.on.doc") }
            .tag("templates")

            NavigationStack {
                EditorView(selection: $selection)
            }
            .tabItem { Label("Editor", systemImage: "pencil") }
            .tag("editor")

            NavigationStack {
                AppsView()
            }
            .tabItem { Label("Apps", systemImage: "sparkles") }
            .tag("apps")

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag("settings")

            // Each pinned module becomes its own tab. Tap it -> live output.
            ForEach(store.modules.filter { $0.isPinned }) { mod in
                NavigationStack {
                    ModulePanelView(moduleID: mod.id)
                }
                .tabItem { Label(mod.name, systemImage: "play.square") }
                .tag("panel-" + mod.id.uuidString)
            }
        }
        .environmentObject(store)
        .preferredColorScheme(.dark)
        .onChange(of: store.modules.filter { $0.isPinned }.map(\.id)) { _, _ in
            // If the selected pinned tab was unpinned/deleted, fall back to Modules.
            if selection.hasPrefix("panel-") {
                let idString = String(selection.dropFirst("panel-".count))
                let stillPinned = store.modules.contains(where: { $0.id.uuidString == idString && $0.isPinned })
                if !stillPinned { selection = "modules" }
            }
        }
    }
}

// MARK: - Home
struct HomeView: View {
    @EnvironmentObject var store: ModuleStore
    @Binding var selection: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("XContainer")
                    .font(.largeTitle.bold())
                Text("A small container for your scripts and modules.")
                    .foregroundStyle(.secondary)
                Text("Modules: \(store.modules.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                navCard(title: "Open Modules", sub: "View and manage your modules.", icon: "square.stack") {
                    selection = "modules"
                }
                navCard(title: "Browse Templates", sub: "Copy a starter, add it, use it.", icon: "doc.on.doc") {
                    selection = "templates"
                }
                navCard(title: "Create Script", sub: "Start a new module with custom code.", icon: "pencil") {
                    store.editingModuleID = nil
                    selection = "editor"
                }
                navCard(title: "Recommended Apps", sub: "Tools similar to XContainer.", icon: "sparkles") {
                    selection = "apps"
                }
                navCard(title: "Settings", sub: "App info and module controls.", icon: "gearshape") {
                    selection = "settings"
                }

                if !store.modules.filter({ $0.isPinned }).isEmpty {
                    Text("My Panels")
                        .font(.headline)
                        .padding(.top, 4)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(store.modules.filter { $0.isPinned }) { mod in
                            NavigationLink {
                                ModuleDetailView(moduleID: mod.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Image(systemName: "play.square")
                                        .font(.title2)
                                    Text(mod.name).font(.headline)
                                    Text("Tap to see output")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color(white: 0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Home")
        .background(Color.black.ignoresSafeArea())
    }

    private func navCard(title: String, sub: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(sub).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: icon).foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(white: 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Templates gallery: copy -> Add module -> Use
struct TemplatesView: View {
    @EnvironmentObject var store: ModuleStore
    @Binding var selection: String
    @State private var query = ""
    @State private var category = "All"
    @State private var addedName = ""

    var categories: [String] {
        var s = Set(ModuleStore.templates.map { $0.category })
        s.insert("All")
        return ["All"] + s.sorted()
    }

    var filtered: [Template] {
        ModuleStore.templates.filter { t in
            (category == "All" || t.category == category)
            && (query.isEmpty || t.name.localizedCaseInsensitiveContains(query) || t.blurb.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack {
            Picker("Category", selection: $category) {
                ForEach(categories, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            if !addedName.isEmpty {
                Text("Added \"" + addedName + "\" — find it in Modules.")
                    .font(.caption)
                    .padding(8)
                    .background(Color.green.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
            }
            List(filtered) { t in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(t.name).font(.headline)
                        Spacer()
                        Text(t.category).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(t.blurb).font(.caption).foregroundStyle(.secondary)
                    Text(t.code)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    HStack {
                        Spacer()
                        Button("Copy") {
                            UIPasteboard.general.string = t.code
                            addedName = ""
                        }.buttonStyle(.bordered)
                        Button("Use template") {
                            let m = store.useTemplate(t)
                            addedName = m.name
                            store.editingModuleID = m.id
                        }.buttonStyle(.borderedProminent)
                        Button("Use & Open") {
                            let m = store.useTemplate(t)
                            addedName = ""
                            store.editingModuleID = m.id
                            selection = "editor"
                        }.buttonStyle(.bordered)
                    }
                    .font(.caption)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.black)
        }
        .searchable(text: $query, prompt: "Search templates")
        .navigationTitle("Templates")
        .background(Color.black.ignoresSafeArea())
    }
}

// MARK: - Modules list (search + sort + safe run + file export)
struct ModulesView: View {
    @EnvironmentObject var store: ModuleStore
    @Binding var selection: String
    @State private var lastRunText = ""
    @State private var lastRunError = ""
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportURL: URL? = nil
    @State private var query = ""
    @State private var sortBy = "Recent"
    @StateObject private var quickRunner = SafeRunner()
    @State private var quickName = ""

    var filtered: [Module] {
        var list = store.modules
        if !query.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.code.localizedCaseInsensitiveContains(query) }
        }
        switch sortBy {
        case "Name": list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case "Oldest": list.sort { $0.createdAt < $1.createdAt }
        default: list.sort { $0.createdAt > $1.createdAt }
        }
        return list
    }

    var body: some View {
        VStack {
            Picker("Sort", selection: $sortBy) {
                Text("Recent").tag("Recent")
                Text("Name").tag("Name")
                Text("Oldest").tag("Oldest")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            if store.modules.isEmpty {
                Text("No modules yet. Grab one from Templates or tap + below.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
            if quickRunner.isRunning {
                HStack {
                    ProgressView().scaleEffect(0.8)
                    Text("Running " + quickName + "…")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Stop") { quickRunner.stop() }.font(.caption)
                }
                .padding(.horizontal)
            } else if let r = quickRunner.result {
                RunOutputView(result: r)
                    .padding(.horizontal)
            }
            List {
                ForEach(filtered) { mod in
                    VStack(alignment: .leading, spacing: 8) {
                        NavigationLink {
                            ModuleDetailView(moduleID: mod.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(mod.name).font(.headline)
                                    Spacer()
                                    if mod.isPinned {
                                        Image(systemName: "pin.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text(mod.code)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        HStack {
                            Spacer()
                            Button("Run") { quickRun(mod) }
                                .buttonStyle(.bordered)
                            Button(mod.isPinned ? "Unpin" : "Pin") {
                                store.togglePin(mod)
                            }
                            .buttonStyle(.bordered)
                            Button("Edit") {
                                store.editingModuleID = mod.id
                                selection = "editor"
                            }
                            .buttonStyle(.bordered)
                            Button("Duplicate") {
                                let c = store.duplicate(mod)
                                lastRunError = ""
                                lastRunText = "Duplicated as \"" + c.name + "\""
                            }
                            .buttonStyle(.bordered)
                            Button("Copy") {
                                UIPasteboard.general.string = mod.code
                                lastRunError = ""
                                lastRunText = mod.name + ": code copied"
                            }
                            .buttonStyle(.bordered)
                            ShareLink("Share", item: mod.code)
                                .buttonStyle(.bordered)
                            ShareLink("File", item: moduleFileURL(mod))
                                .buttonStyle(.bordered)
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                    .swipeActions {
                        Button(role: .destructive) { store.delete(mod) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.black)

            if !lastRunText.isEmpty {
                Text(lastRunText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.blue.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
            }
            if !lastRunError.isEmpty {
                Text(lastRunError)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.red.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
            }
        }
        .navigationTitle("Modules")
        .searchable(text: $query, prompt: "Search modules")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showImporter = true
                } label: { Image(systemName: "square.and.arrow.down") }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    exportAll()
                } label: { Image(systemName: "square.and.arrow.up") }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.editingModuleID = nil
                    selection = "editor"
                } label: { Image(systemName: "plus") }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.plainText, .javaScript]) { res in
            do {
                let url = try res.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
                    let base = url.deletingPathExtension().lastPathComponent
                    let m = store.importModule(name: base.isEmpty ? "Imported module" : base, code: text)
                    lastRunError = ""
                    lastRunText = "Imported \"" + m.name + "\""
                } else {
                    lastRunError = "Could not read that file (empty or not UTF-8)."
                }
            } catch {
                lastRunError = "Import failed: " + error.localizedDescription
            }
        }
        .fileExporter(isPresented: $showExporter, document: ExportDoc(url: exportURL), contentType: .json, defaultFilename: "xcontainer-modules.json") { _ in }
        .onChange(of: quickRunner.result) { _, _ in
            if let r = quickRunner.result {
                let summary = ([r.logs.joined(separator: " "), r.result].filter { !$0.isEmpty }.joined(separator: " | ")).prefix(120)
                store.recordRun(moduleName: quickName, summary: summary.isEmpty ? "(no output)" : String(summary), hadError: r.error != nil && !(r.error ?? "").isEmpty)
            }
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func moduleFileURL(_ mod: Module) -> URL {
        let safe = mod.name.replacingOccurrences(of: "/", with: "-").prefix(40)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(String(safe) + ".js")
        try? mod.code.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func exportAll() {
        let arr = store.modules.map { ["name": $0.name, "code": $0.code, "pinned": $0.isPinned] as [String: Any] }
        if let data = try? JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted]) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("xcontainer-modules.json")
            try? data.write(to: url)
            exportURL = url
            showExporter = true
        }
    }

    private func quickRun(_ mod: Module) {
        // Off-main-thread so a looping module never freezes the list.
        quickName = mod.name
        lastRunError = ""
        lastRunText = ""
        quickRunner.start(mod.code)
    }
}

// Wrapper so Export-All can use .fileExporter.
struct ExportDoc: FileDocument {
    var url: URL?
    static var readableContentTypes: [UTType] { [.json] }
    init(url: URL?) { self.url = url }
    init(configuration: ReadConfiguration) throws { self.url = nil }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if let url, let data = try? Data(contentsOf: url) {
            return FileWrapper(regularFileWithContents: data)
        }
        return FileWrapper(regularFileWithContents: Data("{}".utf8))
    }
}

// MARK: - Safe runner (JS runs off main thread, Stop + timeout included)
final class SafeRunner: ObservableObject {
    @Published var result: JSRunResult? = nil
    @Published var isRunning = false
    private var generation = 0

    func start(_ code: String, timeout: Double = 5) {
        generation += 1
        let g = generation
        isRunning = true
        result = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let r = JSEngine.run(code)
            DispatchQueue.main.async {
                guard g == self.generation else { return }
                self.result = r
                self.isRunning = false
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            guard g == self.generation && self.isRunning else { return }
            self.generation += 1
            self.isRunning = false
            var t = JSRunResult()
            t.error = "Timed out - likely an infinite loop. Tap Re-run to try again."
            self.result = t
        }
    }

    func stop() {
        generation += 1
        isRunning = false
    }
}

func looksLikeHTML(_ s: String) -> Bool {
    let lower = s.lowercased()
    guard s.contains("<") && s.contains(">") else { return false }
    let tags = ["<html", "<div", "<button", "<h1", "<h2", "<h3", "<p", "<style", "<span", "<ul", "<ol", "<li", "<input", "<table", "<img", "<a ", "<form"]
    return tags.contains(where: { lower.contains($0) })
}

struct HTMLView: UIViewRepresentable {
    let html: String
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let v = WKWebView(frame: .zero, configuration: config)
        v.isOpaque = false
        v.backgroundColor = .clear
        v.scrollView.backgroundColor = .clear
        v.scrollView.bounces = true
        v.scrollView.isScrollEnabled = true
        return v
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        // Don't reload on every SwiftUI refresh — that would wipe
        // scroll position / input text in the interactive panel.
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            view.loadHTMLString(html, baseURL: nil)
        }
    }
    final class Coordinator {
        var lastHTML: String = ""
    }
}

// Fullscreen cover so panels/games can use the whole screen.
struct FullscreenHTMLView: View {
    let html: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            HTMLView(html: html)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Panel")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Done") { dismiss() }.bold()
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Shared output view
struct RunOutputView: View {
    let result: JSRunResult
    @State private var showFullscreen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !result.logs.isEmpty {
                Text("Console").font(.caption.bold()).foregroundStyle(.secondary)
                Text(result.logs.joined(separator: "\n"))
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if !result.result.isEmpty {
                if looksLikeHTML(result.result) {
                    HStack {
                        Text("App output (interactive)").font(.caption.bold()).foregroundStyle(.secondary)
                        Spacer()
                        Button("Fullscreen") { showFullscreen = true }
                            .font(.caption.bold())
                    }
                    HTMLView(html: result.result)
                        .frame(minHeight: 480)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .fullScreenCover(isPresented: $showFullscreen) {
                            FullscreenHTMLView(html: result.result)
                        }
                } else {
                    Text("Return value").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(result.result)
                        .font(.system(.callout, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.green.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            if let e = result.error, !e.isEmpty {
                Text("Error").font(.caption.bold()).foregroundStyle(.red)
                Text(e)
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.red.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

// MARK: - Module detail: tap a module -> see live output
// Split into small views so plain `swiftc` builds (BuildBox) type-check fast.
func runSummaryText(_ r: JSRunResult) -> String {
    let logsText: String = r.logs.joined(separator: " ")
    let parts: [String] = [logsText, r.result].filter { !$0.isEmpty }
    let joined: String = parts.joined(separator: " | ")
    if joined.isEmpty { return "(no output)" }
    return String(joined.prefix(120))
}

func runHadError(_ r: JSRunResult) -> Bool {
    guard let e = r.error else { return false }
    return !e.isEmpty
}

struct ModuleDetailView: View {
    @EnvironmentObject var store: ModuleStore
    let moduleID: UUID
    @StateObject private var runner = SafeRunner()

    private var module: Module? { store.modules.first(where: { $0.id == moduleID }) }

    var body: some View {
        ScrollView {
            detailStack
                .padding()
        }
        .navigationTitle("Module")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.black.ignoresSafeArea())
        .onAppear { autoRun() }
        .onChange(of: module?.code ?? "") { _, _ in autoRun() }
        .onChange(of: runner.result) { _, _ in recordCurrentRun() }
    }

    private func autoRun() {
        guard let m = module else { return }
        let trimmed = m.code.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { runner.start(m.code) }
    }

    private func recordCurrentRun() {
        guard let r = runner.result else { return }
        guard let m = module else { return }
        store.recordRun(moduleName: m.name, summary: runSummaryText(r), hadError: runHadError(r))
    }

    @ViewBuilder
    private var detailStack: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let m = module {
                detailHeader(m)
                detailButtons(m)
                detailStatus
            } else {
                Text("This module was deleted.").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func detailHeader(_ m: Module) -> some View {
        Text(m.name).font(.title2.bold())
        Text(m.code)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color(white: 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func detailButtons(_ m: Module) -> some View {
        HStack {
            Button("Re-run") { runner.start(m.code) }
                .buttonStyle(.borderedProminent)
                .disabled(runner.isRunning)
            if runner.isRunning {
                Button("Stop") { runner.stop() }
                    .buttonStyle(.bordered)
            }
            Button(m.isPinned ? "Unpin from Tabs" : "Pin to Tabs") {
                store.togglePin(m)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var detailStatus: some View {
        if runner.isRunning {
            Text("Running… (Stop frees the app if it loops)").foregroundStyle(.secondary)
        } else if let r = runner.result {
            RunOutputView(result: r)
        }
    }
}

// MARK: - Pinned panel tab: same as detail, auto-runs
struct ModulePanelView: View {
    @EnvironmentObject var store: ModuleStore
    let moduleID: UUID
    @StateObject private var runner = SafeRunner()

    private var module: Module? { store.modules.first(where: { $0.id == moduleID }) }

    var body: some View {
        ScrollView {
            panelStack
                .padding()
        }
        .navigationTitle(module?.name ?? "Panel")
        .background(Color.black.ignoresSafeArea())
        .onAppear { autoRun() }
        .onChange(of: module?.code ?? "") { _, _ in autoRun() }
        .onChange(of: runner.result) { _, _ in recordCurrentRun() }
    }

    private func autoRun() {
        guard let m = module else { return }
        let trimmed = m.code.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { runner.start(m.code) }
    }

    private func recordCurrentRun() {
        guard let r = runner.result else { return }
        guard let m = module else { return }
        store.recordRun(moduleName: m.name, summary: runSummaryText(r), hadError: runHadError(r))
    }

    @ViewBuilder
    private var panelStack: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let m = module {
                Text(m.name).font(.title2.bold())
                panelButtons(m)
                panelStatus
            } else {
                Text("Unpinned or deleted.").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func panelButtons(_ m: Module) -> some View {
        HStack {
            Button("Re-run") { runner.start(m.code) }
                .buttonStyle(.borderedProminent)
                .disabled(runner.isRunning)
            if runner.isRunning {
                Button("Stop") { runner.stop() }
                    .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var panelStatus: some View {
        if runner.isRunning {
            Text("Running…").foregroundStyle(.secondary)
        } else if let r = runner.result {
            RunOutputView(result: r)
        }
    }
}
