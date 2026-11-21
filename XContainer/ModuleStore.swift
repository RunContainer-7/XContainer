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
    // Which container (folder) this module lives in. Defaults to General
    // so modules saved by older versions still load.
    var folder: String = "General"

    enum CodingKeys: String, CodingKey {
        case id, name, code, createdAt, isPinned, folder
    }

    init(id: UUID = UUID(), name: String, code: String, createdAt: Date = Date(), isPinned: Bool = false, folder: String = "General") {
        self.id = id
        self.name = name
        self.code = code
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.folder = folder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        code = try c.decode(String.self, forKey: .code)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        let rawFolder = try c.decodeIfPresent(String.self, forKey: .folder) ?? "General"
        let trimmed = rawFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        folder = trimmed.isEmpty ? "General" : String(trimmed.prefix(40))
    }
}

// MARK: - Template: copy -> add as module -> use
struct Template: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var category: String
    var blurb: String
    var pinByDefault: Bool = false
    var code: String
}

// MARK: - Run history entry
struct RunEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var moduleName: String
    var at: Date = Date()
    var summary: String
    var hadError: Bool = false
}

// MARK: - Store (persisted to UserDefaults so modules survive restarts)
final class ModuleStore: ObservableObject {
    @Published var modules: [Module] = []
    // Set by Modules list when user taps Edit -> Editor picks it up.
    @Published var editingModuleID: UUID? = nil
    @Published var history: [RunEntry] = []

    private let storageKey = "xcontainer.modules.v1"
    private let seededKey = "xcontainer.seeded.v1"
    private let historyKey = "xcontainer.history.v1"

    init() {
        let hadSavedData = load()
        loadHistory()
        // Only seed examples on very first launch. An empty array is a valid
        // saved state (user hit Reset) and must stay empty across restarts.
        if !hadSavedData {
            modules = Self.examples
            save()
            UserDefaults.standard.set(true, forKey: seededKey)
        }
    }

    func recordRun(moduleName: String, summary: String, hadError: Bool) {
        // Auto-runs fire on every tab visit — skip exact repeats so real
        // runs are not pushed out of the 100-entry cap by duplicates.
        if let last = history.first, last.moduleName == moduleName, last.summary == summary, last.hadError == hadError { return }
        let e = RunEntry(moduleName: moduleName, summary: summary, hadError: hadError)
        history.insert(e, at: 0)
        if history.count > 100 { history = Array(history.prefix(100)) }
        saveHistory()
    }

    func clearHistory() {
        history = []
        saveHistory()
    }

