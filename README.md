# noctalia-niri-config-setup

niri config for the Noctalia v5 shell. Blur is on for all shell surfaces, for apps and in the overview. It comes with an Arch Linux installer that uses Noctalia's own colors.

![The installer's welcome screen](docs/screenshots/welcome.png)

## Quick install (Arch Linux)

Works on a **fresh minimal Arch install**, straight from the TTY and even as root:

```bash
curl -fsSL https://raw.githubusercontent.com/Abijspy/noctalia-niri-config-setup/main/install.sh | bash
```

Or from a clone:

```bash
git clone https://github.com/Abijspy/noctalia-niri-config-setup.git
cd noctalia-niri-config-setup
./install.sh
```

### The installer

The installer is a full-screen terminal UI built with [gum](https://github.com/charmbracelet/gum). It uses the colors of Noctalia's built-in palette: navy surface, yellow primary, lavender secondary and mint accents. If gum is missing, the installer installs it first. On a bare Linux console it temporarily switches the console to the Noctalia palette and uses symbols the console font can draw. The original palette comes back when the installer exits.

| | |
|---|---|
| ![Choosing components](docs/screenshots/components.png) | ![Choosing a terminal](docs/screenshots/apps.png) |
| **Components:** tick the extras you want | **Apps:** pick a terminal, file manager and browser |
| ![Review screen](docs/screenshots/review.png) | ![Installing](docs/screenshots/installing.png) |
| **Review:** nothing changes until you choose *Install now* | **Install:** live steps, progress bar and the latest log lines |

![Finished screen](docs/screenshots/done.png)

On a minimal install, straight from the TTY:

![The installer on the Linux console](docs/screenshots/tty.png)

<sub>Screenshots are rendered from a test run, so the install log shows placeholder package names.</sub>

**Controls**

| Key | Action |
|---|---|
| `↑` / `↓` | Move between options |
| `Enter` | Continue (picks the highlighted option) |
| `Space` | Tick or untick an item on the Components screen |
| `Esc` | Quit the installer. Nothing changes before you choose *Install now* |

**Screens**

1. **Welcome:** shows whether it found a laptop and an existing login manager.
2. **User:** only when run as root. Pick an existing user or create a new one. A new user is added to `wheel`, and `sudo` is installed and enabled for that group.
3. **Components:** apps, Noctalia Greeter, overview type-to-launch, Noctalia's polkit agent, and the lid-close lock (laptops only).
4. **Apps:** terminal (alacritty, kitty, foot, ghostty or wezterm), file manager (nautilus, thunar, dolphin, nemo or none) and browser (firefox, chromium or none). The keybinds in the config are updated to match.
5. **Keyboard:** the layout is written into the niri config, e.g. `us` or `us,de`.
6. **Review:** if gdm, sddm or lightdm is active, it first asks whether to replace it with greetd. Then you can install, go back and change your choices, or quit.
7. **Install:** each step is shown as it runs, with a progress bar and the latest log lines. Keys are ignored during this step so it can't be stopped halfway.
8. **Done:** the main keybinds, any notes, and an offer to reboot.

If something fails, the installer shows the last lines of the log. The full log is at `/tmp/noctalia-niri-install.log`.

### What gets installed

- `niri`, `noctalia` (v5), `xwayland-satellite`, portals, PipeWire, `playerctl`, `brightnessctl` and fonts. This runs a full `pacman -Syu`.
- `~/.config/niri/config.kdl`, with any existing file backed up first.
- `~/.config/noctalia/10-niri.toml`, which turns on type-to-launch and the polkit agent.
- If you choose the greeter: `noctalia-greeter` from `[extra]` (which pulls in `greetd`) and `polkit`. The installer sets these lines in `[default_session]` of `/etc/greetd/config.toml` and leaves the rest of the file unchanged:
  ```toml
  [default_session]
  command = "/usr/bin/noctalia-greeter-session"
  user = "greeter"
  ```
  It then runs `noctalia-greeter-apply-appearance --setup-system` and enables `greetd`. Your old login manager is disabled but not stopped, so your current session keeps running. The switch happens when you reboot.

### Options

| Flag | Effect |
|---|---|
| `--no-tui` | Plain text prompts instead of menus |
| `--yes` | No prompts at all, use defaults and flags |
| `--user=NAME` | User to set up when run as root |
| `--terminal=…` | `alacritty` `kitty` `foot` `ghostty` `wezterm` |
| `--file-manager=…` | `nautilus` `thunar` `dolphin` `nemo` `none` |
| `--browser=…` | `firefox` `chromium` `none` |
| `--layout=…` | Keyboard layout(s), e.g. `us,de` |
| `--no-apps` | Skip the file manager and browser (a terminal is always installed) |
| `--no-greeter` | Skip Noctalia Greeter and greetd |
| `--lid-fix` | Lock the screen before suspend when the lid closes |

Example of a fully unattended install as root:

```bash
./install.sh --yes --user=me --terminal=kitty --layout=us
```

> If the greeter doesn't appear after you reboot, switch to a TTY (`Ctrl+Alt+F2`) and run `systemctl status greetd`.

## Manual install

```bash
mkdir -p ~/.config/niri
cp niri/config.kdl ~/.config/niri/config.kdl
niri validate
```

Blur needs a niri build with `background-effect` / `blur` support.

## Key binds

| Keys | Action |
|---|---|
| `Mod+Space` / `Mod+D` | Noctalia launcher |
| `Mod+S` | Control center |
| `Mod+Shift+Comma` | Noctalia settings |
| `Alt+Tab` | Noctalia window switcher |
| `Mod+O` | Overview |
| `Mod+Return` | Terminal |
| `Mod+Shift+/` | Show all keybinds |
