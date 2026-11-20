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

Ships with 3 examples: **Calculator**, **Mini Assistant** (hardcoded replies), **Dice Game** (tap Re-run to roll again).

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

If your tool only accepts a single file: concatenate the 5 files in this order —
`ModuleStore.swift`, `JSEngine.swift`, `ContentView.swift`, `EditorAppsSettings.swift`, `XContainerApp.swift` (the `@main` file last) — into one `.swift` file.

## Notes for sideloading

- The app runs JS locally with JavaScriptCore. No server, no entitlements needed.
- Storage is `UserDefaults`, so modules stay on that device.
- If your builder tool asks for a team / signing: use your own Apple ID (free 7-day cert works for showing a friend).
