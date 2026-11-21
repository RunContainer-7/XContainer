# XContainer — Swift version

Native iOS scripting container in **SwiftUI + JavaScriptCore**.

This replaces the old Expo/React Native prototype with the real Swift app.

## What it does

- **Editor**: type a module name + JavaScript code, hit **Run** to see console output + return value + errors.
- **Save**: stores the module on-device (UserDefaults). Turn on **"Pin as tab panel on Save"** and it also becomes its own tab.
- **Modules**: list of saved modules. Tap one to open its detail page which auto-runs and shows live output. Quick **Run / Pin / Edit / Delete** from the list.
- **Panels/Tabs**: every pinned module appears as an extra tab at the bottom. Tap it and you see that module's output — calculator, dice game, hardcoded assistant, whatever you wrote.
- **Home**: counts, shortcuts, plus a "My Panels" grid for pinned modules.
- **Apps**: recommended sideloading-related apps (same idea as before).
- **Settings**: about, restore examples, reset all.

Ships with 4 examples: **Calculator**, **Mini Assistant**, **Counter App** (interactive HTML tab), **Dice Game**.

## Templates (copy → Add module → Use)

Modules now live in **Containers** (folders): Templates sort themselves into Games/Tools/etc., the Modules tab filters by container chips, and the Editor assigns one. Deletes and Reset ask first, restores never wipe, history skips repeats, names stay unique.

New **Templates** tab with 24 starters in 4 groups:

- **Mini-apps**: Notes, Todos, Timer, Tap Counter UI, Expense Tracker, Habit Tracker, Pomodoro
- **Games**: Dice Roller, Guess Number, Rock Paper Scissors, Tap Dash, Snake, Memory Match
- **Tools**: Calculator+, JSON Formatter, Base64 Tool, Password Generator, Markdown Notes, Unit Converter, Weather Now (live fetch), API Tester, JSON Inspector
- **HTML UI**: Dark Card UI, Form UI (return HTML from JS to render an interactive panel)

Each card has **Copy** (copies code), **Use template** (adds it to Modules), **Use & Open** (adds + jumps to Editor). Search + category filter included.

## What's new in this update

- **Modules**: search bar, Recent/Name/Oldest sort, safe background Run + Stop (no UI freeze on loops), **Share** (text) + **File** (.js export per module), **Export-All** button (JSON backup), fixed file import (security-scoped URLs + error messages).
- **Editor**: one-tap snippets (log / loop / func / html / store), empty-code guard, pin state syncs correctly on save.
- **Engine**: `console.error/warn/info`, `alert/prompt`, `setTimeout/setInterval` polyfill, `fetch(url)` (sync, 12s timeout), `btoa/atob`, `const console/localStorage` so user code can't clobber them. Errors show line numbers, logs capped at 200 lines, 8s run timeout + Stop button so loops never freeze the list.
- **Panels**: HTML detector covers more tags, WKWebView only reloads on new HTML (keeps scroll/input), empty code doesn't auto-run.
- **Settings → Run history**: last 100 runs with time + error flag, Clear button.

## Project layout

```
XContainer/
  XContainerApp.swift      # @main entry
  ModuleStore.swift        # Module model + persisted store + examples
  JSEngine.swift           # JavaScriptCore wrapper (console.log, return value, errors)
  ContentView.swift        # Tabs, Home, Modules list, Module detail + panel
  EditorAppsSettings.swift # Editor, Apps, Settings
XContainer.xcodeproj/
  project.pbxproj
```

No dependencies. Only `SwiftUI` + `JavaScriptCore` + `Foundation`.

## How to open / build

### On a Mac (Xcode)
1. Open `XContainer.xcodeproj` in Xcode 16+.
2. Pick your Team in Signing & Capabilities (bundle id `com.xcontainer.app`).
3. Run on simulator or device (iOS 17+).

### Without a Mac (sideload / on-device builder tool)
1. Create a new iOS App project in your tool with bundle id `com.xcontainer.app`.
2. Copy the 5 `.swift` files from `XContainer/` into it (no extra setup — they only use system frameworks).
3. Build as unsigned IPA, then sideload with your usual tool (AltStore / Sideloadly / LiveContainer flow) and show your friend.

If your tool only accepts a single file: use `BuildBox/XContainer-Combined.swift.txt` —
rename it to `.swift` on your iPhone first. It is the same 5 files joined in order
(`ModuleStore`, `JSEngine`, `ContentView`, `EditorAppsSettings`, `XContainerApp` last).

> BuildBox fix (duplicate-type error): never import BOTH the `XContainer/` folder AND
> the combined file into the same app — pick one. The `.txt` extension in this repo
> stops auto-builders from compiling the same `JSRunResult` struct twice.

## Notes for sideloading

- The app runs JS locally with JavaScriptCore. No server, no entitlements needed.
- Storage is `UserDefaults`, so modules stay on that device.
- If your builder tool asks for a team / signing: use your own Apple ID (free 7-day cert works for showing a friend).
