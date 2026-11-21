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
        add(name: t.name, code: t.code, pinned: t.pinByDefault)
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

    func duplicate(_ module: Module) -> Module {
        let copy = Module(name: module.name + " copy", code: module.code, isPinned: false)
        modules.append(copy)
        save()
        return copy
    }

    func importModule(name: String, code: String) -> Module {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = Module(name: clean.isEmpty ? "Imported module" : clean, code: code, isPinned: false)
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
              """)
        ]
    }
}
