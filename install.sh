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

for arg in "$@"; do
    case "$arg" in
        -y|--yes)   ASSUME_YES=1 ;;
        --no-apps)  INSTALL_APPS=0 ;;
        --lid-fix)  LID_FIX=1 ;;
        -h|--help)  sed -n '2,15p' "$0"; exit 0 ;;
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

# ---------- done ----------
echo
ok "All done."
cat <<EOF

  Next steps
  ----------
  • Log out and pick "Niri" in your display manager,
    or from a TTY run:  niri-session
  • Noctalia starts automatically (spawn-at-startup "noctalia").
  • Mod+Space  launcher        Mod+S  control center
    Mod+Shift+Comma  Noctalia settings    Mod+Shift+/  all keybinds

EOF
