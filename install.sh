#!/usr/bin/env bash
# =====================================================================
#  niri + Noctalia v5 installer for Arch Linux
#  https://github.com/Abijspy/noctalia-niri-config-setup
#
#  Usage:
#    ./install.sh                 # interactive
#    ./install.sh --yes           # no prompts (accept defaults)
#    ./install.sh --no-apps       # skip terminal/browser/file manager
#    ./install.sh --lid-fix       # also set HandleLidSwitch=ignore in logind
#    ./install.sh --no-greeter    # skip Noctalia Greeter + greetd setup
#
#  Or straight from GitHub:
#    curl -fsSL https://raw.githubusercontent.com/Abijspy/noctalia-niri-config-setup/main/install.sh | bash
# =====================================================================
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/Abijspy/noctalia-niri-config-setup/main"
NIRI_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
NOCTALIA_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/noctalia"

ASSUME_YES=0
INSTALL_APPS=1
LID_FIX=0
INSTALL_GREETER=1
GREETD_CONF="/etc/greetd/config.toml"

for arg in "$@"; do
    case "$arg" in
        -y|--yes)     ASSUME_YES=1 ;;
        --no-apps)    INSTALL_APPS=0 ;;
        --lid-fix)    LID_FIX=1 ;;
        --no-greeter) INSTALL_GREETER=0 ;;
        -h|--help)    sed -n '2,16p' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

