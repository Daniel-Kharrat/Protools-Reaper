# Daniel_Open Pro Tools session

A REAPER extension that opens **Pro Tools sessions (`.ptx`)** directly in REAPER.

Choose **File > Open project**, select a `.ptx` file, and REAPER opens it as a REAPER project. Your tracks, clips, fades, routing, automation, plug-in slots and mixer settings come with it.

The Pro Tools session file is never changed.

---

## Contents

- [Features at a glance](#features-at-a-glance)
- [Installation](#installation)
- [How to use it](#how-to-use-it)
- [What is converted](#what-is-converted)
- [Plug-ins](#plug-ins)
- [Differences between Pro Tools and REAPER](#differences-between-pro-tools-and-reaper)
- [What is not converted](#what-is-not-converted)
- [Compatibility](#compatibility)
- [Files that the extension writes](#files-that-the-extension-writes)
- [Building from source](#building-from-source)
- [Credits](#credits)

---

## Features at a glance

- Opens `.ptx` files from **File > Open project**, like any REAPER project.
- No Pro Tools needed. No other software or scripts needed.
- Works on **macOS, Windows and Linux**.
- Converts tracks, clips, fades, clip gain, MIDI, sends, buses, groups, VCAs, automation, tempo, markers, track colours and more.
- Avid EQ3 and Dyn3 plug-ins become REAPER stock plug-ins with the same settings. Every other plug-in keeps its slot as a named placeholder.
- Writes a **conversion report** that lists what was converted and what needs a check.

---

## Installation

1. Download the file for your system:

   | System | File |
   |---|---|
   | macOS (Apple Silicon and Intel) | `reaper_daniel_open_protools_session.dylib` |
   | Windows (64-bit) | `reaper_daniel_open_protools_session-x64.dll` |
   | Linux (x86_64) | `reaper_daniel_open_protools_session-x86_64.so` |

2. Put the file in REAPER's `UserPlugins` folder:

   | System | Folder |
   |---|---|
   | macOS | `~/Library/Application Support/REAPER/UserPlugins` |
   | Windows | `%APPDATA%\REAPER\UserPlugins` |
   | Linux | `~/.config/REAPER/UserPlugins` |

   You can also open this folder from REAPER: **Options > Show REAPER resource path**, then open `UserPlugins`.

3. Restart REAPER.

> **Tip:** Keep the `.ptx` in its Pro Tools session folder, next to the `Audio Files` folder. REAPER then finds the audio.

---

## How to use it

1. In REAPER, choose **File > Open project**.
2. Select the `.ptx` file. Pro Tools sessions now show in the file list.
3. The session is converted and opens as a REAPER project.
4. When the conversion is finished, a short message tells you:
   - how many plug-ins have no REAPER version (placeholders)
   - any warnings, in plain words
   - the name of the conversion report

### If the project already exists

If you open the same `.ptx` again, a REAPER project with that name already exists. The extension asks you what to do:

| Button | Result |
|---|---|
| **Yes** (default) | Keeps the old project. The new one is saved as `Session (2).rpp`, `Session (3).rpp` and so on. |
| **No** | Overwrites the old project and its report. |
| **Cancel** | Opens nothing. |

**Yes** is the default, so a quick Enter never deletes your work.

---

## What is converted

### Session

| Pro Tools | REAPER |
|---|---|
| Sample rate | Project sample rate |
| Session start (for example 01:00:00:00) | Project start time |
| Timecode rate (23.976, 24, 25, 29.97, 29.97 drop, 30, 30 drop) | Project frame rate |
| Tempo and meter changes | Tempo map |
| Markers and memory locations | Markers and regions |
| Track comments | Project notes, and SWS track notes (if SWS is installed) |

### Tracks and mixer

| Pro Tools | REAPER |
|---|---|
| Audio, aux, MIDI, instrument, VCA and video tracks | Tracks in the same order |
| Track names and colours (exact Pro Tools colours) | Track names and colours |
| Volume, pan and mute | Volume, pan and mute |
| Stereo tracks with two pan knobs | Dual pan (normal pan when the knobs are at hard left and right) |
| Solo | Solo |
| Solo safe | Solo defeat |
| Hidden tracks | Hidden in the arrange view and the mixer |
| Inactive tracks | Muted, with the FX chain off |
| Master fader volume and inserts | Master volume and master FX chain |

### Routing

| Pro Tools | REAPER |
|---|---|
| Track output to a bus that an aux track uses as its input | Send to that aux track (the master send is off) |
| Sends, with level, pan and mute | Sends, with level, pan and mute |
| Pre-fader and post-fader sends | Pre-fader and post-fader sends |
| Send to a bus that no aux track uses | A new, silent track with the bus name receives these sends (see [Buses with no aux track](#buses-with-no-aux-track)) |

### Clips and editing

| Pro Tools | REAPER |
|---|---|
| Clips (position, length, start offset) | Items |
| Clip names | Take names |
| Muted clips | Muted items |
| Fade-ins and fade-outs, with their shape and curve amount | Item fades, with their shape and curvature |
| Crossfades (equal power, equal gain, or no link) | Overlapping items with matching fades |
| Clip gain | Take volume |
| Clip gain lines | Take volume envelopes |
| Sync points | Snap offsets |
| Clip groups | Item groups |
| Clip loops | Looped items |
| Overlapping clips | Trimmed, so only the front clip plays, as in Pro Tools |
| Alternate playlists | Fixed item lanes (only the main playlist plays) |
| Elastic Audio | Playrate, and stretch markers for warp markers |
| Split-stereo clips (`.L` and `.R` files) | One item with two takes that play together (see [Split-stereo clips](#split-stereo-clips)) |
| Video track clip | Video item (file from the `Video Files` folder) |

### Automation

| Pro Tools | REAPER |
|---|---|
| Volume, pan and mute automation | Track envelopes |
| Volume trim automation | Trim volume envelope |
| Send level, pan and mute automation | Send envelopes |
| VCA fader automation | Volume envelope on the VCA leader |
| Plug-in automation (see [Plug-ins](#plug-ins)) | FX parameter envelopes |
| Plug-in Master Bypass automation | FX bypass envelope |

### Groups and VCAs

| Pro Tools | REAPER |
|---|---|
| Mix groups | Track groups that link volume, mute and solo |
| Edit groups | Track groups that link media edits |
| Edit and Mix groups | Both of the above |
| Inactive groups | Group name only, nothing linked |
| VCA master tracks | VCA leader, with the group members as VCA followers |

REAPER has 32 track groups. If a session has more groups, only the first 32 are converted.

### MIDI

| Pro Tools | REAPER |
|---|---|
| MIDI clips | MIDI items |
| Notes (pitch, velocity, length) | Notes |
| Controllers (CC) | CC events |
| Pitch bend | Pitch bend |
| Program change | Program change |

---

## Plug-ins

Every Pro Tools insert keeps its **slot**, in the same order:

- **Avid stock plug-ins** below become REAPER stock plug-ins with the same settings.
- **Every other plug-in** becomes a placeholder with the Pro Tools plug-in name. The placeholder passes audio through unchanged. Replace it with the real plug-in.
- **Bypassed** inserts are bypassed in REAPER.
- **Inactive** inserts are set offline in REAPER.

Plug-in values are rounded, so REAPER shows clean numbers (1 Hz, 0.1 dB and so on).

### Converted plug-ins

| Pro Tools | REAPER | Settings | Automation |
|---|---|---|---|
| EQ3 7-Band | ReaEQ | All bands: type, frequency, gain, Q, on/off. High-pass and low-pass filters. Output gain. | Band gain, frequency and Q |
| EQ3 1-Band | ReaEQ | Filter type, frequency, gain, Q, output gain | Gain |
| Dyn3 Compressor/Limiter | ReaComp | Threshold, ratio, attack, release, knee, gain, side-chain filters | Threshold, ratio, attack, release, gain, knee |
| Dyn3 Expander/Gate, ratio 20:1 and up | ReaGate | Threshold, attack, hold, release, range, side-chain filters | Threshold, range, attack, hold, release |
| Dyn3 Expander/Gate, ratio under 20:1 | JS: Auto Expander | Threshold, ratio | Threshold |
| Dyn3 De-Esser | JS: De-Esser | Frequency | Frequency |

### Known limits of the converted plug-ins

- **EQ3:** ReaEQ has no 6 dB/oct or 18 dB/oct filters, so the next steeper slope is used. Input gain is added to the ReaEQ output gain. Shelves and pass filters can be a little different from Pro Tools.
- **Dyn3 Compressor:** ReaComp is set to peak detection, as Dyn3 detects peaks.
- **De-Esser:** the REAPER De-Esser has threshold and ratio, not range. Set the threshold by ear.
- **Expander:** the Auto Expander has no range, attack, hold or release. Its ratio works a little differently.
- **Automation with no REAPER target:** EQ high-pass and low-pass frequency, input and output level, De-Esser range.

Each of these shows in the conversion report, on the plug-in it applies to.

---

## Differences between Pro Tools and REAPER

Pro Tools and REAPER do some things differently. This is how the extension handles each difference.

### Split-stereo clips

Pro Tools can play a stereo clip from two mono files (`.L` and `.R`). A REAPER take plays one file, so each clip becomes **one item with two takes**:

- the L file, panned hard left
- the R file, panned hard right
- "Play all takes" is on, so both play at the same time

You move and cut it as one item. No new audio files are made.

### Buses with no aux track

In Pro Tools you can send audio to a bus that no aux track uses as its input. You hear nothing from that bus.

To keep this routing, the extension makes a new track with the bus name. It receives all the sends to that bus. The track has:

- no input
- no colour
- volume at -inf
- no master send

It is silent, as in Pro Tools. To hear it, raise its volume and turn on its master send. The end message and the report list each of these tracks.

### Other differences

| Pro Tools | REAPER |
|---|---|
| Master fader inserts are post-fader | Master FX are pre-fader |
| Inactive tracks | REAPER has no inactive tracks: the track is muted and its FX chain is off |
| 30 drop frame | REAPER has no 30 drop: 30 fps is used |
| More than one master fader | REAPER has one master: only the first master fader's inserts are converted |

---

## What is not converted

- Settings of third-party and other non-Avid plug-ins (they become placeholders)
- Virtual instruments: put an instrument on each MIDI or instrument track
- Side-chain key inputs
- Surround tracks (5.1 and up): only the first 2 channels are converted
- Track heights and window layout
- Group attributes other than volume, mute, solo and media edits
- Sessions from Pro Tools 5 and 6 on old PowerPC Macs

---

## Compatibility

| | |
|---|---|
| REAPER | 7 or newer (fixed item lanes need REAPER 7) |
| macOS | 10.15 or newer, Apple Silicon and Intel |
| Windows | 64-bit |
| Linux | x86_64, glibc 2.17 or newer |
| Pro Tools sessions | `.ptx` from Pro Tools 10 and newer. Tested with Pro Tools 12.5 (Windows) and 2021.7 (macOS). |
| SWS (optional) | Needed only for track notes from Pro Tools track comments |

The Pro Tools session format is not public. If a session from another Pro Tools version does not convert correctly, please open an issue and add the conversion report.

---

## Files that the extension writes

| File | Where | What |
|---|---|---|
| `Session.rpp` | Next to the `.ptx` | The converted REAPER project |
| `Session - conversion report.txt` | Next to the `.ptx` | What was converted, what was not, and what needs a check |
| `Daniel_Pro Tools plug-in placeholder.jsfx` | `REAPER/Effects/Daniel Kharrat/ProTools Effects/` | The placeholder for plug-ins that have no REAPER version |

The `.ptx` file and the audio files are never changed.

### The conversion report

The report has these parts:

- **Converted:** counts of tracks, items, fades, sends, markers, plug-ins and so on
- **Not converted:** what the extension cannot convert
- **Warnings:** things that need your attention
- **Stock plug-ins:** each converted plug-in with its settings. Lines that start with `!` need a check.
- **Groups, VCAs and track states**
- **Muted clips:** check that these are muted in Pro Tools too
- **Audio files outside the session folder**
- **Tracks:** each track with its volume, pan, output, sends and inserts

---

## Building from source

Everything that the build needs is in this repository. Nothing is downloaded.

| Folder or file | What |
|---|---|
| `src/main.cpp` | The extension |
| `src/Daniel_Open Pro Tools session.lua` | The converter. It is built into the extension. |
| `deps/lua` | Lua 5.4 |
| `deps/reaper-sdk` | REAPER SDK headers |
| `tests/` | Test tools that compare the extension output with the converter output |

**macOS** (needs the Xcode Command Line Tools):

```sh
./build-mac.sh
```

This builds the `.dylib` for Apple Silicon and Intel and installs it in REAPER's `UserPlugins` folder.

**Linux and Windows** (on Linux, needs `gcc`, `xxd` and MinGW for Windows; `zig` is optional, for older Linux systems):

```sh
./build.sh          # both
./build.sh linux    # .so only
./build.sh windows  # .dll only
```

To change the converter, edit only `src/Daniel_Open Pro Tools session.lua`, then build again.

---

## Credits

- **Daniel Kharrat**: extension, converter, and analysis of Pro Tools sessions.
- **ptformat** by Damien Zammit (LGPL): the session decryption and basic block layout come from this open-source project.
- **Lua 5.4** (MIT licence), Copyright © 1994–2024 Lua.org, PUC-Rio.
- **REAPER SDK** by Cockos.

Pro Tools, EQ3 and Dyn3 are trademarks of Avid Technology. This project is not made by, or connected with, Avid or Cockos.

If this extension saves you time, you can support it on [Ko-fi](https://ko-fi.com/danielkharrat).
