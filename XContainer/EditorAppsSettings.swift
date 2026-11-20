import SwiftUI

// MARK: - Editor: type code -> Run -> Save (+ optional Pin as tab)
struct EditorView: View {
    @EnvironmentObject var store: ModuleStore
    @Binding var selection: String

    @State private var name = ""
    @State private var code = "// write your script here\nconsole.log(\"hello from XContainer\");\n1 + 2;"
    @State private var pinAsPanel = true
    @State private var result: JSRunResult? = nil
    @State private var loadedID: UUID? = nil

    private var isEditing: Bool { loadedID != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(isEditing ? "Edit Module" : "Script Editor")
                    .font(.title2.bold())

                Text("Module name").font(.caption).foregroundStyle(.secondary)
                TextField("My first module", text: $name)
                    .textFieldStyle(.roundedBorder)

                Text("Script (JavaScript)").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $code)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 220)
                    .padding(8)
                    .background(Color(white: 0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                Toggle("Pin as tab panel on Save", isOn: $pinAsPanel)
                    .font(.caption)

                HStack {
                    Button("Run") {
                        result = JSEngine.run(code)
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)

                    Button(isEditing ? "Save" : "Save") {
                        save()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if isEditing {
                    Button("New blank script") {
                        store.editingModuleID = nil
                        loadedID = nil
                        name = ""
                        code = "// write your script here"
                        result = nil
                    }
                    .font(.caption)
                }

                if let r = result {
                    RunOutputView(result: r)
                }
            }
            .padding()
        }
        .navigationTitle("Editor")
        .background(Color.black.ignoresSafeArea())
        .onAppear(perform: loadIfNeeded)
        .onChange(of: store.editingModuleID) { _, _ in loadIfNeeded() }
    }

    private func loadIfNeeded() {
        let target = store.editingModuleID
        guard target != loadedID else { return }
        loadedID = target
        if let m = store.module(withID: target) {
            name = m.name
            code = m.code
            pinAsPanel = m.isPinned
        } else {
            // Fresh script (Home -> Create, Modules -> +, or after Save).
            // Always reset so we never show the previous module's text.
            name = ""
            code = "// write your script here\nconsole.log(\"hello from XContainer\");\n1 + 2;"
            pinAsPanel = true
        }
        result = nil
    }

    private func save() {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        if let id = loadedID, store.module(withID: id) != nil {
            store.update(id: id, name: clean, code: code)
            if pinAsPanel {
                if let m = store.module(withID: id) { store.setPinned(m, pinned: true) }
            }
        } else {
            let m = store.add(name: clean, code: code, pinned: pinAsPanel)
            loadedID = m.id
            store.editingModuleID = m.id
        }
        store.editingModuleID = nil
        loadedID = nil
        name = ""
        result = nil
        selection = "modules"
    }
}

// MARK: - Recommended apps (same idea as the prototype)
struct AppsView: View {
    let apps: [(String, String)] = [
        ("AltStore", "An alternative app store that lets you sideload apps onto your iOS device using your Apple ID."),
        ("StikDebug", "A debugging-focused tool that helps inspect and interact with apps and system behavior."),
        ("LocalDevVPN", "A local development VPN tool for testing and development."),
        ("UTM", "A virtual machine app that lets you run other operating systems on your device."),
        ("LiveContainer", "A container-style app that lets you run iOS apps without actually installing them!"),
        ("XContainer", "Your own scripting container: create modules, run custom code, pin them as panels.")
    ]

    var body: some View {
        List(apps, id: \.0) { app in
            VStack(alignment: .leading, spacing: 4) {
                Text(app.0).font(.headline)
                Text(app.1).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .listStyle(.plain)
        .navigationTitle("Recommended Apps")
        .background(Color.black.ignoresSafeArea())
    }
}

// MARK: - Settings
struct SettingsView: View {
    @EnvironmentObject var store: ModuleStore

    var body: some View {
        List {
            Section {
                Text("XContainer is a Swift scripting container. Write JavaScript modules in the Editor, run them on JavaScriptCore, save them, and pin them as their own tabs/panels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: { Text("About XContainer") }

            Section {
                Button("Restore example modules") { store.restoreExamples() }
                Button("Reset all modules", role: .destructive) { store.reset() }
            } header: { Text("Modules") }

            Section {
                Text("Modules are stored on-device (UserDefaults). Code runs locally with Apple's JavaScriptCore — no server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: { Text("Storage & Engine") }
        }
        .navigationTitle("Settings")
    }
}
