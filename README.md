<p align="center"><img src="docs/icon.png" width="128" alt="Platter icon"></p>

<h1 align="center">Platter</h1>

<p align="center">Your music, playing on your desktop.<br>
A tiny macOS menu bar app that turns whatever you're listening to in Spotify or Apple Music into a living desktop scene.</p>

![Turntable](docs/screenshots/turntable.jpg)

The current album cover becomes the sleeve, the record label, the cassette sticker or the CD print. Records spin, tape winds from spool to spool, keys press when you play, pause or skip, and the scene fades back to your normal wallpaper when nothing is playing.

## Scenes

| | |
|---|---|
| ![Room](docs/screenshots/room.jpg) **Room** — desk against a wall: the album on a stand, the record on the deck, recently played covers in a stack | ![Turntable](docs/screenshots/turntable.jpg) **Turntable** — top-down deck on a planked table; the tonearm drops in when you press play and tracks the song's progress |
| ![Cassette](docs/screenshots/cassette.jpg) **Cassette** — portable tape player; Play latches down, spools wind as the track plays | ![Discman](docs/screenshots/discman.jpg) **Discman** — the disc printed with the cover spins under a smoked lid, LCD shows progress |
| ![Boombox](docs/screenshots/boombox.jpg) **Boombox** — thumping speakers, dancing EQ, a tuning needle that follows the song | |

## Lighting

Every scene comes in **Day**, **Sunset** and **Night**, or **Auto** to follow the clock (day 07–17, sunset 17–20, night after). At night a lamp lights the scene and anything with its own light — LEDs, the Discman's LCD, the Boombox's dial and EQ — keeps glowing.

| Day | Sunset | Night |
|---|---|---|
| ![Room, day](docs/screenshots/room.jpg) | ![Room, sunset](docs/screenshots/room-sunset.jpg) | ![Room, night](docs/screenshots/room-night.jpg) |
| ![Boombox, day](docs/screenshots/boombox.jpg) | ![Boombox, sunset](docs/screenshots/boombox-sunset.jpg) | ![Boombox, night](docs/screenshots/boombox-night.jpg) |

*Screenshots use made-up sample covers; in use you'll see your own albums.*

## Features

- Works with **Spotify** and **Apple Music**
- Lives in the menu bar — no Dock icon. Left click for the panel (now playing, progress, ⏮ ⏯ ⏭, scenes), right click for a quick scene menu
- Easy on the battery: animations run on the GPU via Core Animation, capped at 30 fps, and stop entirely when the desktop is covered, an app is full screen, or Low Power Mode is on. Players are polled only every 15 s — track changes arrive as notifications
- Optional: hide the scene while paused, launch at login
- Multiple displays supported
- Free and open source (MIT)

## Install

1. Download `Platter-x.y.dmg` from [Releases](../../releases) and drag **Platter** to **Applications**.
2. The app isn't notarized, so macOS blocks the first launch. Open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**. Or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Platter.app
   ```
3. When asked, allow Platter to control **Spotify** / **Music** — that's how it reads the current track. You can change this later in **System Settings → Privacy & Security → Automation**.

Can't find the menu bar icon? On MacBooks with a notch, icons can hide behind it when the menu bar is full. Open Platter again from Applications or Spotlight and its panel appears as a window.

Requires macOS 14 Sonoma or later. Universal: Apple Silicon and Intel.

## Build from source

Needs Xcode 15+ (or the Swift toolchain that ships with it).

```bash
git clone https://github.com/Aqpanbek/platter.git
cd platter
./build.sh            # → build/Platter.app
./build.sh --dist     # → also dist/Platter-<version>.dmg and .zip
```

Preview every scene without launching the app:

```bash
swift build -c release && .build/release/Platter --render /tmp/platter
```

## How it works

- **Now playing** — `Sources/Platter/NowPlaying.swift` asks Spotify and Music over AppleScript (and listens to their playback notifications) for the track, its position and the artwork. If a cover can't be read from the player, it is looked up in the iTunes Search API.
- **Desktop** — `Sources/Platter/DesktopController.swift` puts a borderless, click-through window on every screen at desktop level: above the wallpaper, below your icons.
- **Scenes** — `Sources/Platter/Render/` draws every scene procedurally with Core Graphics (wood is grown from simulated tree rings and boards, concrete and felt are generated noise; no image assets). Motion is Core Animation: spinning records and spools, key presses, the tonearm, speaker thump and cross-fades on track change.

### Adding a scene

Subclass `DesktopScene`, lay out your layers in `build()` on the 1600×1040 design canvas, react in `artworkDidChange`, `playbackDidChange`, `progressDidChange` and `trackSkipped`, call `applyMood(lamps:glowing:)` at the end of `build()` so it gets sunset and night lighting, then add a case to `SceneKind`.

## Privacy

Platter talks only to your local Spotify / Music apps. The one network request it makes is the artwork fallback: when a player doesn't hand over a cover, the artist and album name are sent to Apple's iTunes Search API to find it. No analytics, no accounts.

## License

[MIT](LICENSE)
