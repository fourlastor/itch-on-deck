# itch on Deck: specification

Draft 1, 2026-10-04, amended the same day after the first build. What that build showed is in
section 14; the sentences it proved wrong are corrected where they stand, and say so.

**What this is based on.** butler v15.31.0 and the description of its daemon API
(`butlerd/generous/spec/butlerd.json` in `itchio/butler`, as of 2026-09-24), the README and source
of `itchio/itch-setup`, the source of the itch app (`itchio/itch`), and a working one-game updater
(`tools/deck_update.py` in the Sands of the Duel repository). The API was read, not run: a claim
marked **(to verify)** has to be tried against a real daemon, which is what milestone 0 is for.
Section 14 lists the claims tried so far.

## 1. Summary

A small, self-contained app for a Steam Deck (and any Linux PC) with which a signed-in itch.io
user can:

1. see what they can install: the games they own, their collections, their own projects (drafts
   included) and search results;
2. install a game, when they ask for it;
3. play the installed games, from the app or from the Steam library, where a button puts them;
4. keep the installed games up to date, by hand or on a schedule that systemd runs.

It needs no desktop session and no itch app, and it is driven with a controller in Gaming Mode.
All the itch.io work (signing in, listing, downloading, patching, launching) is done by butler,
itch.io's own tool, in its daemon mode. The app is a front end and a scheduler around butler.

### Why not the itch app

- It needs a display, so it cannot run as a background service in Gaming Mode.
- It does not look for game updates by itself: its periodic check is switched off in its source,
  and a game is checked when its page is opened in the app.
- Its interface is made for a mouse.

It has two things worth keeping in mind: `itch-setup --run-game <id>` launches an installed game
with no window (through `butler launch`), and it can add games to Steam as shortcuts.

### Goals

- **G1** Everything works in Gaming Mode: controller only, 1280x800, started from one non-Steam
  shortcut.
