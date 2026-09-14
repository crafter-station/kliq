![Kliq](site/og.png)

# Kliq

Mechanical keyboard sounds for every keystroke and click, as a macOS menu bar app.
Free and open source. Native Swift, SwiftUI and AppKit, no third-party dependencies.

**[kliq.crafter.run](https://kliq.crafter.run)**

Seven recorded sound profiles ship with the app: hover to audition, click to choose,
and start typing.
It goes quiet automatically during calls.

## Install

Download [Kliq.dmg](https://github.com/crafter-station/kliq/releases/latest/download/Kliq.dmg)
from the latest [release](https://github.com/crafter-station/kliq/releases), open it
and drag Kliq to Applications. Builds are signed with a Developer ID and notarized by
Apple, and run on Apple silicon and Intel with macOS 15 or later.

On first launch Kliq asks for the Accessibility permission, which it needs to notice
key presses in other apps. It only listens: it never records, stores or changes what
you type, and it makes no network requests.

## Features

- Global key down / key up sounds through a listen-only `CGEvent` tap on its own thread
- 24-voice polyphonic engine on `AVAudioEngine`, per-key pitch variation and stereo panning
- Seven recorded sound profiles with hover previews, pitch and brightness controls, and a choice of output device
- Mouse click sounds, typewriter ding on Return, audible modifier keys, key-repeat filtering
- Sleep triggers: microphone in use by another app, camera in use, Music or Spotify playing
- Global toggle hotkey (default ⌃⌥K), launch at login, usage stats with favorite switch
- Settings window (General, Sound, Sleep, Stats, About) and a first-run guide

## Sound sets

Kliq ships its switch sets inside the app; this section is for contributors adding
a new one. A set is a folder of `<code>-down.wav` / `<code>-up.wav` files, where `<code>` is a
PC scan code (set 1). Any format that
`AVAudioFile` reads works (wav, caf, aiff, m4a, mp3), at any sample rate or channel
count; everything is converted to 48 kHz stereo float at load time.

| Codes | Keys |
|-------|------|
| 2-11 | number row (1 to 0) |
| 16-25 | q w e r t y u i o p |
| 30-38 | a s d f g h j k l |
| 44-50 | z x c v b n m |
| 14 / 15 / 28 / 41 / 57 / 58 | backspace / tab / return / backtick / space / caps lock |
| 42 / 54 | left / right shift |
| 29, 56 / 3640, 3675 / 3676 | control, option, command |
| 57416 / 57419 / 57421 / 57424 | up / left / right / down |
| 1, 59-68, 87, 88 | esc and F1 to F12 |

Missing codes fall back to a neighbouring key, so a set with 57 files still covers
the whole keyboard. Top-level effect files are also loaded: `ding` (Return),
`left-down`, `left-up`, `right-down`, `right-up` (mouse) and `click` (fallback).

Sound design by Cris. Seven recorded profiles ship with the app: Cherry, DSA, KAT,
MT3, OEM, SA, and XDA. Their per-key press and release samples, along with the bundled
mouse and Return effects, are WAV files. These are the complete product sound library.

## Build from source

```
./build.sh
open build/Kliq.app
```

Or `make build` / `make run`. `make help` lists every shortcut (build, dmg,
release, web-sounds, icon, og, dmg-background, diagnose, clean) wrapping the
scripts below.

Requires macOS 15 and Xcode 26 (or a matching Swift toolchain). The script compiles
with `swift build`, assembles `build/Kliq.app`, and signs it with the hardened runtime.

macOS ties the Accessibility grant to the code signature, so `build.sh` signs with
the same Developer ID as releases when it's in your keychain (falling back to an
Apple Development identity). That keeps the permission working across rebuilds and
releases; switching identities makes an existing grant silently stop applying.
Override it, or force ad-hoc signing, with:

```
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./build.sh
CODESIGN_IDENTITY="-" ./build.sh
```

If key presses stop making sound after a rebuild, the grant went stale. Reset it
and relaunch:

```
tccutil reset Accessibility run.crafter.kliq
```

## Releasing

`release.sh` builds a universal binary, signs it with a Developer ID, packages a
DMG, notarizes and staples it, and prints its SHA-256. It refuses to run if
`Resources/` has anything that is not committed, so a release contains exactly what
is in this repository. The DMG is always named `Kliq.dmg`, so the
`releases/latest/download/Kliq.dmg` link on the website keeps working.

The DMG opens as a drag-to-Applications window. `Tools/make_dmg.sh` builds it with
[dmgbuild](https://github.com/dmgbuild/dmgbuild) (run through `uv`, so nothing to
install) over `Resources/DMGBackground.tiff`, which `make dmg-background` renders
from `Tools/dmg.html`. `make dmg` builds an unnotarized copy to preview the window.

```
# once: store notarization credentials in the keychain, using an App Store
# Connect API key (Users and Access → Integrations → Team Keys, Developer role)
xcrun notarytool store-credentials kliq-notary \
  --key AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <issuer-uuid>

./release.sh 0.0.1
gh release create v0.0.1 build/Kliq.dmg --title "Kliq 0.0.1" --generate-notes
```

## Layout

```
Sources/Kliq/
  App/      entry point, AppController (wiring), Settings, AppState
  Audio/    SoundEngine, SoundSet + SoundLibrary, KeyMapper
  Input/    InputMonitor (event tap), AccessibilityManager
  Sleep/    SleepManager and the Microphone, Camera, NowPlaying monitors
  System/   HotKeyManager (Carbon), LaunchAtLogin (SMAppService)
  Stats/    StatsManager
  UI/       StatusMenuController and MenuBar/ (menu bar menu), Settings/ (settings
            window), OnboardingView, Components/ (KliqLogo, set badges, keycaps)
Tools/      gen_sounds.py, make_web_sounds.py, render_icon.sh, diagnose_triggers.swift
Resources/  Info.plist, Kliq.entitlements, AppIcon.svg + AppIcon.icns, Sounds/
site/       kliq.crafter.run, a static page deployed on Vercel
```

## Troubleshooting

The app logs its state under the subsystem `run.crafter.kliq`. Watch it live while
launching:

```
/usr/bin/log stream --predicate 'subsystem == "run.crafter.kliq"' --level debug --style compact
```

A healthy launch reports the audio engine starting, Accessibility trusted, the
event tap starting, the set loading with its sample count, and the first input
event once you type.

To see what the sleep triggers currently detect:

```
swift Tools/diagnose_triggers.swift
```

## License

MIT © Crafter Station. See [LICENSE](LICENSE).
