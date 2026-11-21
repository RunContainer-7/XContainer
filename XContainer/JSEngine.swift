import Foundation
import JavaScriptCore

// Result of running one script.
struct JSRunResult: Equatable {
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

private func formatJSException(_ exc: JSValue) -> String {
    let msg = exc.toString() ?? "Unknown error"
    var line = ""
    var col = ""
    if let l = exc.objectForKeyedSubscript("line")?.toString(), l != "undefined" { line = l }
    if let c = exc.objectForKeyedSubscript("column")?.toString(), c != "undefined" { col = c }
    if !line.isEmpty { return msg + " (line " + line + (col.isEmpty ? "" : ", col " + col) + ")" }
    if let stack = exc.objectForKeyedSubscript("stack")?.toString(), !stack.isEmpty, stack != "undefined" {
        let first = stack.components(separatedBy: "\n").prefix(2).joined(separator: " | ")
        if first.count > 8 { return msg + " | " + String(first.prefix(220)) }
    }
    return msg
}

final class JSEngine {
    static func selfTest() -> String {
        let a = run("1 + 2;").result
        let b = run("console.log('hi'); 'ok';").result
        let c = run("localStorage.setItem('t','1'); localStorage.getItem('t');").result
        return "math=" + a + " log=" + b + " storage=" + c
    }
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
        let iosSleep: @convention(block) (Double) -> Void = { ms in
            if ms > 0 { Thread.sleep(forTimeInterval: min(ms / 1000.0, 2.0)) }
        }
        let iosFetch: @convention(block) (String) -> String = { urlString in
            guard let url = URL(string: urlString) else { return "FETCH_ERROR: bad URL" }
            var out = "FETCH_ERROR: timeout"
            let sem = DispatchSemaphore(value: 0)
            let task = URLSession.shared.dataTask(with: url) { data, _, err in
                defer { sem.signal() }
                if let e = err { out = "FETCH_ERROR: " + e.localizedDescription; return }
                guard let d = data else { out = "FETCH_ERROR: empty"; return }
                out = String(data: d, encoding: .utf8) ?? "FETCH_ERROR: binary"
            }
            task.resume()
            _ = sem.wait(timeout: .now() + 12)
            return out
        }
        ctx.setObject(iosGet, forKeyedSubscript: "iosGet" as NSString)
        ctx.setObject(iosHas, forKeyedSubscript: "iosHas" as NSString)
        ctx.setObject(iosSet, forKeyedSubscript: "iosSet" as NSString)
        ctx.setObject(iosRemove, forKeyedSubscript: "iosRemove" as NSString)
        ctx.setObject(iosSleep, forKeyedSubscript: "iosSleep" as NSString)
        ctx.setObject(iosFetch, forKeyedSubscript: "iosFetch" as NSString)
        ctx.evaluateScript("""
        function __fmt(v) {
          if (v === undefined) return "undefined";
          if (v === null) return "null";
          if (typeof v === "object") { try { return JSON.stringify(v); } catch(e) { return String(v); } }
          return String(v);
        }
        function log() { iosLog(Array.from(arguments).map(__fmt).join(" ")); }
        const console = { log: log, info: log, warn: log, error: log, debug: log };
        function print() { log.apply(null, arguments); }
        function alert(msg) { log("ALERT: " + __fmt(msg)); }
        function prompt(msg, def) { log("PROMPT: " + __fmt(msg)); return def === undefined ? "" : String(def); }
        // Synchronous timer polyfill: runs the callback after a short blocking
        // sleep so template code using setTimeout still works in order.
        // (No background intervals on iOS JSContext — use Re-run for loops.)
        var __timerId = 0;
        function setTimeout(fn, ms) {
          __timerId += 1;
          try { iosSleep(Number(ms) || 0); } catch(e) {}
          try { if (typeof fn === "function") fn(); else eval(fn); } catch(e) { throw e; }
          return __timerId;
        }
        function clearTimeout(id) {}
        function setInterval(fn, ms) { return setTimeout(fn, ms); }
        function clearInterval(id) {}
        function btoa(s) { s = String(s); var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="; var out = "", i = 0; while (i < s.length) { var a = s.charCodeAt(i++), b = s.charCodeAt(i++), c = s.charCodeAt(i++); var x = (a << 16) | ((isNaN(b) ? 0 : b) << 8) | (isNaN(c) ? 0 : c); out += chars[(x >> 18) & 63] + chars[(x >> 12) & 63] + (isNaN(b) ? "=" : chars[(x >> 6) & 63]) + (isNaN(c) ? "=" : chars[x & 63]); } return out; }
        function atob(s) { s = String(s); var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="; var out = "", i = 0; s = s.replace(new RegExp("[^A-Za-z0-9+/=]", "g"), ""); while (i < s.length) { var e1 = chars.indexOf(s.charAt(i++)), e2 = chars.indexOf(s.charAt(i++)), e3 = chars.indexOf(s.charAt(i++)), e4 = chars.indexOf(s.charAt(i++)); var x = (e1 << 18) | (e2 << 12) | ((e3 & 63) << 6) | (e4 & 63); out += String.fromCharCode((x >> 16) & 255) + (e3 === 64 ? "" : String.fromCharCode((x >> 8) & 255)) + (e4 === 64 ? "" : String.fromCharCode(x & 255)); } return out; }
        function fetch(url) { var text = iosFetch(String(url)); return { text: text, json: function() { return JSON.parse(text); } }; }
        const localStorage = {
          getItem: function(k) { k = String(k); return iosHas(k) ? iosGet(k) : null; },
          setItem: function(k, v) { iosSet(String(k), String(v)); },
          removeItem: function(k) { iosRemove(String(k)); }
        };
        """)

        ctx.exceptionHandler = { _, exc in
            if let e = exc {
                handlerError = formatJSException(e)
            }
        }

        let value = ctx.evaluateScript(code)

        if let exc = ctx.exception {
            handlerError = formatJSException(exc)
            ctx.exception = nil
        }

        res.error = handlerError
        res.logs = Array(box.lines.prefix(200))
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
