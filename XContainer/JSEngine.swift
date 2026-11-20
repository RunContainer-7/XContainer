import Foundation
import JavaScriptCore

// Result of running one script.
struct JSRunResult {
    var logs: [String] = []
    var result: String = ""
    var error: String? = nil

    var hasOutput: Bool { !logs.isEmpty || !result.isEmpty || error != nil }
}

// Real JS engine on iOS. Supports console.log(...) / log(...) / print(...)
// and returns the completion value of the script.
private final class LogBox {
    var lines: [String] = []
}

final class JSEngine {
    static func run(_ code: String) -> JSRunResult {
        var res = JSRunResult()
        // Empty editor should not produce a confusing "undefined" result.
        if code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            res.result = "(no output)"
            return res
        }
        let box = LogBox()
        var handlerError: String? = nil

        guard let ctx = JSContext() else {
            res.error = "Could not create JS engine"
            return res
        }

        // console.log("a", 1) -> one line "a 1"
        let appendLog: @convention(block) (String) -> Void = { msg in
            box.lines.append(msg)
        }
        ctx.setObject(appendLog, forKeyedSubscript: "iosLog" as NSString)

        // localStorage polyfill backed by UserDefaults (shared across runs).
        // Kept tiny on purpose: string keys/values only.
        let storageKey = "xcontainer.jsStorage.v1"
        let iosGet: @convention(block) (String) -> String = { k in
            let d = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] ?? [:]
            return d[k] ?? ""
        }
        let iosHas: @convention(block) (String) -> Bool = { k in
            let d = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] ?? [:]
            return d[k] != nil
        }
        let iosSet: @convention(block) (String, String) -> Void = { k, v in
            var d = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] ?? [:]
            d[k] = v
            UserDefaults.standard.set(d, forKey: storageKey)
        }
        let iosRemove: @convention(block) (String) -> Void = { k in
            var d = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] ?? [:]
            d.removeValue(forKey: k)
            UserDefaults.standard.set(d, forKey: storageKey)
        }
        ctx.setObject(iosGet, forKeyedSubscript: "iosGet" as NSString)
        ctx.setObject(iosHas, forKeyedSubscript: "iosHas" as NSString)
        ctx.setObject(iosSet, forKeyedSubscript: "iosSet" as NSString)
        ctx.setObject(iosRemove, forKeyedSubscript: "iosRemove" as NSString)
        ctx.evaluateScript("""
        function __fmt(v) {
          if (v === undefined) return "undefined";
          if (v === null) return "null";
          if (typeof v === "object") { try { return JSON.stringify(v); } catch(e) { return String(v); } }
          return String(v);
        }
        function log() { iosLog(Array.from(arguments).map(__fmt).join(" ")); }
        var console = { log: log };
        function print() { log.apply(null, arguments); }
        var localStorage = {
          getItem: function(k) { k = String(k); return iosHas(k) ? iosGet(k) : null; },
          setItem: function(k, v) { iosSet(String(k), String(v)); },
          removeItem: function(k) { iosRemove(String(k)); }
        };
        """)

        ctx.exceptionHandler = { _, exc in
            if let e = exc?.toString(), !e.isEmpty {
                handlerError = e
            }
        }

        let value = ctx.evaluateScript(code)

        if let exc = ctx.exception?.toString(), !exc.isEmpty {
            handlerError = exc
            ctx.exception = nil
        }

        res.error = handlerError
        res.logs = box.lines
        if let v = value, !v.isUndefined {
            let s = v.toString() ?? ""
            // Hide bare "undefined" when there are already logs.
            if s != "undefined" || box.lines.isEmpty {
                res.result = s
            }
        }
        return res
    }
}
