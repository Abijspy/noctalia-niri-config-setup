# noctalia-niri-config-setup

niri config for the Noctalia v5 shell. Blur is on for all shell surfaces, for apps and in the overview.

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

### The TUI installer

The installer opens full-screen menus (whiptail). It installs `libnewt` (the package that provides whiptail) automatically if it's missing, and the menus fit a standard 80×24 console.

1. **Welcome:** shows whether it found a laptop and an existing login manager.
2. **User:** only when run as root. Pick an existing user or create a new one. A new user is added to `wheel`, and `sudo` is installed and enabled for that group.
3. **Components:** apps, Noctalia Greeter, overview type-to-launch, Noctalia's polkit agent, and the lid-close lock (laptops only).
4. **Apps:** terminal (alacritty, kitty, foot, ghostty or wezterm), file manager (nautilus, thunar, dolphin, nemo or none) and browser (firefox, chromium or none). The keybinds in the config are updated to match.
5. **Keyboard layout:** written into the niri config, e.g. `us` or `us,de`.
6. **Login manager:** if gdm, sddm or lightdm is active, it asks before replacing it with greetd.
7. **Summary:** nothing changes until you confirm here.
8. **Progress bar,** then a final screen and an offer to reboot.

If something fails, it shows the last lines of the log. The full log is at `/tmp/noctalia-niri-install.log`.

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