# ---------- helpers ----------
c_blue=$'\e[1;34m'; c_green=$'\e[1;32m'; c_yellow=$'\e[1;33m'; c_red=$'\e[1;31m'; c_off=$'\e[0m'
info() { printf '%s==>%s %s\n' "$c_blue" "$c_off" "$*"; }
ok()   { printf '%s ✓ %s %s\n' "$c_green" "$c_off" "$*"; }
warn() { printf '%s !  %s %s\n' "$c_yellow" "$c_off" "$*"; }
die()  { printf '%s ✗  %s %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }

ask() {  # ask "question" default(y/n)
    local prompt="$1" def="${2:-y}" reply
    [[ $ASSUME_YES -eq 1 ]] && { [[ $def == y ]]; return; }
    [[ $def == y ]] && prompt+=" [Y/n] " || prompt+=" [y/N] "
    read -r -p "$prompt" reply </dev/tty || reply=""
    reply="${reply:-$def}"
    [[ $reply =~ ^[Yy] ]]
}

# ---------- checks ----------
[[ $EUID -eq 0 ]] && die "Run as your normal user, not root (sudo is used when needed)."
command -v pacman >/dev/null || die "pacman not found — this script is for Arch Linux."
command -v sudo   >/dev/null || die "sudo is required."

# Find config.kdl: next to the script, or download it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ -n $SCRIPT_DIR && -f $SCRIPT_DIR/niri/config.kdl ]]; then
    CONFIG_SRC="$SCRIPT_DIR/niri/config.kdl"
else
    info "Downloading config.kdl from GitHub"
    command -v curl >/dev/null || sudo pacman -S --needed --noconfirm curl
    curl -fsSL "$REPO_RAW/niri/config.kdl" -o "$TMP_DIR/config.kdl" \
        || die "Could not download config.kdl"
    CONFIG_SRC="$TMP_DIR/config.kdl"
fi

# ---------- packages ----------
# Core: compositor, shell, X11 apps, portals, audio/media helpers.
PKGS=(
    niri                      # compositor
    noctalia                  # Noctalia v5 shell ([extra])
    xwayland-satellite        # X11 app support for niri
    xdg-desktop-portal-gnome  # screencast/screenshot portal used by niri
    xdg-desktop-portal-gtk    # file chooser portal
    gnome-keyring             # secrets for apps
    pipewire wireplumber pipewire-pulse
    playerctl                 # media keys
    brightnessctl
    noto-fonts noto-fonts-emoji ttf-jetbrains-mono-nerd
)
# Apps referenced by the keybinds in config.kdl (Mod+Return/E/B).
APPS=( alacritty nautilus firefox )

[[ $INSTALL_APPS -eq 1 ]] && PKGS+=("${APPS[@]}")

info "Updating system and installing packages:"
printf '    %s\n' "${PKGS[@]}"
if ask "Continue?" y; then
    sudo pacman -Syu --needed --noconfirm "${PKGS[@]}"
    ok "Packages installed"
else
    die "Aborted."
fi

# Noctalia v4 (Quickshell) leftovers warning
if pacman -Qq noctalia-shell &>/dev/null || pacman -Qq noctalia-shell-git &>/dev/null; then
    warn "Noctalia v4 (noctalia-shell) is also installed. This config uses v5 (\`noctalia\`)."
    warn "Remove v4 when you're happy:  sudo pacman -Rns noctalia-shell noctalia-qs"
fi

# ---------- niri config ----------
mkdir -p "$NIRI_DIR"
if [[ -f $NIRI_DIR/config.kdl ]]; then
    BACKUP="$NIRI_DIR/config.kdl.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$NIRI_DIR/config.kdl" "$BACKUP"
    ok "Backed up existing config to $BACKUP"
fi
install -m 644 "$CONFIG_SRC" "$NIRI_DIR/config.kdl"
ok "Installed $NIRI_DIR/config.kdl"

mkdir -p "$HOME/Pictures/Screenshots" "$HOME/Pictures/Wallpapers" "$NOCTALIA_DIR"

# Turn on niri overview type-to-launch in Noctalia (only if not already set).
NOC_NIRI="$NOCTALIA_DIR/10-niri.toml"
if [[ ! -f $NOC_NIRI ]]; then
    cat > "$NOC_NIRI" <<'EOF'
# Written by noctalia-niri-config-setup/install.sh
[shell]
niri_overview_type_to_launch_enabled = true
niri_overview_close_on_launch_enabled = true
EOF
    ok "Wrote $NOC_NIRI (type in niri overview to open the launcher)"
fi

# ---------- validate ----------
info "Validating niri config"
if niri validate -c "$NIRI_DIR/config.kdl"; then
    ok "niri config is valid"
else
    warn "niri validate failed. If it complains about 'background-effect' or 'blur',"
    warn "your niri is too old for blur — update niri (or niri-git from the AUR)."
fi

# ---------- laptop lid ----------
if compgen -G "/sys/class/power_supply/BAT*" >/dev/null; then
    if [[ $LID_FIX -eq 1 ]] || ask "Laptop detected. Let Noctalia lock before suspend on lid close (edit logind.conf)?" n; then
        sudo mkdir -p /etc/systemd/logind.conf.d
        printf '[Login]\nHandleLidSwitch=ignore\nHandleLidSwitchExternalPower=ignore\n' \
            | sudo tee /etc/systemd/logind.conf.d/10-noctalia-lid.conf >/dev/null
        ok "Wrote /etc/systemd/logind.conf.d/10-noctalia-lid.conf (applies after reboot)"
    fi
fi

# ---------- Noctalia Greeter + greetd ----------
aur_install() {  # aur_install pkg — uses paru or yay if present
    local helper
    for helper in paru yay; do
        if command -v "$helper" >/dev/null; then
            "$helper" -S --needed --noconfirm "$@"
            return
        fi
    done
    return 1
}

# Set `key = "value"` inside [default_session] of greetd's config,
# keeping every other line/section untouched.
greetd_set() {  # greetd_set key value
    local key="$1" val="$2" tmp
    tmp="$(mktemp)"
    sudo cat "$GREETD_CONF" | awk -v key="$key" -v val="$val" '
        BEGIN { in_ds = 0; done = 0; seen = 0 }
        /^[[:space:]]*\[.*\][[:space:]]*$/ {
            if (in_ds && !done) { print key " = \"" val "\""; done = 1 }
            in_ds = ($0 ~ /^[[:space:]]*\[default_session\][[:space:]]*$/)
            if (in_ds) seen = 1
            print; next
        }
        in_ds && $0 ~ "^[[:space:]]*#?[[:space:]]*" key "[[:space:]]*=" {
            if (!done) { print key " = \"" val "\""; done = 1 }
            next
        }
        { print }
        END {
            if (in_ds && !done) { print key " = \"" val "\""; done = 1 }
            if (!seen) { print ""; print "[default_session]"; print key " = \"" val "\"" }
        }
    ' > "$tmp"
    sudo install -m 644 "$tmp" "$GREETD_CONF"
    rm -f "$tmp"
}

if [[ $INSTALL_GREETER -eq 1 ]] && ask "Install Noctalia Greeter (login screen) with greetd?" y; then
    info "Installing greetd + Noctalia Greeter"
    sudo pacman -S --needed --noconfirm greetd polkit

    # noctalia-greeter is moving AUR -> [extra]; it may still be in
    # [extra-testing] or the AUR depending on when you run this.
    if pacman -Si noctalia-greeter &>/dev/null; then
        sudo pacman -S --needed --noconfirm noctalia-greeter
    elif aur_install noctalia-greeter || aur_install noctalia-greeter-git; then
        :
    else
        die "noctalia-greeter isn't in your enabled repos and no AUR helper (paru/yay) was found.
    Install it manually (enable [extra-testing] or use an AUR helper), then re-run with --yes."
    fi
    ok "noctalia-greeter installed"

    GREETER_SESSION="$(command -v noctalia-greeter-session || echo /usr/bin/noctalia-greeter-session)"
    [[ -x $GREETER_SESSION ]] || die "noctalia-greeter-session not found at $GREETER_SESSION"

    # greetd config: merge into [default_session], don't overwrite the file.
    sudo mkdir -p /etc/greetd
    if [[ -f $GREETD_CONF ]]; then
        sudo cp "$GREETD_CONF" "$GREETD_CONF.bak.$(date +%Y%m%d-%H%M%S)"
        ok "Backed up $GREETD_CONF"
    else
        printf '[terminal]\nvt = 1\n\n[default_session]\n' | sudo tee "$GREETD_CONF" >/dev/null
    fi
    greetd_set command "$GREETER_SESSION"
    greetd_set user "greeter"
    ok "greetd now starts $GREETER_SESSION as user 'greeter'"

    # State dir (/var/lib/noctalia-greeter) via the shipped tmpfiles rule,
    # then create greeter.toml + sync.toml.
    id greeter &>/dev/null || die "User 'greeter' doesn't exist (it should come with the greetd package)."
    sudo systemd-tmpfiles --create
    sudo noctalia-greeter-apply-appearance --setup-system \
        && ok "Greeter config initialised (greeter.toml, sync.toml)" \
        || warn "noctalia-greeter-apply-appearance --setup-system failed — run it manually later."

    # Switch display manager. Only `disable` (no --now) so we don't kill
    # the session you're running this from; the switch happens on reboot.
    CURRENT_DM="$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" 2>/dev/null || true)"
    if [[ -n $CURRENT_DM && $CURRENT_DM != "display-manager.service" && $CURRENT_DM != "greetd.service" ]]; then
        if ask "Disable current display manager ($CURRENT_DM) and use greetd?" y; then
            sudo systemctl disable "$CURRENT_DM"
            ok "Disabled $CURRENT_DM"
        else
            warn "Leaving $CURRENT_DM enabled — greetd won't be enabled (two DMs would fight)."
            INSTALL_GREETER=0
        fi
    fi
    if [[ $INSTALL_GREETER -eq 1 ]]; then
        sudo systemctl enable greetd.service
        ok "greetd enabled — Noctalia Greeter will appear after reboot"
        GREETER_DONE=1
    fi
fi

# ---------- done ----------
echo
ok "All done."
if [[ ${GREETER_DONE:-0} -eq 1 ]]; then
    LOGIN_HINT="Reboot. Noctalia Greeter will show up — pick the \"Niri\" session and log in."
else
    LOGIN_HINT="Log out and pick \"Niri\" in your display manager, or from a TTY run:  niri-session"
fi
cat <<EOF

  Next steps
  ----------
  • $LOGIN_HINT
  • Noctalia starts automatically (spawn-at-startup "noctalia").
  • Mod+Space  launcher        Mod+S  control center
    Mod+Shift+Comma  Noctalia settings    Mod+Shift+/  all keybinds

EOF
