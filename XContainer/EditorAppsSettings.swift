import SwiftUI

// MARK: - Editor: type code -> Run -> Save (+ optional Pin as tab)
struct EditorView: View {
    @EnvironmentObject var store: ModuleStore
    @Binding var selection: String

    @State private var name = ""
    @State private var code = "// write your script here\nconsole.log(\"hello from XContainer\");\n1 + 2;"
    @State private var pinAsPanel = true
    @StateObject private var runner = SafeRunner()
    @State private var loadedID: UUID? = nil
    @State private var fontSize: Double = 15

    private var isEditing: Bool { loadedID != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(isEditing ? "Edit Module" : "Script Editor")
                    .font(.title2.bold())

                Text("Module name").font(.caption).foregroundStyle(.secondary)
                TextField("My first module", text: $name)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text("Script (JavaScript)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(code.components(separatedBy: "\n").count) lines").font(.caption).foregroundStyle(.secondary)
                    Button("A-") { fontSize = max(11, fontSize - 1) }.font(.caption)
                    Button("A+") { fontSize = min(22, fontSize + 1) }.font(.caption)
                    Button("Clear") { code = "" }.font(.caption)
                }
                TextEditor(text: $code)
                    .font(.system(size: fontSize, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 220)
                    .padding(8)
                    .background(Color(white: 0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        snippetButton("log", insert: "console.log(\"hello\");\n")
                        snippetButton("loop", insert: "for (let i = 0; i < 5; i++) { console.log(i); }\n")
                        snippetButton("func", insert: "function name() {\n  return 1;\n}\n")
                        snippetButton("html", insert: "\"<div style='font-family:-apple-system;padding:20px;text-align:center'><h1>Hi</h1></div>\";\n")
                        snippetButton("store", insert: "localStorage.setItem(\"key\", \"value\");\n")
                    }
                }

                Toggle("Pin as tab panel on Save", isOn: $pinAsPanel)
                    .font(.caption)

                HStack {
                    Button(runner.isRunning ? "Running…" : "Run") {
                        runner.start(code)
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(runner.isRunning)
                    if runner.isRunning {
                        Button("Stop") { runner.stop() }
                            .buttonStyle(.bordered)
                    }
                    Button("Save") {
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
                        runner.stop()
                    }
                    .font(.caption)
                }

                if let r = runner.result {
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
        runner.stop()
    }

    private func snippetButton(_ label: String, insert: String) -> some View {
        Button(label) { code += insert }
            .font(.caption)
            .buttonStyle(.bordered)
    }

    private func save() {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        // Empty code is allowed but confirm-ish: save a placeholder comment
        // so detail/panel never shows a blank confusing screen.
        let finalCode = code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "// empty module\nconsole.log(\"empty module\");" : code
        if let id = loadedID, store.module(withID: id) != nil {
            store.update(id: id, name: clean, code: finalCode)
            if let m = store.module(withID: id) { store.setPinned(m, pinned: pinAsPanel) }
        } else {
            let m = store.add(name: clean, code: finalCode, pinned: pinAsPanel)
            loadedID = m.id
            store.editingModuleID = m.id
        }
        store.editingModuleID = nil
        loadedID = nil
        name = ""
        code = "// write your script here\nconsole.log(\"hello from XContainer\");\n1 + 2;"
        runner.stop()
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
        .scrollContentBackground(.hidden)
        .background(Color.black)
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
                if store.history.isEmpty {
                    Text("No runs yet. Run anything and it shows up here.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(store.history.prefix(20)) { h in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(h.moduleName).font(.caption.bold())
                                Spacer()
                                Text(h.at, style: .time).font(.caption2).foregroundStyle(.secondary)
                            }
                            Text(h.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            if h.hadError { Text("error").font(.caption2).foregroundStyle(.red) }
                        }
                        .padding(.vertical, 2)
                    }
                    Button("Clear history", role: .destructive) { store.clearHistory() }
                }
            } header: { Text("Run history") }

            Section {
                Text("Modules are stored on-device (UserDefaults). Code runs locally with Apple's JavaScriptCore — no server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: { Text("Storage & Engine") }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Settings")
    }
}
