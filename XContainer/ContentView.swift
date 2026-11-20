import SwiftUI

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

// MARK: - Modules list
struct ModulesView: View {
    @EnvironmentObject var store: ModuleStore
    @Binding var selection: String
    @State private var lastRunText = ""
    @State private var lastRunError = ""

    var body: some View {
        VStack {
            if store.modules.isEmpty {
                Text("No modules yet. Create one from Home or tap + below.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
            List {
                ForEach(store.modules) { mod in
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.editingModuleID = nil
                    selection = "editor"
                } label: { Image(systemName: "plus") }
            }
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func quickRun(_ mod: Module) {
        let r = JSEngine.run(mod.code)
        lastRunError = ""
        lastRunText = ""
        if let e = r.error, !e.isEmpty {
            lastRunError = "\(mod.name): \(e)"
        } else {
            var out = mod.name + ":"
            if !r.logs.isEmpty { out += "\n" + r.logs.joined(separator: "\n") }
            if !r.result.isEmpty { out += "\n=> " + r.result }
            if r.logs.isEmpty && r.result.isEmpty { out += "\n(no output)" }
            lastRunText = out
        }
    }
}

// MARK: - Shared output view
struct RunOutputView: View {
    let result: JSRunResult

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
                Text("Return value").font(.caption.bold()).foregroundStyle(.secondary)
                Text(result.result)
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.green.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
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
struct ModuleDetailView: View {
    @EnvironmentObject var store: ModuleStore
    let moduleID: UUID
    @State private var result: JSRunResult? = nil

    private var module: Module? { store.modules.first(where: { $0.id == moduleID }) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let m = module {
                    Text(m.name).font(.title2.bold())
                    Text(m.code)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(white: 0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    HStack {
                        Button("Re-run") { result = JSEngine.run(m.code) }
                            .buttonStyle(.borderedProminent)
                        Button(m.isPinned ? "Unpin from Tabs" : "Pin to Tabs") {
                            store.togglePin(m)
                        }
                        .buttonStyle(.bordered)
                    }

                    if let r = result {
                        RunOutputView(result: r)
                    } else {
                        Text("Running…").foregroundStyle(.secondary)
                    }
                } else {
                    Text("This module was deleted.").foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Module")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            if let m = module {
                result = JSEngine.run(m.code)
            }
        }
        .onChange(of: module?.code ?? "") { _, _ in
            if let m = module {
                result = JSEngine.run(m.code)
            } else {
                result = nil
            }
        }
    }
}

// MARK: - Pinned panel tab: same as detail, auto-runs
struct ModulePanelView: View {
    @EnvironmentObject var store: ModuleStore
    let moduleID: UUID
    @State private var result: JSRunResult? = nil

    private var module: Module? { store.modules.first(where: { $0.id == moduleID }) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let m = module {
                    Text(m.name).font(.title2.bold())
                    Button("Re-run") { result = JSEngine.run(m.code) }
                        .buttonStyle(.borderedProminent)
                    if let r = result {
                        RunOutputView(result: r)
                    }
                } else {
                    Text("Unpinned or deleted.").foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(module?.name ?? "Panel")
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            if let m = module { result = JSEngine.run(m.code) }
        }
        .onChange(of: module?.code ?? "") { _, _ in
            if let m = module { result = JSEngine.run(m.code) }
        }
    }
}