- **G2** Only what the user asks for is installed.
- **G3** Installed games can update without the app open, when the user has switched that on. An
  update costs the size of what changed (butler's patches), not the size of the game.
- **G4** Self-contained: it lives in the home folder, brings its own butler, and needs neither
  root nor system packages, so a SteamOS update does not remove it.
- **G5** Safe: a running game's files are never touched, no connection means "not now" and never
  a failure, and a stopped install leaves nothing half-installed.

### Not in version 1

- Buying games, store pages, ratings, comments: there is no embedded browser.
- HTML5 games, books, soundtracks, and anything else that needs a browser or the desktop's file
  handlers.
- Windows-only games (see open question 3).
- Publishing builds, although butler's daemon can.
- Several accounts at once.
- Searching itch.io's catalogue: butler cannot do it (section 14). Version 1 searches the games
  the account can reach; what to do about the catalogue is left for version 1.1.
- Opening a collection after a sign-in through the browser: itch.io does not let such a login
  read a collection's games (section 14). Left for version 1.1.

## 2. Terms

| Term | Meaning |
|---|---|
| butler | itch.io's command-line tool. `butler daemon` is a long-running mode that answers JSON-RPC requests; the itch app is a front end for it. |
| profile | A signed-in itch.io account, kept in butler's database. |
| game | A page on itch.io (a game, a tool, ...). |
| upload | One downloadable file of a game, for example its Linux build. |
| wharf upload, channel, build | An upload pushed with butler. It has builds (versions), and a patch from each build to the next. |
| download key | What gives an account access to a paid or restricted game. "The library" is the list of keys an account owns. |
| cave | butler's record of one installed upload: its folder, its build, its play time. |
| install location | A folder under which games are installed (internal storage, an SD card). |

## 3. Requirements

### 3.1 Signing in

- **R1** The user signs in once; the login survives restarts (butler keeps the profile).
- **R2** Signing in is possible with a controller alone. Preferred: device sign-in, where the app
  shows a QR code and a short code and the user approves on a phone; itch.io allows it only to
  applications it has approved (section 14). Until then: sign-in through a browser, where the
  user allows the app on itch.io's own page and no key is typed. Fallback: an API key made on
  itch.io, typed or read from a file. The key `butler login` saves is not one: itch.io refuses
  it for anything but pushing builds.
- **R3** Signing out removes the profile.

### 3.2 Finding games

- **R4** Five lists: Installed, Owned, Collections, My projects, Search.
- **R5** My projects lists the user's own pages, drafts included, and marks the drafts.
- **R6** Search takes text (Steam's on-screen keyboard) and looks through the games the account
  can reach: owned, in its collections, its own projects and the installed ones. It does not ask
  itch.io: butler has no request for that (section 14). Each of the other lists can be filtered
  by text.
- **R7** An entry shows the title, the cover, the short text, whether it is installed, whether an
  update is known, "not installable here" when it has no Linux upload, and "not owned" when it
  is a paid game the account does not own (it is listed, and cannot be installed).
- **R8** With no connection the lists show what butler has cached, marked as possibly out of date,
  and refresh when the connection is back.

### 3.3 Installing

- **R9** Nothing is installed unless the user asks: owned games are not installed by themselves,
  and the scheduled job never installs a game that is not installed already.
- **R10** Installing a game: the user picks it, the app shows the uploads that fit this machine
  (usually one) with the download size and the free space needed, the user confirms (and picks
  the install location when there are several), and the download shows progress, speed and time
  left.
- **R11** Several installs can wait in a queue; one runs at a time; each can be cancelled. A
  cancelled or failed install leaves nothing behind.
- **R12** After a sleep or a lost connection a download carries on where butler can resume it
  **(to verify)**, and otherwise starts again cleanly.
- **R13** Uninstalling removes the game's folder and its cave, after the user confirms.
- **R14** Install locations: `~/Games/itch` to start with; the user can add others (an SD card).
  Each shows its free space.

### 3.4 Playing

- **R15** A game can be started from the app. The app then uses as little as it can until the game
  exits. butler records the play time.
- **R16** An installed game has an "Add to Steam" button. Pressing it puts the game in the Steam
  library as a non-Steam game, with nothing left to do by hand in Steam: the game's title as the
  name, its cover as the artwork where Steam allows, and a launch that needs neither the app nor
  a window of it (section 7).
- **R16a** The button then reads "In Steam" and offers "Remove from Steam". Uninstalling a game
  removes its Steam entry too.
- **R16b** If Steam has to restart before the entry shows, the app says so.
- **R16c** The app can add itself to Steam the same way, so that it can be opened in Gaming
  Mode: from Settings, and from the sign-in screen, which is the first screen of a new install.
  Its entry gets library images that the app draws itself.
- **R17** A game that needs what the app cannot give (a browser, a licence to accept in a window
  it cannot show) is reported plainly, not started half-way.

### 3.5 Updating

- **R18** "Check for updates" for one game, or for all installed games.
- **R19** One setting for the schedule: off (the default), or an interval (15 minutes, 1 hour, 6
  hours, daily). With the schedule on, every installed game is updated except those the user
  pinned to their current version.
- **R20** The scheduled job runs without the app, from a systemd user timer, applies the updates
  and writes what it did to the journal.
- **R21** It never updates a game that is running: that game waits for the next run.
- **R22** No connection (the Deck just woke, Wi-Fi is not back yet, or it sleeps in the middle of
  a download) is not an error. The job waits a minute for the connection, and otherwise leaves
  everything as it is for the next run.
- **R23** An update the job cannot decide alone (several possible uploads) is left for the app to
  show.
- **R24** The app shows what the last runs did: when, which games were updated, what went wrong.

### 3.6 General

- **R25** Controller first, readable on the Deck's screen at 1280x800; keyboard and mouse work too.
- **R26** Factual text only: what a thing is and what state it is in.
- **R27** The app manages its own butler: it downloads it, checks it, and updates it when asked.
- **R28** With itch.io unreachable, the installed games are still listed and can be played.

## 4. Architecture

```
Steam (Gaming Mode)
  shortcut "itch on Deck" ......... GUI app ---- JSON-RPC ----> butler daemon --+
  shortcut per game (optional) .... run-game ---> butler launch (no window) ----+--> butler.db
systemd --user                                                                  |    install locations
  itch-on-deck-update.timer ....... updater ---- JSON-RPC ----> butler daemon --+
```

Three programs use one database: the app, the updater and the launcher. butler's source says this
is safe: the database is in WAL mode, and a lock per install folder keeps a launch and an install
from running on the same game at once **(to verify under our use)**.

### 4.1 Files

| Path | What |
|---|---|
| `~/.local/share/itch-on-deck/butler/<version>/` | butler and its two 7-zip libraries |
| `~/.local/share/itch-on-deck/db/butler.db` | butler's database: the profile, the caves, the cache |
| `<install location>/downloads/` | partial downloads: butler's queue keeps them next to the games, on the same disk, not under the app's own folder |
| `~/.local/share/itch-on-deck/state.json` | what the last update runs did |
| `~/.config/itch-on-deck/config.json` | settings: the schedule, the install locations, the profile in use |
| `~/.config/systemd/user/itch-on-deck-update.{service,timer}` | written and enabled by the app |
| `~/Games/itch/` | the default install location |

The app keeps its own database rather than sharing the itch app's (`~/.config/itch`): it has to
work with no itch app installed, and a shared database ties both to the same butler version.

### 4.2 Talking to the daemon

- Start: `butler --json --dbpath <db> daemon --transport stdio --destiny-pid <own pid>`. The daemon
  also takes `--transport tcp` (the default: it prints a `butlerd/listen-notification` line with a
  secret and an address, and the first request must be `Meta.Authenticate` with that secret),
  `--keep-alive`, `--low-power` ("favor a small CPU and memory footprint over speed, for
  battery-powered devices") and `--log`.
- JSON-RPC 2.0. Traffic goes three ways: requests from the client, notifications from the daemon
  (progress, log lines), and requests from the daemon that the client must answer (section 4.4).
- `Meta.Flow` is the long conversation that carries the global notifications and keeps the daemon
  alive; `Meta.Shutdown` ends it.
- The API description is a generated file. The client's request and result types should be
  generated from it too, so that a new butler version shows what changed.
- `daemon` and `launch` are hidden commands, an interface made for the itch app. The app pins one
  butler version and moves to a newer one only after milestone 0's script passes against it.

### 4.3 Calls per feature

| Feature | Calls | Notes |
|---|---|---|
| Sign in with a device | `Profile.LoginWithDevice` | Notification `Profile.LoginWithDevice.Challenge` gives the URL for the QR code, the code to show under it and its lifetime. Needs an OAuth client ID registered for the device grant (open question 1). |
| Sign in with a key | `Profile.LoginWithAPIKey` | Also what the browser sign-in ends with: the app gets the key from itch.io's OAuth page and hands it over. |
| Come back | `Profile.List`, `Profile.UseSavedLogin` | |
| Sign out | `Profile.Forget` | |
| The four lists | `Fetch.GameRecords` | `source`: `owned`, `installed`, `profile` or `collection`; with `search`, `sortBy`, `filters`, `limit`, `offset`. The result says when it is stale. |
| Collections | `Fetch.ProfileCollections`, `Fetch.Collection.Games` | |
| My projects | `Fetch.ProfileGames` | `filters.visibility`: `draft` or `published`; each item says `published`. |
| Search | `Search.Local` | The account's own games. `Search.Games` reads only butler's database too, and at most four rows of it. |
| A game's uploads | `Install.GetUploads` | Gives the uploads that fit, and the ones that do not. |
| Size before installing | `Install.Plan`, `Install.PlanUpload` | Final size and free space needed. |
| Install | `Install.Queue`, then `Downloads.Drive` or `Install.Perform` | `Install.Queue` with `queueDownload` hands it to the download queue; notifications `Downloads.Drive.Progress`, `.Finished`, `.Errored`, `.NetworkStatus`. |
| Cancel | `Install.Cancel`, `Downloads.Drive.Cancel`, `Downloads.Discard` | |
| Installed games | `Fetch.Caves`, `Fetch.Cave` | A cave has its game, upload, build, folder, size and play time. |
| Uninstall | `Uninstall.Perform` | |
| Install locations | `Install.Locations.List`, `.Add`, `.Remove`; `System.StatFS` | |
| Look for updates | `CheckUpdate` | With no cave IDs: every cave, skipping pinned and snoozed ones. With cave IDs: those caves. The result lists each update with its possible uploads and builds. |
| Apply an update | `Install.Queue` with the cave and `reason: update`, then perform | Patches for wharf uploads **(to verify)**. |
| Pin a version | `Caves.SetPinned` | A pinned cave is left out of update checks. |
| Play from the app | `Launch` | `allowedStrategies: [native]` keeps HTML5, shell and URL launches out. Notifications `LaunchRunning`, `LaunchExited`. |
| Play from Steam | `butler --json --dbpath <db> launch --cave <id>` | Not the daemon: a command. Exit code 3 means the launch needs a full client. |
| Add to Steam | `steam://addnonsteamgame/<path>`, or Steam's `shortcuts.vdf` | Not butler: section 7. |
| Limit bandwidth | `Network.SetBandwidthThrottle` | A possible setting. |

### 4.4 What the daemon asks the client

| Request | When | The app | The updater |
|---|---|---|---|
| `PickUpload` | Several uploads fit | Shows a picker | Declines; the update is left for the app (R23) |
| `AcceptLicense` | A game comes with a licence | Shows it | Does not apply |
| `PickManifestAction` | A game offers several things to launch | Shows a picker | Does not apply |
| `PrereqsFailed` | A game's prerequisites did not install | Asks whether to go on | Does not apply |
| `AllowSandboxSetup` | The sandbox needs setting up | Asks | Does not apply |
| `HTMLLaunch`, `ShellLaunch`, `URLLaunch`, `RuntimeLaunch` | A game that is not a native program | Not asked: excluded by `allowedStrategies` | Does not apply |
| `Profile.LoginWithDevice.RequestDeviceInfo` | During device sign-in | Answers with nothing, or the device's name | Does not apply |

## 5. Who can install what

| Case | Covered | How |
|---|---|---|
| A game the user owns (bought, claimed, from a bundle) | Yes | Owned list; the download key gives access. |
| A free public game | Yes | Search or a collection; no key needed. |
| The user's own project, published or draft | Yes **(to verify in milestone 0)** | My projects; the owner's login gives access. The itch app, a front end for the same daemon, installed Sands of the Duel while it was a draft; that game is the first test. |
| Someone else's draft, by its secret URL | No | See below. |
| A page behind a password | No | See below. |

itch.io's API accepts a page's secret or its password next to the login: the Go client library
(`go-itchio`) has both. The daemon does not pass them on: its game credentials carry an API key
and a download key, nothing else. So the app cannot reach, through butler, a page that only a
secret URL or a password opens.

For friends testing someone's unreleased game, the way that fits is a download key: the owner
makes keys for the project, a friend claims one to their account, and the game is then in the
friend's Owned list like a bought one. Whether a claimed key opens a page that is still a draft,
or the page has to be set to restricted first, is **to verify** on itch.io.

Passing the secret would need a change in butler, or the app calling itch.io's API itself for
that one case. Neither is planned.

## 6. Installing

1. The user opens a game and presses Install.
2. `Install.GetUploads` gives the uploads that fit this machine. With none, the app says so and
   lists what the game does have (Windows only, HTML5 only).
3. With several, the user picks one. Demos and pre-orders are labelled.
4. `Install.Plan` gives the size. With too little free space in every install location the app
   says how much is missing and does not start.
5. `Install.Queue` and the download queue do the rest; the Downloads screen shows each item.
6. A finished install appears in Installed. A failed one shows butler's reason, and Retry.

Version 1 installs Linux uploads only. butler can also run Windows games through Wine, and on a
Deck the better route is a Steam shortcut with Proton, which is what the itch app writes: that is
open question 3.

## 7. Adding a game to Steam

What the button makes is a non-Steam shortcut:

| Field | Value |
|---|---|
| Name | The game's title |
| Target | `run-game <cave ID>`, the launcher script the app installs (section 10) |
| Start in | The game's install folder |
| Artwork | The game's cover: the shortcut's icon and, where Steam takes them, its library images |

The launcher runs `butler launch` for that cave. The game starts with no app window, butler
records its play time, and Steam's overlay and controller settings apply to it as to any non-Steam
game. The shortcut names the cave, not a build, so updating the game does not change it.

There are two ways to make Steam take the shortcut. Milestone 0 tries both on a Deck:

1. **Ask the running Steam.** SteamOS has `steamos-add-to-steam`, which opens a
   `steam://addnonsteamgame/<path>` address. Given a `.desktop` file, Steam reads the name, the
   command and the icon from it, and the entry should appear at once, with no restart. It cannot
   set library images or remove an entry. **(to verify: this is written from memory, so first
   that the script and the address are as described; then that it works in Gaming Mode, for a
   `.desktop` file the app writes, and on a PC's Steam)**
2. **Write Steam's shortcuts file**, `userdata/<user>/config/shortcuts.vdf`, a binary file, as the
   itch app does. It can set every field and remove entries; Steam shows the change after it
   restarts. The itch app's rules apply: recognise the app's own entries by a marker Steam keeps
   (the itch app uses the `DevkitGameID` field), replace the file in one step, never rewrite a
   file that could not be read in full, and never make two writes at once. **(to verify: whether
   an entry written while Steam runs survives Steam's exit)**

The first is preferred where it works, since nothing restarts. The second is the fallback, and
the way to remove an entry. On a PC's Steam the first works as described, except that Steam
takes neither the icon nor the folder from the `.desktop` file (section 14); the app gives the
entry its library images itself. With several Steam users on the machine, the user picks which one
gets the entry.

## 8. Updating on a schedule

The app writes two units and enables or disables the timer when the setting changes. No root is
needed.

```ini
# itch-on-deck-update.service
[Unit]
Description=itch on Deck: update the installed games

[Service]
Type=oneshot
ExecStart="%h/.local/share/itch-on-deck/update-run" "<the app's program file>"
SyslogIdentifier=itch-on-deck
Nice=10
IOSchedulingClass=idle
```

`update-run` is a small script the app writes. It copies the app's program file to
`~/.cache/itch-on-deck/update-run/` when the copy is not the same file any more, and starts the
run from the copy with `--headless -- update`, telling it in `ITCH_ON_DECK_APP` where the app
really is. The run cannot be started from the app's own file: it may have to replace that file,
and Linux does not let a file be written while a program runs from it (section 14, On a Deck).
The app writes the units and the script again at its start when they are not what it would
write now, which is so after it was moved to another folder.

```ini
# itch-on-deck-update.timer
[Unit]
Description=itch on Deck: look for updates

[Timer]
OnStartupSec=2min
OnCalendar=*:0/15

[Install]
WantedBy=timers.target
```

`OnCalendar` follows the setting. A calendar timer missed during sleep should run when the machine
wakes, which is when a Deck is picked up **(to verify on the Deck)**.

What a run does:

1. Take a lock, so that two runs never overlap. With the lock taken, end.
2. Wait up to a minute for itch.io to be reachable. If it is not, write "no connection" and end
   without an error.
3. Start the daemon and call `CheckUpdate` for every cave: pinned ones are skipped by butler.
4. For each update: skip it when its game is running, or when it offers more than one possible
   upload. Otherwise queue it with `reason: update` and perform it.
5. A download cut short is removed. With the connection gone that is "not now"; with the
   connection there it is an error, and the run ends as failed so that systemd shows it. What
   a removed download had fetched is deleted by butler a moment later; a run that ends before
   that leaves the folder, and the next run, or the app at its start, removes it.
6. Write to `state.json` what was updated, skipped and failed, for the app to show.

A game being updated when the user starts it: butler's lock on the install folder makes the
launch wait for the update to finish **(to verify)**. The app should show that it is waiting.

## 9. Screens

Visual design is a separate step, with mock-ups first. What the screens have to hold:

| Screen | Holds |
|---|---|
| Sign in | The QR code and the short code, or the field for an API key; Add itch on Deck to Steam. |
| Lists | Tabs for Installed, Owned, Collections, My projects, Search. A grid or a list of covers and titles, each with its state (installed, update known, not installable here, draft). |
| Game | Cover, title, short text, uploads, size, install location; Install, Play, Add to Steam (then In Steam, with Remove from Steam), Check for updates, Pin this version, Uninstall. |
| Downloads | What is downloading and waiting, with progress, speed and time left; Cancel. |
| Settings | The schedule and its interval, install locations with free space, bandwidth limit, butler's version, the last update runs, Add itch on Deck to Steam, Sign out. |

Controller: the shoulder buttons change tab, one button opens Search, one opens Downloads; the
rest is focus navigation. Text is entered with Steam's on-screen keyboard **(to verify that it
opens for the app in Gaming Mode)**.

## 10. Technology

Proposed: Godot 4, exported for Linux, as one binary used two ways: with a window for the app,
and with `--headless` for the updater.

- A controller-first interface is what it is made for, and it runs under Gaming Mode's compositor
  like any game.
- The export is self-contained: no runtime to install.
- It is the engine Sands of the Duel is made with.
- Costs: about 70 MB; a QR code needs a small encoder; whether `--headless` starts inside a
  systemd user service with no display has to be tried **(to verify)**. If it does not, the
  updater becomes a separate small program, and section 8 stays as it is.

Considered and not chosen:

| Option | For | Against |
|---|---|---|
| A Decky Loader plugin | Lives in Gaming Mode's own menu; no separate app | Depends on Decky and on its surviving Steam updates; not usable on a plain Linux PC |
| Python with a GUI toolkit | SteamOS has Python | No toolkit there with good controller navigation |
| Rust with an immediate-mode GUI | One small binary | Controller focus navigation is ours to write |

The Steam shortcut for a game points at a small `run-game` script that the app installs. It finds
the app's current butler and runs `butler launch`, so a butler update does not break shortcuts.

## 11. Milestones

| | What | Shows |
|---|---|---|
| **M0** | A script, no interface: start the daemon, sign in with an API key, list the user's projects with the drafts, install Sands of the Duel, push a new build, check for the update and apply it, launch with `butler launch`, and add that game to Steam in both of section 7's ways. | Most of the "to verify" items: that a draft installs for its owner, that an update is patch-sized, how the daemon behaves over stdio, which way of adding to Steam works in Gaming Mode. Also the compatibility test for a new butler version. |
| **M1** | The updater and its systemd units. | Replaces `tools/deck_update.py` on the Deck, with patch-sized downloads. |
| **M2** | The app: sign in with an API key, Installed, My projects, install and uninstall with progress, play. | The whole path for one's own games, with a controller. |
| **M3** | Owned, Collections, Search; the download queue; settings; Add to Steam. | The whole of version 1's lists, and games started from the Steam library. |
| **M4** | Device sign-in; the last "to verify" items. | Version 1. |

## 12. Open questions

1. **Device sign-in needs an OAuth client ID registered for the device grant.** Whether itch.io
   lets a third-party app register one is not known. An API key works without it, so this blocks
   only R2's preferred way.
2. **Hidden commands.** `butler daemon` and `butler launch` can change without notice. Pinning the
   version and running M0's script against each new one is the answer; how often that breaks
   will only show with time.
3. **Windows-only games.** Most of itch.io's catalogue. Either butler's Wine launch, or a Steam
   shortcut mapped to Proton as the itch app writes it. Left for after version 1.
4. **Adding to Steam.** Which of section 7's two ways works in Gaming Mode is not known:
   whether the running Steam takes a `.desktop` file the app writes, and whether an entry written
   to `shortcuts.vdf` while Steam runs is still there after Steam exits. Also open: how a shortcut
   gets its library images, and whether the app can restart Steam itself when a restart is needed.
5. **Sandbox.** butler can run a game in a sandbox (bubblewrap, firejail). Off or on by default,
   and whether it works on SteamOS, is undecided.
6. **Removed SD card.** What butler does with caves whose install location is gone.
7. **Updating the app itself.** Decided: the app is the page `fourlastor/itch-on-deck`, published
   by a GitHub Actions workflow, and updates through butler, under a setting of its own, apart
   from the games' schedule. The update run, which is started from a copy of the app (section
   8), reads the page's uploads, and when the newest build is another version than the copy
   has butler install that build into the folder the app is in (`Install.Queue` with `noCave`,
   then `Install.Perform`), only while the app's window is closed (section 14).
8. **The name.** "itch on Deck" uses itch.io's name. Fine for a personal tool; check their brand
   rules before publishing it.

## 13. What carries over from `tools/deck_update.py`

That script keeps one game at its channel's latest build with `butler fetch` and a systemd user
timer, and ran on a Deck on 2026-10-04.

Seen on the Deck:

- A user timer runs in Gaming Mode, with no desktop and no open terminal.
- A user service's `PATH`, and a shell's, may lack `~/.local/bin`: use absolute paths.
- Two runs at once happen (the timer fired during the first download): a lock is needed.
- `butler fetch` downloads the whole build (about 200 MB for that game) where the patch between
  two builds was under 2 MB. Updating through the daemon is what removes that cost.

Built in and tried only with a stand-in for butler, not yet seen on the Deck:

- A tick missed during sleep is expected to run at wake, before Wi-Fi is back: the run waits for
  the connection rather than fail.
- A download cut short by sleep or a lost connection is removed, and the next run starts again.
- A build a game is running from stays until the game exits.

## 14. What the first build showed

2026-10-04. The app was built in Godot 4.7.2 and run on a Linux PC with Steam, signed in to a
real account, against butler v15.31.0, with the draft project Sands of the Duel as the game.
Only the part "On a Deck" below was tried on a Deck.

### Seen to work

- **The daemon over stdio.** One JSON message per line on standard output, the log on standard
  error. Godot reads the pipe without blocking; no thread is needed.
- **The app fetches butler itself** at its first launch: the archive of the pinned version from
  broth, checked against a SHA-256 the app carries, unpacked, and run once before it is used.
- **A draft installs for its owner**, from My projects.
- **An update is patch-sized.** After going back one build, the update downloaded 5.10 KiB where
  the whole upload is 179.65 MiB.
- **The lock.** While a game started through butler runs, an update of it by a second daemon
  waits until the game exits (the game's folder holds `.itch/runlock.json`). The update run
  therefore looks for a running game itself, in that file and in `/proc`, and skips it (R21).
- **Two daemons on one database** at the same time.
- **The update run under systemd.** The exported binary starts with `--headless` in a user
  service with no display, applies a waiting update and writes it to the journal and to
  `state.json`.
- **`butler launch --cave`**, through the `run-game` script, starts a game with no window of the
  app.
- **Adding to Steam by asking the running Steam** (way 1 of section 7) on a PC: the entry is
  there at once, with no restart. Steam takes the name and the command from the `.desktop`
  file, not the icon and not the folder. The app then reads the ID Steam gave the entry from
  `shortcuts.vdf` and writes the library images into `userdata/<user>/config/grid/`.
- **Removing from Steam by editing `shortcuts.vdf`** (way 2 of section 7) while Steam runs, on a
  PC: the running Steam went on showing the two test entries, and after it was restarted they
  were gone. Steam had not written the file again when it exited.
- **What a running Steam does with its shortcuts file**, tried on a PC with throwaway entries
  (2026-10-04). An entry Steam is asked to add (way 1) is in `shortcuts.vdf` half a second
  later, with the ID Steam chose; the ID cannot be worked out from the entry's fields. Steam
  writes the file again from its own memory every time a shortcut is added through it and
  every time a shortcut is started, and each time whatever was written into the file behind
  its back is gone: an entry added by hand (way 2, which is what Lutris and Heroic do) did not
  survive the next save. So way 2 only holds when Steam is restarted before it saves again,
  and the app, which itself runs as a shortcut, does not add that way. The same goes for the
  removal above: it lasts only if Steam restarts before its next save.
- **Adopting a folder.** `Install.Adopt` makes an existing folder an installed game without
  downloading anything, and that folder then updates like any other. The app first updated
  itself this way: it registered the folder above its own as an install location that the
  lists do not show, and adopted its own folder. It no longer does: adopting reads the game's
  page, which only works for the account that owns the page (see "The app's own update, for
  every account" below). A record made this way by an earlier build is left alone and stays
  out of the lists.

### Not as the sections above had it

- **Search.** butler has no request that searches itch.io. `Search.Games` reads only butler's
  database.
- **The key of `butler login`** may push builds and nothing else: itch.io answers "api key does
  not permit `profile:me`".
- **Partial downloads** are kept in `<install location>/downloads/`.
- **An update's size is not known before it is applied**: the update object names the build,
  not the size of the patch.
- **`LaunchRunning` carries no process ID**, and **going back a build pins the game**.

### Signing in

- **Through a browser.** itch.io's OAuth "implicit" flow with a loopback address: the app opens
  itch.io's permission page, and itch.io sends the browser back to `http://127.0.0.1:34881`,
  where the app listens. It needs only an ordinary OAuth application, which is registered. On a
  PC the default browser is used; in Gaming Mode the app asks for Steam's own browser
  (`steam://openurl/`) **(to verify on a Deck)**.
- **What such a login may do.** itch.io offers third-party applications the scopes `profile`
  and `game:view:uploads` (and a few that do not matter here); the wider `itch` scope is
  refused as "invalid scope". With that key the lists of owned games, projects and collections
  work, and so do installing, updating and launching. Two things are refused: reading one
  game's page, and reading a collection's games. butler reads a game's page again when its copy
  is a few minutes old; the app answers a refusal by fetching again the list the game is in,
  which is allowed and makes butler's copy fresh. A game that is in none of the account's
  lists cannot be reached this way.
- **An API key made on itch.io** (Settings, API keys) is refused nothing.
- **Device sign-in.** itch.io documents it and limits it to approved applications: register an
  OAuth application, write to support with the subject "OAuth application request: QR code
  login (device authorization grant)", and after approval set the application's redirect URI
  to `urn:itchio:poll`. butler's own `Profile.LoginWithDevice` asks for the `itch` scope, so
  the app may have to run the five requests of that flow itself and hand the key to butler.

### On a Deck

2026-10-04, the first published build, started by hand on a Deck.

- **The app started and was added to Steam there.** Whether Steam had to restart to show the
  entry was not noted.
- **A and B did nothing.** Godot's built-in actions for moving the focus (`ui_left` and the
  other three) come with the D-pad and the left stick; `ui_accept` and `ui_cancel` come with
  keyboard keys only. The project's input map now adds the controller's A and B to them
  (`tools/setup_input_map.gd`). Sands of the Duel adds the same two when it starts, and its
  controls work on a Deck.
- **Every screen was then pressed through with a controller**, which had not been done before:
  on a PC, with the presses sent by the screenshot helper (`--pad=`), not yet on the Deck. It
  showed two more things.
  - Godot chooses the control the D-pad moves to by distance alone. The focus walked out of an
    open dialog onto the screen under it, where A then pressed a row; and from the end of a
    section of Settings it jumped into the list of sections. Now the screen under a dialog
    cannot take the focus, and the two columns of Settings are wired by hand: up and down stay
    in a column, right enters a section, left and B leave it.
  - A text field takes Enter by itself but not a controller's A. The filter, the search and the
    field for an API key now hand A to the field.
- **The app's own entry had no library images**, because the app wrote none for itself. They
  are not taken from its itch.io page: an account that does not own the page may not be
  allowed to read it (see Signing in), and the entry should look right with no connection. The
  app draws them itself (the wide and the tall picture, the hero and the logo) when it adds
  the entry, and at its start for an entry that lacks them. An entry of a game gets them at the
  start too, if Steam wrote the entry down too late for them the first time.

- **The update run works under the Deck's timer**: the journal shows it starting every 15
  minutes and ending with "Nothing to update."
- **The app's own update failed**, every run, with butler's "open
  .../itch-on-deck.x86_64: text file busy". Linux does not let a program file be written while
  a program runs from it, and the update run was that program: the timer started it from the
  very file butler then had to replace. It failed whether the window was open or not. Nothing
  was damaged, because butler fails before it changes the file. Reproduced on a PC with the
  same two builds, and fixed: the timer now starts a script that runs the update from a copy
  of the app (section 8). With that, on the PC, the installed app went from one published
  build to the next ("Updated Itch on Deck to 30fbb73."), also through the unit and systemd.
  A run that is started from the app's own file all the same (a unit written by an older
  build, or by hand) skips the app's update and says why, instead of failing. **(to verify on
  the Deck, which needs the fixed build installed by hand once, and then one build more.)**
- **A failed update left its staging folder behind** (a few hundred KiB) in the install
  location's `downloads` folder, because the run ended before butler deleted it. The update
  run and the app now remove such folders at their start.

- **The app did not find its own entry in Steam's file**, so it added itself again at every
  press and never wrote its library images, while a game's entry got its images. The app
  looks for an entry by its program and, for a game, by the cave ID among the launch options.
  For itself it asked for no launch option, as an empty text, and to Godot no text contains
  the empty text. It was not seen before the Deck because, run from the project's sources,
  the app is matched by a launch option (`--path`). Fixed; checked with the exported build
  against a Steam folder laid out like the Deck's. A second press now says that the app is
  in Steam already; when the file does not show the entry but this copy was handed to Steam
  before, the app asks before adding again. The small icon of an entry cannot be set this
  way: Steam takes none from the shortcut it is handed, and what is written into its file is
  lost at its next save (see "What a running Steam does with its shortcuts file").
- **There was no way out of the app with a controller.** B on the first screen (the lists, the
  sign-in, the fetching of butler) now asks whether to close the app.

### Looked into for version 1.1

2026-10-04. Why a sign-in through the browser cannot open a collection or search itch.io, and
what could be done about it. Tried with the browser sign-in of a real account, on a PC; the
`probe key` command asks itch.io for a key through the browser and shows what that key may
read. Nothing of this is built.

- **What itch.io gives a third-party application.** Its OAuth page lists the scopes:
  `profile:me`, `profile:games`, `profile:collections` and `profile:owned` (all four are in
  `profile`), `game:view:ownership`, `game:view:rewards`, `game:view:uploads`, and
  `collection:edit`. `collection:edit` creates and changes collections. Reading a collection's
  games needs `collection:view` and reading a game's page needs `game:view`; neither is on the
  list, and asking for `collection:view` is refused as "invalid scope", the way `itch` was.
- **Collections.** The list of collections and a single collection are allowed; its games are
  refused ("api key does not permit `collection:view`"), and no request that `collection:edit`
  allows gives them back. A collection's page on itch.io can be read with no key at all when the
  collection is public (`https://itch.io/c/<id>/<name>?format=json`, which holds the games as
  the cells of the page) and answers 404 when it is private; the four of the test account are
  private. So after a browser sign-in a public collection could be read from its page, and a
  private one cannot be read by any means, until itch.io offers `collection:view` to
  third-party applications. A sign-in with an API key reads both.
- **Search.** The API has `/search/games`, and a browser sign-in may call it: asked for "moon"
  with such a key, it gave 28 games back. butler never calls it (its `Search.Games` reads its
  own database), so the app has to make the request itself, and for that it has to keep the
  key, which today it hands to butler and forgets. A login made before the app keeps the key
  has to be made once more. There are also pages that answer with no key at all
  (`https://itch.io/autocomplete?query=`, up to five games as JSON, and
  `https://itch.io/search?q=`, 54 a page as cells), but neither is a documented API and
  `robots.txt` asks crawlers to stay out of `/search`; with the API open they are not needed.
- **Installing a game that is in none of the account's lists** is what makes either worth
  doing, and it works. `Install.GetUploads` and `Install.Plan`, which the app uses, make butler
  read the game's page, which is refused. `Fetch.GameUploads`, `Install.PlanUpload` and
  `Install.Queue` do not: `Install.Queue` takes the game as the caller describes it. Tried on a
  free game the account does not own, described by hand (ID, address, title; `probe unlisted`):
  the uploads were listed, the install was planned, and the game was downloaded and installed
  (83 MB); the check for updates took it like any other, butler started it, and it was
  uninstalled again. A paid game the account does not own answers with no uploads. The same
  three requests serve the games the account does hold (tried on the account's own project
  with butler's copies made stale), and would make the refetching of lists described under
  Signing in unnecessary.
- **The app's own update had the same fault.** `Install.Adopt` reads the game's page too. For
  the account that owns the page the app got around it through the list of projects; an
  account that does not own it has no list to fetch, so it could not hand its folder to
  butler. Making the page public changes nothing: the refusal is about the key, not about who
  may see the page.

### The app's own update, for every account

2026-10-04, on a PC, with the page's published builds and a scratch copy of the app.

- **How.** The app does not have butler hold its folder as an installed game. It reads the
  page's uploads (`Fetch.GameUploads`, allowed to every sign-in) and compares the newest
  build's version with its own, which is the commit the build was made from. When they
  differ, the update run has butler install that build into the folder the app is in:
  `Install.Queue` with `noCave`, the folder, a staging folder under the app's cache and the
  game described by the app, then `Install.Perform`. None of this reads the game's page.
- **The first update of a copy unpacked by hand** finds no record from butler in the folder,
  so butler fetches the whole build (28 MiB) and writes its record (`.itch/receipt.json.gz`).
  Tried: a copy that called itself another version became the newest published build, through
  the timer's launcher.
- **Every update after that is a patch.** Tried on the same folder, put back one build:
  butler's log says "Upgrading from build 2065197 to 2066303", one patch of 215 KiB against a
  full upload of 28 MiB.
- **What it no longer needs**: the copy being the page's newest build before the switch can be
  turned on, and the folder above the app registered as an install location.
- **The run says how an update arrived**, for the app and for games, after "Updated ...":
  "(1 patch, 295.59 KiB)", "(the whole build, 28.34 MiB)" or "(repaired from the build)". It
  reads that off butler's own log lines, which the daemon sends along while it works; once an
  update is done butler's log of it is deleted, so nothing else would tell afterwards.
- **On the Deck (2026-10-04, 23:39)** the app went from `7748e9b` to `d7687bd` by itself, under
  the timer, and an earlier run left it alone because the app was open. That update was still
  done by the old code. **(to verify: an update done by this code on a Deck, and with an
  account that does not own the page.)**

### Still to verify

- On a Deck: the controller after the changes above, Steam's on-screen keyboard, Steam's
  browser for the sign-in, adding a game to Steam, and whether a new entry and its images show
  without restarting Steam. (The app's own entry does show its images on the Deck now.)
- Whether an entry *added* to `shortcuts.vdf` while Steam runs is still there after Steam exits.
  The app does not add that way, so this only matters if way 1 of section 7 fails on a Deck.
- The app's own update on a Deck, and with an account that does not own the page.
- The lists and the update run with no connection, and a download across a sleep.
- Sign-in with a hand-made API key (the same request the browser sign-in ends with).
