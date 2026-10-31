# Resolution Swapper for KDE Plasma

A small Plasma 6 widget that switches your **main monitor** between two
resolutions from the panel, the system tray or a keyboard shortcut, without
opening System Settings.

It is the Linux counterpart of the Windows tray app
[ResolutionSwapper](https://github.com/Unackn0wledged/ResolutionSwapper). The
setup it was built for is a `3440x1440` ultrawide that sometimes needs to run at
`2560x1440` for applications that don't handle 21:9 well. Other monitors are left
alone.

## Features

- Pick a resolution in the popup, or from the widget's right-click menu.
- **Swap with one action**: middle-click the widget, or give it a keyboard
  shortcut.
- Shows the current resolution in the tooltip, and optionally in the panel.
- Always targets the monitor Plasma treats as **primary**, so there is nothing to
  update if your setup changes.
- Uses the highest refresh rate available at the target resolution.
- **Adds missing resolutions for you** as custom modes, and undoes them
  automatically if you can't confirm the picture (see below).
- Monitors to the right of or below the main one move with it, so no gap opens up
  between the screens.
- Notices changes made elsewhere, such as in System Settings.

## Requirements

- KDE Plasma 6 on Wayland. Custom modes need a recent Plasma; this was built on 6.8.
- `kscreen-doctor`, which comes with Plasma in the `libkscreen` package.

## Installation

```bash
git clone https://github.com/Unackn0wledged/ResolutionSwapper-Plasma.git
cd ResolutionSwapper-Plasma
./install.sh
```

Then right-click your panel, choose **Add Widgets…** and drag **Resolution
Swapper** to the panel or the desktop. To keep it in the system tray instead,
enable it under **Configure System Tray… → Entries**.

To update, run `git pull` and `./install.sh` again, then restart Plasma with
`systemctl --user restart plasma-plasmashell`.

To remove it:

```bash
kpackagetool6 --type Plasma/Applet --remove com.github.unackn0wledged.resolutionswapper
```

## Usage

| Action | Result |
|---|---|
| Left click | Open or close the popup |
| Middle click | Swap to the other resolution |
| Right click | Menu with the current mode and both resolutions |
| Keyboard shortcut | Swap to the other resolution |

To set a shortcut, open **Configure Resolution Swapper… → Keyboard Shortcuts**.

As in the Windows app, swapping goes to the second resolution when the first is
active, and to the first one otherwise.

### Settings

Under **Configure Resolution Swapper… → General** you can change:

- the name and resolution of both presets
- the refresh rate used when adding a custom mode
- whether the panel shows the current resolution
- whether a left click swaps instead of opening the popup
- whether a notification appears after switching

Errors always show a notification.

## Custom modes

Linux only lists the modes in the monitor's EDID, which is often shorter than the
list Windows shows. Many ultrawides don't report `2560x1440` at all. When a preset
is missing, its row says so and has an **Add** button.

**Add** creates a custom mode in KWin and switches to it for a 15 second trial:

- Choose **Keep** and the mode stays, including after a reboot.
- Choose **Go back**, or do nothing, and the widget returns to the previous mode
  and removes the custom one.

The timeout matters because a monitor that rejects a mode goes black, and the
widget may be on that monitor. If it does, wait for it to come back, lower
**Refresh rate** in the settings and try again.

Custom modes use reduced blanking. To remove one you kept, list them with
`kscreen-doctor -o`, then remove it by its index:

```bash
kscreen-doctor output.DP-2.removeCustomMode.0
```

### NVIDIA

**Add** can't work with NVIDIA's driver, at any refresh rate. The driver only
accepts modes listed in the monitor's EDID, so KWin gets
`The driver rejected the output configuration` and the widget removes the mode
again. The monitor isn't the problem, and lowering the refresh rate won't help.

The way around this is to add the resolution to the EDID the driver sees. This
worked on a 34" LG UltraGear with driver 615.78, but it depends on the monitor
accepting a resolution it never advertised.

`tools/add-edid-mode.py` writes a copy of your EDID with the new resolution added.
It only reads the monitor and needs no root. It needs `edid-decode`, and it requires
a resolution with the same height as a mode the monitor already has:

```bash
mkdir -p edid
./tools/add-edid-mode.py DP-2 2560x1440 edid/DP-2.bin
```

The generated file contains your monitor's serial number. `*.bin` is ignored by
git here, so keep it that way if you share the folder.

To try it, load the file as a temporary override. This lasts until the next reboot,
so a reboot undoes it:

```bash
sudo sh -c 'd=$(ls -d /sys/kernel/debug/dri/*/DP-2 | head -1); [ -n "$d" ] && cat edid/DP-2.bin > "$d/edid_override" && echo detect > /sys/class/drm/card*-DP-2/status'
```

KWin doesn't rescan a connector that's already running, so make it pick up the new
modes by turning the monitor off and on, or by logging out and back in.

Modes added this way count as normal modes, so the widget switches to them directly,
without a 15 second trial. If the picture is black, use the widget or
`kscreen-doctor` from another monitor to switch back, then reboot to clear the
override.

An EDID override has been reported to disable HDR or VRR on some setups. Both stayed
available on the LG above, but check yours if you use them.

To keep the override after a reboot, install it as a boot service:

```bash
sudo tools/install-edid-override.sh DP-2 edid/DP-2.bin
```

This copies the EDID to `/etc/resolution-swapper` and leaves the kernel command line
and initramfs alone. If the service fails, the monitor simply uses its normal EDID.
It also skips the override if a different monitor is on that connector.

To remove it, run this and reboot:

```bash
sudo tools/install-edid-override.sh --remove DP-2
```

## How it works

The widget is plain QML with no compiled code. It reads the setup from
`kscreen-doctor -j`, picks the enabled output with the lowest priority number, and
applies modes with `kscreen-doctor output.<name>.mode.<id>`. KWin saves the result
like any other display change, so it survives a reboot.

`kscreen-doctor` exits with 0 even when it rejects a mode, so the widget reads the
setup back to confirm each switch.

[`package/contents/code/logic.js`](package/contents/code/logic.js) holds the
parsing and command building, and
[`package/contents/ui/main.qml`](package/contents/ui/main.qml) holds the switching
and the custom mode trial.

## Tests

The logic has unit tests. The `qmltestrunner` on your `PATH` may be the Qt 5 one,
so use the Qt 6 binary:

```bash
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
```

## Troubleshooting

**The widget doesn't appear in Add Widgets.** Restart Plasma with
`systemctl --user restart plasma-plasmashell`.

**"Could not read the monitor setup".** Check that `kscreen-doctor -j` works in a
terminal. If the command is missing, install `libkscreen`.

**"The graphics driver refused" a custom mode.** See [NVIDIA](#nvidia).

**The monitor went black after adding a mode.** Wait for the trial to end, which
takes at most 15 seconds. The monitor doesn't support that mode, so try a lower
refresh rate.

**Windows moved after switching.** KWin rearranges windows when a monitor changes
size. This isn't specific to the widget.

**The image is stretched to fill the monitor, or looks soft.** Scaling at non-native
resolutions is done by the monitor. With the resolution active, look for an aspect
ratio option in its on-screen menu. On an LG ultrawide, setting **Ratio** to
**Original** gives a sharp 16:9 picture with black bars.

## License

[MIT](LICENSE)
