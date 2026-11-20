import Foundation
import SwiftUI
import Combine

// MARK: - Model
// A user script. When isPinned == true it also appears as its own tab/panel.
struct Module: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var code: String
    var createdAt: Date = Date()
    var isPinned: Bool = false
}

// MARK: - Store (persisted to UserDefaults so modules survive restarts)
final class ModuleStore: ObservableObject {
    @Published var modules: [Module] = []
    // Set by Modules list when user taps Edit -> Editor picks it up.
    @Published var editingModuleID: UUID? = nil

    private let storageKey = "xcontainer.modules.v1"
    private let seededKey = "xcontainer.seeded.v1"

    init() {
        let hadSavedData = load()
        // Only seed examples on very first launch. An empty array is a valid
        // saved state (user hit Reset) and must stay empty across restarts.
        if !hadSavedData {
            modules = Self.examples
            save()
            UserDefaults.standard.set(true, forKey: seededKey)
        }
    }

    func module(withID id: UUID?) -> Module? {
        guard let id else { return nil }
        return modules.first(where: { $0.id == id })
    }

    func add(name: String, code: String, pinned: Bool) -> Module {
        let m = Module(name: name, code: code, isPinned: pinned)
        modules.append(m)
        save()
        return m
    }

    func update(id: UUID, name: String, code: String) {
        guard let i = modules.firstIndex(where: { $0.id == id }) else { return }
        modules[i].name = name
        modules[i].code = code
        save()
    }

    func delete(_ module: Module) {
        modules.removeAll(where: { $0.id == module.id })
        if editingModuleID == module.id { editingModuleID = nil }
        save()
    }

    func togglePin(_ module: Module) {
        guard let i = modules.firstIndex(where: { $0.id == module.id }) else { return }
        modules[i].isPinned.toggle()
        save()
    }

    func setPinned(_ module: Module, pinned: Bool) {
        guard let i = modules.firstIndex(where: { $0.id == module.id }) else { return }
        modules[i].isPinned = pinned
        save()
    }

    func reset() {
        modules = []
        editingModuleID = nil
        save()
    }

    func restoreExamples() {
        modules = Self.examples
        editingModuleID = nil
        save()
    }

    // MARK: Persistence
    @discardableResult
    private func load() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return false }
        if let decoded = try? JSONDecoder().decode([Module].self, from: data) {
            modules = decoded
            return true
        }
        return false
    }

    private func save() {
        if let data = try? JSONEncoder().encode(modules) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    // MARK: - Starter modules so the app isn't empty
    static var examples: [Module] {
        [
            Module(
                name: "Calculator",
                code: """
                // Calculator — edit the numbers, hit Run
                let a = 12;
                let b = 30;
                console.log(a + " + " + b + " = " + (a + b));
                console.log(a + " * " + b + " = " + (a * b));
                (a + b) * 2;
                """,
                isPinned: true
            ),
            Module(
                name: "Mini Assistant",
                code: """
                // Hardcoded assistant — change the question below
                function answer(q) {
                  q = q.toLowerCase();
                  if (q.includes("hello") || q.includes("hi")) return "Hi! I'm your mini assistant inside XContainer.";
                  if (q.includes("who")) return "I'm a demo assistant running on JavaScriptCore.";
                  if (q.includes("calc")) return "Try the Calculator module for math!";
                  return "I only know a few hardcoded replies. Edit me to teach me more!";
                }
                let question = "hello, who are you?";
                console.log("You: " + question);
                answer(question);
                """
            ),
            Module(
                name: "Dice Game",
                code: """
                // Tiny game — tap Re-run to roll again
                let roll = Math.floor(Math.random() * 6) + 1;
                console.log("You rolled: " + roll);
                if (roll === 6) "JACKPOT! You rolled a 6!";
                else if (roll >= 4) "Nice! You got " + roll;
                else "You got " + roll + " — try again!";
                """
            )
        ]
    }
}
