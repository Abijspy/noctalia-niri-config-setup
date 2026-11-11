# noctalia-niri-config-setup

Ready-made configs and an installer for the [Noctalia v5](https://docs.noctalia.dev/noctalia/) shell, on every compositor Noctalia supports (**niri, Hyprland, Sway, Scroll, Mango, Labwc, Umbriel and KDE Plasma**) and every distribution Noctalia packages for (**Arch, Fedora, openSUSE, Debian/Ubuntu, Void, Alpine Edge, Chimera, Gentoo and Solus**). The installer uses Noctalia's own colors, and on Arch it can install the **yay** or **paru** AUR helper.

![The installer's welcome screen](docs/screenshots/welcome.png)

## Quick install

Works on a **fresh minimal install**, straight from the TTY and even as root:

```bash
curl -fsSL https://raw.githubusercontent.com/Abijspy/noctalia-niri-config-setup/main/install.sh | bash
```

Or from a clone:

```bash
git clone https://github.com/Abijspy/noctalia-niri-config-setup.git
cd noctalia-niri-config-setup
./install.sh
```

## The installer

The installer is a full-screen terminal UI written in plain bash, so it needs nothing extra on a minimal install. It uses the colors of Noctalia's built-in palette: navy surface, yellow primary, lavender secondary and mint accents. On a bare Linux console it temporarily switches the console to the Noctalia palette and uses symbols the console font can draw. The original palette comes back when the installer exits.

| | |
|---|---|
| ![Choosing compositors](docs/screenshots/desktop.png) | ![Choosing an AUR helper](docs/screenshots/aur.png) |
| **Desktop:** pick one or more compositors | **AUR helper:** paru, yay, an installed one, or none |
| ![Choosing extras](docs/screenshots/components.png) | ![Choosing a terminal](docs/screenshots/apps.png) |
| **Extras:** greeter, type-to-launch, polkit agent, apps | **Apps:** terminal, file manager and browser |
| ![Review screen](docs/screenshots/review.png) | ![Installing](docs/screenshots/installing.png) |
| **Review:** nothing changes until you choose *Install now* | **Install:** live steps, progress bar and the latest log lines |

![Finished screen](docs/screenshots/done.png)

On a minimal install, straight from the TTY:

![The installer on the Linux console](docs/screenshots/tty.png)

On other distributions, compositors your distribution doesn't package are greyed out, with the reason:

![Compositor list on Void Linux](docs/screenshots/distro.png)

<sub>Screenshots are rendered from a test run, so the install log shows placeholder package names.</sub>

**Controls**

| Key | Action |
|---|---|
| `↑` / `↓` | Move between options (`Home` / `End` jump to the first / last) |
| `Enter` | Continue (picks the highlighted option) |
| `Space` | Tick or untick an item on the Desktop and Extras screens |
| `Backspace` or `←` | Go back to the previous page. In a text field, Backspace deletes first and goes back once the field is empty |
| `Esc` | Quit the installer. Nothing changes before you choose *Install now* |

**Screens**

1. **Welcome:** shows whether it found a laptop and an existing login manager.
2. **User:** only when run as root. Pick an existing user or create a new one. A new user is added to `wheel`, and `sudo` is installed and enabled for that group.
3. **Desktop:** choose one or more compositors. Press Enter to take the highlighted one, or tick several with Space first. Each one gets its own config, and with Noctalia Greeter you pick between them at login.
4. **Extras:** Noctalia Greeter, overview type-to-launch, Noctalia's polkit agent, file manager and browser, and the lid-close lock (laptops only, and only with niri, Sway or Scroll). Then the **AUR helper**:
   - keep yay or paru if one is already installed, install **paru** or **yay**, or skip it;
   - Scroll and Umbriel are only in the AUR, so they need a helper.
5. **Apps:** terminal (alacritty, kitty, foot, ghostty or wezterm), file manager (nautilus, thunar, dolphin, nemo or none) and browser (firefox, chromium or none). The keybinds in every config are updated to match.
6. **Keyboard:** the layout is written into each compositor's config, e.g. `us` or `us,de`.
7. **Review:** if gdm, sddm or lightdm is active, it first asks whether to replace it with greetd. Then you can install, go back and change your choices, or quit.
8. **Install:** each step is shown as it runs, with a progress bar and the latest log lines. Keys are ignored during this step so it can't be stopped halfway.
9. **Done:** the main keybinds, any notes, and an offer to reboot.

If something fails, the installer shows the last lines of the log. The full log is at `/tmp/noctalia-niri-install.log`.

## Distributions

The installer reads `/etc/os-release`, adds Noctalia's repository the way [Noctalia's install guide](https://docs.noctalia.dev/noctalia/getting-started/installation/) describes, and installs everything with your distribution's package manager.

| Distribution | Package manager | Noctalia comes from | Noctalia Greeter |
|---|---|---|---|
| Arch Linux and derivatives (CachyOS, EndeavourOS, Manjaro…) | `pacman` (+ yay/paru for the AUR) | `[extra]` | yes |
| Fedora 44+ | `dnf` | Fedora; Terra for the greeter and Umbriel | yes |
| openSUSE Tumbleweed, Slowroll, Leap 16 | `zypper` | openSUSE; OBS `home:neifua:Noctalia` for Umbriel | Tumbleweed / Slowroll |
| Debian 13, Debian sid, Ubuntu 26.04 / 26.10 and derivatives | `apt` | Noctalia's APT repository (amd64 / arm64) | yes |
| Void Linux | `xbps` | UniversalRepository | — |
| Alpine Edge | `apk` | UniversalRepository | — |
| Chimera Linux | `apk` | Chimera's user repository | — |
| Gentoo | `emerge` | GURU overlay | — |
| Solus | `eopkg` | Solus | — |
| NixOS, Guix, anything else | — | **configs only** | — |

- **Package checks:** before installing, each package is looked up with your package manager.
  - A compositor your distribution doesn't package can't be picked.
  - A missing optional package (a font, a portal) is skipped and listed at the end.
  - If Noctalia or a chosen compositor can't be found, the installer stops before installing anything.
- **Configs only:** on NixOS, Guix, other distributions, and releases Noctalia doesn't package for (e.g. Debian 12, Fedora 43, Alpine stable), the installer writes the compositor and Noctalia configs and tells you what to install yourself.
- **Only on Arch:** the AUR (Scroll, `umbriel-git`, yay/paru) and the `pacman -Syu` system upgrade.
- **Greeter and lid lock:** these need systemd. The greeter is offered only where it's packaged.
- **Run as root on doas-only systems:** when there's no sudo (common on Alpine and Chimera), run the installer as root, e.g. `doas ./install.sh`.

## Compositors

| Compositor | Package (Arch) | Config written | Start from a TTY |
|---|---|---|---|
| niri | `niri` | `~/.config/niri/config.kdl` | `niri-session` |
| Hyprland | `hyprland` | `~/.config/hypr/hyprland.lua` | `Hyprland` |
| Sway | `sway` | `~/.config/sway/config` | `sway` |
| Scroll | `sway-scroll` (AUR) | `~/.config/scroll/config` | `scroll` |
| Mango | `mangowm` | `~/.config/mango/config.conf` | `mango` |
| Labwc | `labwc` | `~/.config/labwc/rc.xml`, `autostart`, `environment` | `labwc` |
| Umbriel | `umbriel-git` (AUR) | `~/.config/umbriel/config.toml` | `umbriel` |
| KDE Plasma | `plasma-desktop` | `~/.config/autostart/noctalia.desktop` | `startplasma-wayland` |

Every config starts Noctalia, includes the Noctalia settings from its [compositor page](https://docs.noctalia.dev/noctalia/compositor-settings/niri/), and shares the same main keys where the compositor allows it:

| Keys | Action |
|---|---|
| `Mod+Space` | Noctalia launcher |
| `Mod+S` | Control center |
| `Mod+,` (`Mod+Shift+,` on niri) | Noctalia settings |
| `Mod+Return` / `Mod+E` / `Mod+B` | Terminal / file manager / browser |
| `Mod+Q` | Close window |
| `Mod+1`…`9`, `Mod+Shift+1`…`9` | Go to / move to workspace |
| Volume and brightness keys | Noctalia's volume and brightness controls |

What to know about each one:

- **niri:** blur everywhere and a blurred overview wallpaper. Needs a niri build with `background-effect` / `blur` support.
- **Hyprland:** uses Hyprland's Lua config (`hyprland.lua`), the format Noctalia documents. An existing `hyprland.conf` is moved aside to a dated backup.
- **Sway / Scroll:** the same config, with Scroll reading its own `config.d` folder. Sway and Scroll can't blur Noctalia's surfaces.
- **Mango:** window blur on, layer blur off, as Noctalia recommends. Noctalia's docs also suggest turning off Noctalia's own shadows under Mango (`shadow = false` for `[bar.default]`, `[dock]` and `[shell.panel]`); the installer doesn't, because that setting would affect every compositor.
- **Labwc:** keeps Labwc's default keybinds and adds the Noctalia, app and close keys. Noctalia's line is appended to an existing `autostart` instead of replacing it.
- **Umbriel:** contains only the settings and keys documented on Noctalia's Umbriel page plus the app keys; window management uses Umbriel's own defaults. The keyboard layout isn't set, because that setting isn't documented.
- **KDE Plasma:** Noctalia is started through Plasma's autostart. Plasma has no blur for Noctalia, and no screenshots, clipboard history or night light from Noctalia. Set shortcuts (`noctalia msg …`) in System Settings.

## What gets installed

- `noctalia` (v5), portals, PipeWire, `playerctl`, `brightnessctl`, fonts, and the packages for each compositor you pick, under your distribution's package names. On Arch this runs a full `pacman -Syu`.
- On Arch with an AUR helper: `base-devel` and `git`, then `paru-bin` or `yay-bin`, built from the AUR as your user. AUR packages (Scroll, Umbriel) are built the same way.
  - Run as root, the installer gives that user passwordless `sudo` only while it builds, and removes the rule straight after (and on exit).
- A config for each compositor you picked (see the table above). Any existing file is backed up first.
- `~/.config/noctalia/10-installer.toml`, which turns on overview type-to-launch for niri and Umbriel and the polkit agent.
- If you choose the greeter: `noctalia-greeter` (which pulls in `greetd`) and `polkit`. The installer sets `command` in `[default_session]` of `/etc/greetd/config.toml`, keeps the greeter account your distribution's greetd already uses (or sets `greeter` if there is none), and leaves the rest of the file unchanged. On Debian and Ubuntu the greeter package configures greetd itself, so the file isn't touched:
  ```toml
  [default_session]
  command = "/usr/bin/noctalia-greeter-session"
  user = "greeter"
  ```
  It then runs `noctalia-greeter-apply-appearance --setup-system` and enables `greetd`. Your old login manager is disabled but not stopped, so your current session keeps running. The switch happens when you reboot.

## Options

| Flag | Effect |
|---|---|
| `--no-tui` | Plain text prompts instead of menus |
| `--yes` | No prompts at all, use defaults and flags |
| `--compositors=…` | Comma-separated: `niri` `hyprland` `sway` `scroll` `mango` `labwc` `umbriel` `kde` (default `niri`) |
| `--aur-helper=…` | Arch only: `auto` (keep an installed one, else paru when needed), `paru`, `yay`, `none` |
| `--user=NAME` | User to set up when run as root |
| `--terminal=…` | `alacritty` `kitty` `foot` `ghostty` `wezterm` |
| `--file-manager=…` | `nautilus` `thunar` `dolphin` `nemo` `none` |
| `--browser=…` | `firefox` `chromium` `none` |
| `--layout=…` | Keyboard layout(s), e.g. `us,de` |
| `--no-apps` | Skip the file manager and browser (a terminal is always installed) |
| `--no-greeter` | Skip Noctalia Greeter and greetd |
| `--lid-fix` | Lock the screen before suspend when the lid closes (niri, Sway, Scroll) |

Example of a fully unattended install as root:

```bash
./install.sh --yes --user=me --compositors=niri,hyprland,scroll --aur-helper=paru --terminal=kitty
```

> If the greeter doesn't appear after you reboot, switch to a TTY (`Ctrl+Alt+F2`) and run `systemctl status greetd`.

## Manual install

Copy the config for your compositor from `configs/`, for example niri:

```bash
mkdir -p ~/.config/niri
cp configs/niri/config.kdl ~/.config/niri/config.kdl
niri validate
```

The configs launch `alacritty`, `nautilus` and `firefox` and use the `us` keyboard layout; change those lines to suit you.
