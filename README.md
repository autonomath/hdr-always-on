# hdr-always-on

Keep HDR switched on for your external displays on macOS. A small background helper turns HDR back on when macOS drops it after sleep, unlock, or reconnecting a display.

## How it works

The helper uses the same private macOS functions as the High Dynamic Range switch in System Settings > Displays. It checks your external displays:

- a few seconds after the Mac wakes, the screen unlocks, or a display connects or changes mode
- every 15 minutes as a backup

When HDR is off, it turns HDR on only if macOS reports that the display can use it right now, then checks again a few seconds later to confirm. If HDR still doesn't come on, the helper waits for the next wake or reconnect, or 15 minutes, before trying again, so a display never flickers in a retry loop.

There are no dependencies. The installer adds one small universal binary (Apple silicon and Intel) and a LaunchAgent, and the helper uses no CPU between checks.

## Install

### Option 1: One-liner (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/autonomath/hdr-always-on/main/install.sh | bash
```

### Option 2: Download the .pkg installer

Download the latest `.pkg` from the [Releases](https://github.com/autonomath/hdr-always-on/releases) page and double-click to install. No Terminal required.

### Option 3: Git clone

```bash
git clone https://github.com/autonomath/hdr-always-on.git
cd hdr-always-on
bash install.sh
```

Installing replaces the older script version (`enable-hdr.sh`) if you have it.

## Leave a display alone

Some TVs only accept HDR at 4K 60 Hz over HDMI with reduced color detail (4:2:2 or 4:2:0), which makes small colored text look blurry. To keep a display in SDR, exclude it:

```bash
~/.local/bin/hdr-always-on list
~/.local/bin/hdr-always-on exclude "SAMSUNG"
```

Use the display's name or the identifier shown by `list`. To manage the display again, run `~/.local/bin/hdr-always-on include "SAMSUNG"`. Exclusions live in `~/.config/hdr-always-on/exclude.txt` and apply from the next check, without a restart.

## Commands

```
hdr-always-on list               Show external displays and their HDR state
hdr-always-on once               Check now and turn HDR on where it's off
hdr-always-on exclude DISPLAY    Leave a display alone
hdr-always-on include DISPLAY    Manage a previously excluded display again
```

## Logs

The log records changes only: HDR turned back on, a display macOS won't use HDR on, or an attempt that didn't work.

```bash
tail -f ~/Library/Logs/hdr-always-on.log
```

## Troubleshooting

**"macOS isn't offering HDR for this display in its current mode."** macOS doesn't currently show the High Dynamic Range switch for that display, so there's nothing to turn on. Check System Settings > Displays. On a TV, turn on the setting that unlocks full HDMI bandwidth for that input (Samsung: Input Signal Plus, or HDMI UHD Color on older models), and use a cable rated for 4K 60 Hz HDR.

**HDR comes back after you switch it off.** That's the helper doing its job. Exclude the display or uninstall.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/autonomath/hdr-always-on/main/uninstall.sh | bash
```

This also removes the older script version.

## Building from source

Requires Xcode or the Command Line Tools.

```bash
./build.sh        # builds bin/hdr-always-on from src/main.swift
bash install.sh   # installs the binary from this folder
```

`bin/hdr-always-on` is committed so the one-line installer works without developer tools. Rebuild it whenever `src/main.swift` changes. `pkg/build-pkg.sh` builds the `.pkg` installer.

## Technical details

The helper looks up three private functions at runtime in CoreDisplay, falling back to SkyLight's `SLSDisplay…` equivalents:

- `CoreDisplay_Display_SupportsHDRMode(displayID)` checks whether macOS offers HDR for the display right now
- `CoreDisplay_Display_IsHDRModeEnabled(displayID)` checks whether HDR is on
- `CoreDisplay_Display_SetHDRModeEnabled(displayID, true)` turns it on

It skips built-in displays and identifies the others by vendor, model, and serial number, which stay the same across reconnects.

## Compatibility

- **macOS**: 11 or later. Tested on macOS 27.2 on Apple silicon.
- **Displays**: Any external display that macOS offers HDR for.
- **Apple silicon and Intel**: The binary is universal.

## Caveats

- Uses **private APIs** that Apple could change or remove. If they disappear, the helper logs that and stops.
- While the helper runs, switching HDR off in System Settings won't stick unless you exclude the display.

## License

MIT