    func useTemplate(_ t: Template) -> Module {
        // Templates land in the container matching their category (Games, Tools, …).
        add(name: t.name, code: t.code, pinned: t.pinByDefault, folder: t.category)
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([RunEntry].self, from: data) else { return }
        history = decoded
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    func module(withID id: UUID?) -> Module? {
        guard let id else { return nil }
        return modules.first(where: { $0.id == id })
    }

    // Never create two modules with the same visible name.
    func uniqueName(_ base: String) -> String {
        if !modules.contains(where: { $0.name == base }) { return base }
        var i = 2
        while modules.contains(where: { $0.name == base + " (\(i))" }) { i += 1 }
        return base + " (\(i))"
    }

    func add(name: String, code: String, pinned: Bool, folder: String = "General") -> Module {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = uniqueName(clean.isEmpty ? "Untitled module" : String(clean.prefix(80)))
        let safeCode = String(code.prefix(200_000))
        let f = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        if modules.count >= 500 { modules.removeFirst() }
        let m = Module(name: safeName, code: safeCode, isPinned: pinned, folder: f.isEmpty ? "General" : String(f.prefix(40)))
        modules.append(m)
        save()
        return m
    }

    func update(id: UUID, name: String, code: String, folder: String? = nil) {
        guard let i = modules.firstIndex(where: { $0.id == id }) else { return }
        modules[i].name = name
        modules[i].code = code
        if let f = folder {
            let t = f.trimmingCharacters(in: .whitespacesAndNewlines)
            modules[i].folder = t.isEmpty ? "General" : String(t.prefix(40))
        }
        save()
    }

    func delete(_ module: Module) {
        modules.removeAll(where: { $0.id == module.id })
        if editingModuleID == module.id { editingModuleID = nil }
        save()
    }

    func duplicate(_ module: Module) -> Module {
        if modules.count >= 500 { modules.removeFirst() }
        let copy = Module(name: uniqueName(module.name + " copy"), code: module.code, isPinned: false, folder: module.folder)
        modules.append(copy)
        save()
        return copy
    }

    func importModule(name: String, code: String) -> Module {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if modules.count >= 500 { modules.removeFirst() }
        let m = Module(name: uniqueName(clean.isEmpty ? "Imported module" : String(clean.prefix(80))), code: String(code.prefix(200_000)), isPinned: false)
        modules.append(m)
        save()
        return m
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

    func validate(code: String) -> String? {
        let t = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "Script is empty." }
        var o = 0
        var c = 0
        var inStr: Character? = nil
        var prev: Character? = nil
        for ch in t {
            if let q = inStr {
                if ch == q && prev != "\\" { inStr = nil }
            } else if ch == "\"" || ch == "'" || ch == "`" {
                inStr = ch
            } else if ch == "{" { o += 1 } else if ch == "}" { c += 1 }
            prev = ch
        }
        if inStr != nil { return "Unclosed string literal." }
        if o != c { return "Mismatched braces: \(o) { vs \(c) }." }
        return nil
    }

    func stats() -> (total: Int, pinned: Int, runs: Int, errors: Int) {
        let errs = history.filter { $0.hadError }.count
        return (modules.count, modules.filter { $0.isPinned }.count, history.count, errs)
    }

    func exportJSON() -> URL? {
        let arr = modules.map { ["name": $0.name, "code": $0.code, "pinned": $0.isPinned, "folder": $0.folder, "createdAt": $0.createdAt.timeIntervalSince1970] as [String: Any] }
        guard let data = try? JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xcontainer-modules.json")
        try? data.write(to: url)
        return url
    }

    func importJSON(_ data: Data) -> Int {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return 0 }
        var n = 0
        for d in arr.prefix(500) {
            guard let code = d["code"] as? String else { continue }
            let name = (d["name"] as? String ?? "Imported").trimmingCharacters(in: .whitespacesAndNewlines)
            let pinned = (d["pinned"] as? Bool) ?? false
            let folder = (d["folder"] as? String ?? "General").trimmingCharacters(in: .whitespacesAndNewlines)
            if modules.count >= 500 { modules.removeFirst() }
            modules.append(Module(name: uniqueName(name.isEmpty ? "Imported" : name), code: String(code.prefix(200_000)), isPinned: pinned, folder: folder.isEmpty ? "General" : folder))
            n += 1
        }
        if n > 0 { save() }
        return n
    }

    func reset() {
        modules = []
        editingModuleID = nil
        save()
    }

    // Adds back any missing examples WITHOUT touching user modules.
    // (It used to overwrite everything — that destroyed work.)
    func restoreExamples() {
        var names = Set(modules.map { $0.name })
        for ex in Self.examples where !names.contains(ex.name) {
            if modules.count >= 500 { modules.removeFirst() }
            modules.append(ex)
            names.insert(ex.name)
        }
        editingModuleID = nil
        save()
    }

