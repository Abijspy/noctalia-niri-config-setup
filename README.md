# noctalia-niri-config-setup

niri config for the Noctalia v5 shell. Blur is on for all shell surfaces, for apps and in the overview.

## Quick install (Arch Linux)

```bash
git clone https://github.com/Abijspy/noctalia-niri-config-setup.git
cd noctalia-niri-config-setup
./install.sh
```

Or in one line:

```bash
curl -fsSL https://raw.githubusercontent.com/Abijspy/noctalia-niri-config-setup/main/install.sh | bash
```

### What the script does

1. Installs `niri`, `noctalia` (v5, from `[extra]`), `xwayland-satellite`, portals, PipeWire, `playerctl`, `brightnessctl` and fonts. It also installs `alacritty`, `nautilus` and `firefox`, because the keybinds launch them.
2. Backs up any existing `~/.config/niri/config.kdl` and then installs this one.
3. Writes `~/.config/noctalia/10-niri.toml`, which lets you type in niri's overview to open the launcher.
4. Runs `niri validate`.
5. On a laptop, it can optionally set `HandleLidSwitch=ignore`, so Noctalia locks the screen before suspending.
6. Installs **Noctalia Greeter** and **greetd**:
   - It installs `noctalia-greeter` from `[extra]`, which also pulls in `greetd`. It installs `polkit` too, so Noctalia can sync your wallpaper and colours to the login screen.
   - It points greetd at the greeter by merging these lines into `[default_session]` in `/etc/greetd/config.toml`. It backs up that file first and leaves the rest of it unchanged.
     ```toml
     [default_session]
     command = "/usr/bin/noctalia-greeter-session"
     user = "greeter"
     ```
   - It runs `noctalia-greeter-apply-appearance --setup-system`, which creates `greeter.toml` and `sync.toml`.
   - It disables your current display manager (gdm, sddm or lightdm) and enables `greetd`. Neither service is stopped now, so your running session stays up. The switch happens when you reboot.

### Options

| Flag | Effect |
|---|---|
| `--yes` | No prompts |
| `--no-apps` | Skip alacritty / nautilus / firefox |
| `--lid-fix` | Apply the logind lid setting without asking |
| `--no-greeter` | Skip Noctalia Greeter and greetd |

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
