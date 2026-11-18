# PokeDaisy for iPhone (iPhone Duo first, early preview)

A port of PokeDaisy to iOS, laid out for the iPhone Duo: the game and the live companion are on screen together, the way
they are on a two-screen handheld. Like the 3DS port, it's a new host around the same portable C (the 3DS port's
companion in `3ds/core/`, its session in `3ds/host/`, the app's `pk_*.c`), not a recompile of the Android app, which is
Kotlin and Jetpack Compose.

**Status: preview, not yet tried on a device.** The C side runs headless in CI on the diagnostic ROMs
(`ios/core/test/pd_ios_smoke.c`): both panes draw, taps reach the companion, the QUICK MENU opens, the sound runs at
48 kHz, saves are written and backed up. The Swift app builds in CI (`.github/workflows/ios.yml`).

## What it plays

GBA, Game Boy and Game Boy Color games, all on **mGBA's interpreter** (the same mGBA 0.10.5 submodule as the other
builds). An iOS app gets no executable memory unless JIT is turned on, so the recompilers the 3DS uses (armGBA, gpSP)
aren't built: `core/pd_ios_nocores.c` stands in for them. A recent iPhone runs mGBA's interpreter comfortably past full speed.
No DS games yet.

The companion covers what the 3DS port's does: PARTY, BAG, MAP, GUIDE, POKéDEX, BATTLE, BOXES, CARD, STATES and
SETTINGS. The HUD, the QUICK MENU and EXPAND are drawn over the game.

## Screens

Both panes keep their shape: the game's is the 3DS top screen's 5:3, at twice its size (a GBA game at a whole 3x), and
the companion's is 320x240. The app picks whichever arrangement gives the game the most room, so it follows the Duo as
it folds and turns:

- **Stacked, buttons under**: the game over the companion, the touch buttons below (folded, upright).
- **Stacked, buttons beside**: the same column, with the D-pad on the left and the buttons on the right (the Duo open,
  either way round).
- **Side by side**: the game on the left, the companion on the right, the buttons at the ends (a phone on its side).

The touch buttons go away while a game controller is connected. Both pictures use sharp bilinear scaling, so pixels
stay even at any size.

## Controls

On screen: the D-pad, A, B, L, R, SELECT, START, **MENU** (the QUICK MENU) and **FF** (fast-forward while held).
Tap the companion to use it. Its SETTINGS tab has CLOSE GAME, which takes you back to the game list.

A controller's buttons go by where they sit, as on a Nintendo pad:

| Controller | PokeDaisy |
| --- | --- |
| Right face button | A |
| Bottom face button | B |
| Top face button | X: the buttons go to the companion (on the field), BACK elsewhere |
| Left face button | Y: the QUICK MENU |
| L1 / R1 | L / R |
| L2 | the companion's tab before |
| R2 | fast-forward while held |
| Menu / Options | START / SELECT |

Keyboard: arrows, X = A, Z = B, A / S = L / R, Return = START, Backspace = SELECT, C = X, Q = QUICK MENU, Tab = FF.

## Your files

Everything is in the Files app under **On My iPhone > PokeDaisy**:

- `ROMs/`: your games (`.gba`, `.gb`, `.gbc`) and their battery saves beside them (`<game>.sav`, mGBA's layout, so a
  save moves to and from mGBA, RetroArch and PokeDaisy on other devices). Add games with **+** in the game list or by
  copying them in. No games are included.
- `PokeDaisy/`: `settings.ini`, `states/`, `cheats/` (by the ROM's CRC32, mGBA's `.cheats` format), `nuzlocke/`, and
  `backups/<game>/`: the save is copied there before every start and every state load, the newest 10 kept.

## Installing it (from Windows)

The CI makes an unsigned `.ipa`. iOS only installs apps signed for your device, so a sideloading tool signs it with
your own Apple ID:

1. On the repo's **Actions** tab, open the latest **iPhone** run and download the **PokeDaisy-iOS** artifact (a zip
   with `PokeDaisy-iOS.ipa` inside).
2. Install **AltStore** (AltServer for Windows, with iTunes and iCloud from Apple's website, not the Microsoft Store)
   or **SideStore**, following their own guides.
3. Open the `.ipa` with AltStore / SideStore on the phone. Turn on **Developer Mode** when iOS asks (Settings > Privacy
   & Security).

With a free Apple ID the app has to be refreshed every 7 days (AltStore / SideStore do it for you), and you can have
3 sideloaded apps at a time.

## Building it

Needs a Mac with Xcode 16+, CMake and XcodeGen (`brew install cmake xcodegen`):

```sh
git submodule update --init third_party/mgba
sh ios/build_core.sh                    # the C side -> ios/build/lib/libpokedaisy_core.a
xcodegen generate --spec ios/project.yml
open ios/PokeDaisy.xcodeproj            # pick your team under Signing to run it on your phone
```

The C side alone, anywhere (Linux too), with its smoke test:

```sh
cmake -S ios/core -B build/ios-core && cmake --build build/ios-core --target pd_ios_smoke
python3 linux/make_diagnostic.py        # diagnostic.gb / diagnostic.gba, original test programs
build/ios-core/pd_ios_smoke diagnostic.gba out
```

## How it fits together

- `core/pd_ios.c`: the session's host, the iPhone's version of `3ds/ctr/main.c`. It owns the files, the buttons, the
  sound (a lock-free ring the audio thread reads, the emulated rate nudged to keep ~50 ms queued) and the two
  pictures: the top screen composed the way `3ds/ctr/gpu.c` draws it (SCREEN's sizes, EXPAND's window, the dim and the
  overlay), the companion as `pd_session_draw` leaves it.
- `App/`: SwiftUI. `Emulator.swift` ticks the C side once a 60 Hz refresh (CADisplayLink, ProMotion held to 60),
  `PixelView.swift` / `Shaders.metal` draw the pictures, `AudioOut.swift` plays the ring, `Controllers.swift` reads
  controllers and keyboards, `GameScreen.swift` lays the screen out, `TouchControls.swift` is the on-screen pad.
- `project.yml`: the Xcode project, generated by XcodeGen (not committed).

## Not yet

- Tried on an iPhone (the CI builds it; nobody has run it yet).
- DS games (melonDS on iOS runs without JIT but slowly; DSperate is an option for later).
- The manual (`docs/manual/`) doesn't cover this build yet.
- Game art scaling options, an on-screen layout editor, haptics settings, iCloud saves.