    // Container (folder) names currently in use, sorted. Always includes General.
    func folders() -> [String] {
        var set = Set(modules.map { $0.folder })
        set.insert("General")
        return set.sorted()
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
                name: "Counter App",
                code: """
                // Interactive tab: return HTML and the panel renders it.
                // Tap the buttons in the panel — that's real <script> running in the tab.
                var count = parseInt(localStorage.getItem("counter") || "0");
                function render(n) {
                  return "<div style='font-family:-apple-system;padding:20px;text-align:center'>"
                    + "<h1>" + n + "</h1>"
                    + "<button onclick='window.webkit.messageHandlers.noop.postMessage(1)' style='font-size:20px;padding:10px 20px'>+1</button>"
                    + "<p style='color:#888'>Counter demo — full tap handling needs a bridge; edit me to style it!</p>"
                    + "</div>";
                }
                console.log("Counter loaded: " + count);
                localStorage.setItem("counter", String(count + 1));
                render(count);
                """,
                isPinned: true
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

    // MARK: - Template gallery: copy -> Add module -> Use
    static var templates: [Template] {
        [
            Template(name: "Notes", category: "Mini-apps", blurb: "Quick notes with localStorage.", pinByDefault: true, code: """
              // Notes — saved in localStorage, survives re-runs
              var notes = JSON.parse(localStorage.getItem("notes") || "[]");
              function add(t) { notes.push(t); localStorage.setItem("notes", JSON.stringify(notes)); }
              // Edit the line below, then Run:
              // add("Buy milk");
              console.log("Notes (" + notes.length + "):");
              notes.forEach(function(n, i) { console.log((i+1) + ". " + n); });
              notes.length ? notes.join("\n") : "No notes yet — uncomment add() and Run.";
              """),
            Template(name: "Todos", category: "Mini-apps", blurb: "Check off tasks.", code: """
              var todos = JSON.parse(localStorage.getItem("todos") || '["Show friend the app","Try a template"]');
              todos.forEach(function(t, i) { console.log((i+1) + ". [ ] " + t); });
              setTimeout(function() { console.log("Tip: edit the array, Re-run, it persists."); }, 0);
              "Done: " + todos.length + " todos listed";
              """),
            Template(name: "Timer", category: "Mini-apps", blurb: "Countdown demo.", code: """
              // Timer — counts down from N
              let start = 5;
              for (let i = start; i >= 0; i--) { console.log(i === 0 ? "GO!" : i + "..."); }
              "Finished countdown from " + start;
              """),
            Template(name: "Tap Counter UI", category: "Mini-apps", blurb: "Interactive HTML panel.", pinByDefault: true, code: """
              var count = parseInt(localStorage.getItem("tapCount") || "0");
              localStorage.setItem("tapCount", String(count + 1));
              console.log("Opened " + (count + 1) + " times");
              "<div style='font-family:-apple-system;padding:24px;text-align:center;background:#111;color:#fff;border-radius:16px'>"
                + "<h1>" + count + "</h1><p>Opens counted with localStorage.</p>"
                + "<p style='color:#888'>Re-run to +1. Edit me to add buttons!</p></div>";
              """),
            Template(name: "Dice Roller", category: "Games", blurb: "Roll d6 / d20.", code: """
              function roll(sides) { return Math.floor(Math.random() * sides) + 1; }
              let d6 = roll(6);
              let d20 = roll(20);
              console.log("d6: " + d6 + "  |  d20: " + d20);
              d20 === 20 ? "CRITICAL HIT! (d20 = 20)" : "You rolled d6=" + d6 + ", d20=" + d20;
              """),
            Template(name: "Guess Number", category: "Games", blurb: "Guess the 1-10 number.", code: """
              // Change guess, hit Re-run to play again
              let secret = Math.floor(Math.random() * 10) + 1;
              let guess = 7;
              console.log("You guessed " + guess + ", secret is " + secret);
              guess === secret ? "Correct! Amazing!" : (guess < secret ? "Too low — it was " + secret : "Too high — it was " + secret);
              """),
            Template(name: "Rock Paper Scissors", category: "Games", blurb: "Play vs computer.", code: """
              let you = "rock"; // change to rock | paper | scissors
              let picks = ["rock", "paper", "scissors"];
              let cpu = picks[Math.floor(Math.random() * 3)];
              console.log("You: " + you + "  CPU: " + cpu);
              if (you === cpu) "Draw!";
              else if ((you === "rock" && cpu === "scissors") || (you === "paper" && cpu === "rock") || (you === "scissors" && cpu === "paper")) "You win!";
              else "CPU wins!";
              """),
            Template(name: "Tap Dash Game", category: "Games", blurb: "Playable! Tap the glowing tile. Real UI.", pinByDefault: true, code: """
              // Tap Dash — REAL playable game. No edit needed.
              // Use template, open its panel tab, hit Start, tap glowing tiles.
              // Game logic lives inside the HTML below, so panel taps just work.
              console.log("Tap Dash ready — open panel to play");
              "<!DOCTYPE html><html><head><meta name='viewport' content='width=device-width,initial-scale=1,maximum-scale=1'>"
              + "<style>"
              + "body{font-family:-apple-system;background:#000;color:#fff;margin:0;padding:16px;text-align:center}"
              + ".card{background:#111;border-radius:20px;padding:18px;max-width:420px;margin:0 auto}"
              + ".row{display:flex;justify-content:space-between;align-items:center;margin:8px 0}"
              + ".score{font-size:28px;font-weight:800}.time{font-size:15px;color:#aaa}"
              + ".grid{display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px;margin-top:14px}"
              + ".tile{height:86px;border-radius:16px;background:#222;border:1px solid #333;font-size:30px;color:#fff}"
              + ".tile.lit{background:#fff;color:#000;transform:scale(1.04)}"
              + ".btn{background:#fff;color:#000;border:0;border-radius:12px;padding:12px 18px;font-weight:800;font-size:16px;width:100%;margin-top:12px}"
              + ".hint{color:#888;font-size:12px;margin-top:10px}"
              + "</style></head><body><div class='card'>"
              + "<div style='font-size:13px;letter-spacing:2px;color:#888'>TAP DASH</div>"
              + "<div class='row'><div class='score'>Score <span id='s'>0</span></div>"
              + "<div class='time'>Time <span id='t'>20</span>s<br>Best <span id='b'>0</span></div></div>"
              + "<div class='grid' id='g'></div>"
              + "<button class='btn' id='start' onclick='startGame()'>Start game</button>"
              + "<div class='hint'>Tap the white tile as fast as you can. 20 seconds.</div>"
              + "</div><script>"
              + "var score=0,time=20,timer=null,target=-1,playing=false;"
              + "var best=0;try{best=parseInt(localStorage.getItem('tapdash_best')||'0')||0;}catch(e){}"
              + "document.getElementById('b').innerText=best;"
              + "function build(){var g=document.getElementById('g');g.innerHTML='';for(var i=0;i<9;i++){var b=document.createElement('button');b.className='tile';b.id='tile'+i;b.innerText='•';b.onclick=(function(i){return function(){hit(i);};})(i);g.appendChild(b);}}"
              + "function pick(){var els=document.querySelectorAll('.tile');for(var i=0;i<els.length;i++)els[i].classList.remove('lit');target=Math.floor(Math.random()*9);document.getElementById('tile'+target).classList.add('lit');}"
              + "function hit(i){if(!playing)return;if(i===target){score++;document.getElementById('s').innerText=score;pick();}else{score=Math.max(0,score-1);document.getElementById('s').innerText=score;}}"
              + "function startGame(){score=0;time=20;playing=true;document.getElementById('s').innerText='0';document.getElementById('t').innerText='20';document.getElementById('start').innerText='Playing... tap white!';build();pick();clearInterval(timer);timer=setInterval(function(){time--;document.getElementById('t').innerText=time;if(time<=0){clearInterval(timer);playing=false;var nb=score>best?score:best;try{localStorage.setItem('tapdash_best',String(nb));}catch(e){}document.getElementById('b').innerText=nb;document.getElementById('start').innerText='Play again (scored '+score+')';}},1000);}"
              + "build();"
              + "</script></body></html>";
              """),
            Template(name: "Calculator+", category: "Tools", blurb: "Better calculator.", code: """
              function calc(a, op, b) {
                if (op === "+") return a + b;
                if (op === "-") return a - b;
                if (op === "*") return a * b;
                if (op === "/") return b === 0 ? "Error: divide by zero" : a / b;
                return "Unknown op " + op;
              }
              console.log("12 * 30 = " + calc(12, "*", 30));
              console.log("100 / 4 = " + calc(100, "/", 4));
              calc(7, "*", 6);
              """),
            Template(name: "JSON Formatter", category: "Tools", blurb: "Pretty-print JSON.", code: """
              let raw = '{"name":"XContainer","tabs":5,"pinned":true}';
              try {
                let obj = JSON.parse(raw);
                console.log(JSON.stringify(obj, null, 2));
                "Keys: " + Object.keys(obj).join(", ");
              } catch(e) { "Invalid JSON: " + e; }
              """),
            Template(name: "Base64 Tool", category: "Tools", blurb: "Encode text (pure JS).", code: """
              // Tiny base64 encode (no network needed)
              function b64(s) {
                let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
                let out = "", i = 0;
                while (i < s.length) {
                  let a = s.charCodeAt(i++), b = s.charCodeAt(i++), c = s.charCodeAt(i++);
                  let x = (a << 16) | ((isNaN(b) ? 0 : b) << 8) | (isNaN(c) ? 0 : c);
                  out += chars[(x >> 18) & 63] + chars[(x >> 12) & 63] + (isNaN(b) ? "=" : chars[(x >> 6) & 63]) + (isNaN(c) ? "=" : chars[x & 63]);
                }
                return out;
              }
              let msg = "hello friend!";
              console.log(msg + " -> " + b64(msg));
              b64(msg);
              """),
            Template(name: "Password Generator", category: "Tools", blurb: "Random password.", code: """
              let len = 14;
              let abc = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#";
              let pw = "";
              for (let i = 0; i < len; i++) pw += abc[Math.floor(Math.random() * abc.length)];
              console.log("New password: " + pw);
              pw;
              """),
            Template(name: "Dark Card UI", category: "HTML UI", blurb: "Starter panel layout.", pinByDefault: true, code: """
              console.log("Rendering card UI below");
              "<div style='font-family:-apple-system;background:#000;color:#fff;padding:16px'>"
              + "<div style='background:#161616;border-radius:16px;padding:20px'>"
              + "<h2 style='margin:0'>Hello friend!</h2><p style='color:#aaa'>Copy this template, edit the text, Re-run.</p>"
              + "<button style='background:#fff;color:#000;border:0;border-radius:10px;padding:10px 16px;font-weight:700'>Get started</button>"
              + "</div></div>";
              """),
            Template(name: "Form UI", category: "HTML UI", blurb: "Input + list starter.", pinByDefault: true, code: """
              console.log("Form UI rendered");
              "<div style='font-family:-apple-system;padding:16px;background:#000;color:#fff'>"
              + "<h3>Feedback</h3><input placeholder='Your name' style='width:100%;padding:10px;border-radius:10px;border:1px solid #333;background:#111;color:#fff'/>"
              + "<p style='color:#888'>Static demo — wire JS to read inputs next.</p></div>";
              """),
            Template(name: "Expense Tracker", category: "Mini-apps", blurb: "Track spending, totals persist.", pinByDefault: true, code: """
              console.log("Expense Tracker ready — open panel");
              `<div style='font-family:-apple-system;background:#000;color:#fff;padding:16px'><div style='background:#111;border-radius:16px;padding:16px;max-width:420px;margin:0 auto'><h2 style='margin:0'>Expenses</h2><p style='color:#888' id='total'>Total: $0</p><input id='nm' placeholder='Coffee' style='width:100%;padding:10px;border-radius:10px;border:1px solid #333;background:#000;color:#fff;margin-bottom:8px'/><input id='am' type='number' placeholder='4.50' style='width:100%;padding:10px;border-radius:10px;border:1px solid #333;background:#000;color:#fff;margin-bottom:8px'/><button onclick='addExp()' style='width:100%;padding:12px;border-radius:12px;border:0;background:#fff;font-weight:800'>Add</button><div id='list' style='margin-top:12px'></div><button onclick='clearExp()' style='background:none;border:0;color:#666;margin-top:8px'>Clear all</button></div></div><script>function getExp(){try{return JSON.parse(localStorage.getItem('exp')||'[]')}catch(e){return[]}}function saveExp(x){localStorage.setItem('exp',JSON.stringify(x))}function draw(){var x=getExp();var t=0;var h='';for(var i=0;i<x.length;i++){t+=x[i].a;h+='<div>'+x[i].n+' — $'+x[i].a.toFixed(2)+'</div>'}document.getElementById('list').innerHTML=h||'<p style=color:#666>No expenses yet</p>';document.getElementById('total').innerText='Total: $'+t.toFixed(2)}function addExp(){var n=document.getElementById('nm').value||'Item';var a=parseFloat(document.getElementById('am').value||'0');var x=getExp();x.push({n:n,a:a});saveExp(x);draw();document.getElementById('nm').value='';document.getElementById('am').value=''}function clearExp(){saveExp([]);draw()}draw()</script>`;
              """),
            Template(name: "Habit Tracker", category: "Mini-apps", blurb: "Daily check-ins with streaks.", pinByDefault: true, code: """
              console.log("Habits ready — open panel");
              `<div style='font-family:-apple-system;background:#000;color:#fff;padding:16px;text-align:center'><div style='background:#111;border-radius:16px;padding:16px;max-width:420px;margin:0 auto'><h2>Today</h2><div id='h'></div><p style='color:#888' id='st'></p></div></div><script>var H=['Read 10 min','Exercise','No soda'];function g(){try{return JSON.parse(localStorage.getItem('hab')||'{}')}catch(e){return{}}}function s(x){localStorage.setItem('hab',JSON.stringify(x))}function d(){var x=g();var t=new Date().toDateString();var h='';for(var i=0;i<H.length;i++){var k=H[i]+'|'+t;var on=!!x[k];h+='<button onclick="tg('+i+')" style="display:block;width:100%;margin:6px 0;padding:12px;border-radius:12px;border:1px solid #333;background:'+(on?'#fff':'#222')+';color:'+(on?'#000':'#fff')+'">'+(on?'✓ ':'○ ')+H[i]+'</button>'}document.getElementById('h').innerHTML=h;var n=0;for(var k in x){if(x[k]&&k.indexOf(t)>-1)n++}document.getElementById('st').innerText=n+' / '+H.length+' done today'}function tg(i){var x=g();var k=H[i]+'|'+new Date().toDateString();x[k]=!x[k];s(x);d()}d()</script>`;
              """),
            Template(name: "Pomodoro", category: "Mini-apps", blurb: "25-min focus timer panel.", pinByDefault: true, code: """
              console.log("Pomodoro ready — open panel");
              `<div style='font-family:-apple-system;background:#000;color:#fff;padding:24px;text-align:center'><div style='background:#111;border-radius:20px;padding:24px;max-width:360px;margin:0 auto'><div style='font-size:64px;font-weight:800' id='clock'>25:00</div><p style='color:#888' id='ph'>Ready to focus</p><button onclick='go(25)' style='padding:12px 18px;border-radius:12px;border:0;background:#fff;font-weight:800'>Focus 25</button> <button onclick='go(5)' style='padding:12px 18px;border-radius:12px;border:1px solid #444;background:#222;color:#fff;font-weight:800'>Break 5</button><br><button onclick='stop()' style='background:none;border:0;color:#666;margin-top:10px'>Stop</button></div></div><script>var iv=null;function go(m){stop();var s=m*60;tick(s);iv=setInterval(function(){s--;if(s<=0){stop();document.getElementById('ph').innerText='Done! 🎉';return}tick(s)},1000)}function tick(s){var m=Math.floor(s/60),r=s%60;document.getElementById('clock').innerText=(m<10?'0':'')+m+':'+(r<10?'0':'')+r}function stop(){if(iv)clearInterval(iv);iv=null}</script>`;
              """),
            Template(name: "Markdown Notes", category: "Tools", blurb: "Write markdown, get HTML.", code: """
              let md = "# Hello\n\n- **bold** and *italic*\n- `code` snippet\n\n> quote here\n\nEdit md, Re-run.";
              function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;"); }
              let h = esc(md);
              h = h.replace(/^# (.*)$/gm, "<h1>$1</h1>").replace(/^## (.*)$/gm, "<h2>$1</h2>");
              var bpts = h.split("**"); if (bpts.length >= 3) { var nh = bpts[0]; for (var bi = 1; bi < bpts.length; bi++) { nh += (bi % 2 === 1 ? "<b>" : "</b>") + bpts[bi]; } h = nh; } h = h.replace(/`(.+?)`/g, "<code>$1</code>");
              h = h.replace(/^&gt; (.*)$/gm, "<blockquote>$1</blockquote>").replace(/^- (.*)$/gm, "<li>$1</li>");
              console.log("Rendered " + md.length + " chars");
              "<div style='font-family:-apple-system;background:#111;color:#fff;padding:20px;border-radius:16px'>" + h + "</div>";
              """),
            Template(name: "Unit Converter", category: "Tools", blurb: "km/mi, kg/lb, C/F.", code: """
              function conv(v, kind) {
                if (kind === "km-mi") return v + " km = " + (v * 0.621371).toFixed(2) + " mi";
                if (kind === "mi-km") return v + " mi = " + (v * 1.60934).toFixed(2) + " km";
                if (kind === "kg-lb") return v + " kg = " + (v * 2.20462).toFixed(2) + " lb";
                if (kind === "c-f") return v + "°C = " + (v * 9/5 + 32).toFixed(1) + "°F";
                if (kind === "f-c") return v + "°F = " + ((v - 32) * 5/9).toFixed(1) + "°C";
                return "pick kind: km-mi | mi-km | kg-lb | c-f | f-c";
              }
              console.log(conv(10, "km-mi"));
              console.log(conv(72, "c-f"));
              conv(5, "kg-lb");
              """),
            Template(name: "Weather Now", category: "Tools", blurb: "Live temp via fetch, no key.", code: """
              // New York City by default — change lat/lon below.
              let lat = 40.71, lon = -74.0;
              let url = "https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon + "&current=temperature_2m,weather_code";
              let r = fetch(url);
              try {
                let j = JSON.parse(r.text);
                let t = j.current.temperature_2m;
                console.log("Temp: " + t + "°C");
                "New York: " + t + "°C right now (live fetch)";
              } catch(e) { console.log(r.text.slice(0, 120)); "Weather fetch failed: " + e; }
              """),
            Template(name: "Snake Game", category: "Games", blurb: "Playable snake, tap arrows.", pinByDefault: true, code: """
              console.log("Snake ready — open panel, Fullscreen to play");
              `<meta name='viewport' content='width=device-width,initial-scale=1'><style>body{font-family:-apple-system;background:#000;color:#fff;margin:0;padding:16px;text-align:center}.b{background:#111;border-radius:16px;padding:14px;max-width:400px;margin:0 auto}canvas{background:#000;border-radius:12px}.r{display:grid;grid-template-columns:repeat(3,64px);gap:8px;justify-content:center;margin-top:10px}button.k{height:56px;border-radius:12px;border:1px solid #444;background:#222;color:#fff;font-size:22px}</style><div class='b'><div>Score <b id='sc'>0</b> Best <b id='bs'>0</b></div><canvas id='c' width='300' height='300'></canvas><div class='r'><span></span><button class='k' onclick='mv(0,-1)'>▲</button><span></span><button class='k' onclick='mv(-1,0)'>◀</button><button class='k' onclick='mv(0,1)'>▼</button><button class='k' onclick='mv(1,0)'>▶</button></div><button onclick='start()' style='margin-top:10px;padding:12px 20px;border-radius:12px;border:0;background:#fff;font-weight:800;width:100%'>Start / Restart</button></div><script>var cv=document.getElementById('c'),x=cv.getContext('2d');var sn,dx,dy,fd,sc,iv,bs=0;try{bs=parseInt(localStorage.getItem('sn_best')||'0')||0}catch(e){}document.getElementById('bs').innerText=bs;function start(){sn=[{x:7,y:7},{x:6,y:7}];dx=1;dy=0;sc=0;document.getElementById('sc').innerText='0';place();clearInterval(iv);iv=setInterval(step,140)}function place(){fd={x:Math.floor(Math.random()*15),y:Math.floor(Math.random()*15)}}function mv(a,b){if(a===-dx&&b===-dy)return;dx=a;dy=b}function step(){var h={x:sn[0].x+dx,y:sn[0].y+dy};if(h.x<0||h.y<0||h.x>=15||h.y>=15){die();return}for(var i=0;i<sn.length;i++){if(sn[i].x===h.x&&sn[i].y===h.y){die();return}}sn.unshift(h);if(h.x===fd.x&&h.y===fd.y){sc++;document.getElementById('sc').innerText=sc;place()}else sn.pop();draw()}function draw(){x.fillStyle='#000';x.fillRect(0,0,300,300);x.fillStyle='#f33';x.fillRect(fd.x*20,fd.y*20,18,18);x.fillStyle='#fff';for(var i=0;i<sn.length;i++)x.fillRect(sn[i].x*20,sn[i].y*20,18,18)}function die(){clearInterval(iv);if(sc>bs){bs=sc;try{localStorage.setItem('sn_best',String(bs))}catch(e){}document.getElementById('bs').innerText=bs}alert2('Game over! Score '+sc)}function alert2(m){var d=document.createElement('div');d.innerText=m;d.style.cssText='background:#fff;color:#000;border-radius:10px;padding:10px;margin-top:10px;font-weight:700';document.querySelector('.b').appendChild(d);setTimeout(function(){d.remove()},2000)}draw()</script>`;
              """),
            Template(name: "Memory Match", category: "Games", blurb: "Flip pairs, timed.", pinByDefault: true, code: """
              console.log("Memory ready — open panel to play");
              `<meta name='viewport' content='width=device-width,initial-scale=1'><style>body{font-family:-apple-system;background:#000;color:#fff;margin:0;padding:16px;text-align:center}.b{background:#111;border-radius:16px;padding:14px;max-width:400px;margin:0 auto}.g{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin-top:12px}.t{height:64px;border-radius:12px;border:1px solid #444;background:#222;font-size:26px;color:#fff}</style><div class='b'><div>Moves <b id='m'>0</b> • Pairs <b id='p'>0</b>/8</div><div class='g' id='g'></div><button onclick='build()' style='margin-top:12px;padding:12px;width:100%;border-radius:12px;border:0;background:#fff;font-weight:800'>Shuffle / Restart</button></div><script>var em=['🍎','🚀','🐶','⚽','🎧','🌙','🍕','🐠'];var deck=[],first=-1,moves=0,pairs=0,lock=false;function build(){deck=em.concat(em).sort(function(){return Math.random()-0.5});moves=0;pairs=0;first=-1;lock=false;document.getElementById('m').innerText='0';document.getElementById('p').innerText='0/8';var g=document.getElementById('g');g.innerHTML='';for(var i=0;i<16;i++){var b=document.createElement('button');b.className='t';b.innerText='?';b.id='t'+i;b.onclick=(function(i){return function(){flip(i)}})(i);g.appendChild(b)}}function flip(i){if(lock)return;var el=document.getElementById('t'+i);if(el.innerText!=='?')return;el.innerText=deck[i];if(first===-1){first=i;return}if(first===i)return;moves++;document.getElementById('m').innerText=moves;if(deck[first]===deck[i]){pairs++;document.getElementById('p').innerText=pairs+'/8';first=-1;if(pairs===8)setTimeout(function(){alert('You win in '+moves+' moves!')},300)}else{lock=true;var a=first,b2=i;setTimeout(function(){document.getElementById('t'+a).innerText='?';document.getElementById('t'+b2).innerText='?';first=-1;lock=false},700);first=-2}}build()</script>`;
              """),
            Template(name: "API Tester", category: "Tools", blurb: "GET any URL, inspect body.", pinByDefault: true, code: """
              console.log("API Tester ready — open panel");
              `<meta name='viewport' content='width=device-width,initial-scale=1'><style>body{font-family:-apple-system;background:#000;color:#fff;margin:0;padding:16px}.b{background:#111;border-radius:16px;padding:14px;max-width:480px;margin:0 auto}input{width:100%;box-sizing:border-box;padding:10px;border-radius:10px;border:1px solid #333;background:#000;color:#fff;margin:8px 0}button.go{width:100%;padding:12px;border-radius:12px;border:0;background:#fff;font-weight:800}pre{background:#000;border-radius:10px;padding:10px;overflow:auto;max-height:300px;font-size:12px}#st{color:#888;font-size:13px}</style><div class='b'><b>API Tester</b><div id='st'>Paste a URL, tap Send</div><input id='u' value='https://api.open-meteo.com/v1/forecast?latitude=40.71&longitude=-74&current=temperature_2m'/><button class='go' onclick='send()'>Send GET</button><pre id='o'>—</pre></div><script>function send(){var u=document.getElementById('u').value;var o=document.getElementById('o');var st=document.getElementById('st');o.innerText='Loading…';var t0=Date.now();fetch(u).then(function(r){st.innerText='HTTP '+r.status+' • '+(Date.now()-t0)+'ms';return r.text()}).then(function(t){try{o.innerText=JSON.stringify(JSON.parse(t),null,2).slice(0,4000)}catch(e){o.innerText=t.slice(0,4000)}}).catch(function(e){st.innerText='Error';o.innerText=String(e).slice(0,500)})}</script>`;
              """),
            Template(name: "JSON Inspector", category: "Tools", blurb: "Validate + pretty JSON.", code: """
              let raw = '{"app":"XContainer","runs":12,"ok":true,"tags":["a","b"]}';
              try {
                let obj = JSON.parse(raw);
                let keys = Object.keys(obj);
                console.log("Valid JSON, " + keys.length + " top-level keys: " + keys.join(", "));
                console.log(JSON.stringify(obj, null, 2).slice(0, 400));
                "Keys: " + keys.join(", ") + " — edit raw, Re-run.";
              } catch(e) { "Invalid JSON: " + e; }
              """)
        ]
    }
}
