#!/usr/bin/env bash
# =====================================================================
#  niri + Noctalia v5 installer for Arch Linux (TUI)
#  https://github.com/Abijspy/noctalia-niri-config-setup
#
#  Works on a fresh minimal Arch install (bare TTY, even as root):
#  it installs whiptail itself and shows a full-screen installer.
#
#  Usage:
#    ./install.sh                     # TUI installer (default)
#    ./install.sh --no-tui            # plain text prompts
#    ./install.sh --yes               # no prompts, accept defaults
#
#  Options (also preset the TUI choices):
#    --user=NAME                      # user to set up (when run as root)
#    --terminal=alacritty|kitty|foot|ghostty|wezterm
#    --file-manager=nautilus|thunar|dolphin|nemo|none
#    --browser=firefox|chromium|none
#    --layout=us                      # keyboard layout(s), e.g. us,de
#    --no-apps                        # skip terminal/file manager/browser
#    --no-greeter                     # skip Noctalia Greeter + greetd
#    --lid-fix                        # lock before suspend on lid close
#
#  Straight from GitHub:
#    curl -fsSL https://raw.githubusercontent.com/Abijspy/noctalia-niri-config-setup/main/install.sh | bash
# =====================================================================
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/Abijspy/noctalia-niri-config-setup/main"
GREETD_CONF="/etc/greetd/config.toml"
LOG="/tmp/noctalia-niri-install.log"
BT="niri + Noctalia v5 installer"

# ---------- defaults ----------
ASSUME_YES=0
NO_TUI=0
INSTALL_APPS=1
INSTALL_GREETER=1
LID_FIX=0
TYPE_TO_LAUNCH=1
POLKIT_AGENT=1
SWITCH_DM=1
TARGET_USER=""
NEW_USER_PASS=""
CREATE_USER=0
TERM_APP="alacritty"
FM_APP="nautilus"
BROWSER_APP="firefox"
KB_LAYOUT="us"

usage() { sed -n '3,25p' "${BASH_SOURCE[0]:-$0}" 2>/dev/null | sed 's/^# \{0,1\}//'; }

for arg in "$@"; do
    case "$arg" in
        -y|--yes)          ASSUME_YES=1 ;;
        --no-tui)          NO_TUI=1 ;;
        --no-apps)         INSTALL_APPS=0 ;;
        --no-greeter)      INSTALL_GREETER=0 ;;
        --lid-fix)         LID_FIX=1 ;;
        --user=*)          TARGET_USER="${arg#*=}" ;;
        --terminal=*)      TERM_APP="${arg#*=}" ;;
        --file-manager=*)  FM_APP="${arg#*=}" ;;
        --browser=*)       BROWSER_APP="${arg#*=}" ;;
        --layout=*)        KB_LAYOUT="${arg#*=}" ;;
        -h|--help)         usage; exit 0 ;;
        *) echo "Unknown option: $arg (see --help)"; exit 1 ;;
    esac
done

check_opt() {  # check_opt name value allowed...
    local name="$1" val="$2"; shift 2
    local a; for a in "$@"; do [[ $val == "$a" ]] && return 0; done
    echo "Invalid --$name=$val (allowed: $*)"; exit 1
}
check_opt terminal     "$TERM_APP"    alacritty kitty foot ghostty wezterm
check_opt file-manager "$FM_APP"      nautilus thunar dolphin nemo none
check_opt browser      "$BROWSER_APP" firefox chromium none
[[ $KB_LAYOUT =~ ^[a-z]{2,}(,[a-z]{2,})*$ ]] || { echo "Invalid --layout=$KB_LAYOUT (e.g. us or us,de)"; exit 1; }

# ---------- output helpers ----------
c_blue=$'\e[1;34m'; c_green=$'\e[1;32m'; c_yellow=$'\e[1;33m'; c_red=$'\e[1;31m'; c_off=$'\e[0m'
WARN_FILE="$(mktemp)"
TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR" "$WARN_FILE"; [[ -n ${KEEPALIVE_PID:-} ]] && kill "$KEEPALIVE_PID" 2>/dev/null; true; }
trap cleanup EXIT

info() { printf '%s==>%s %s\n' "$c_blue" "$c_off" "$*"; }
ok()   { printf '%s ✓ %s %s\n' "$c_green" "$c_off" "$*"; }
warn() { printf '%s !  %s %s\n' "$c_yellow" "$c_off" "$*"; echo "• $*" >> "$WARN_FILE"; }
die()  { printf '%s ✗  %s %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }

# ---------- environment checks ----------
command -v pacman >/dev/null || die "pacman not found — this installer is for Arch Linux."

if [[ $EUID -eq 0 ]]; then
    IS_ROOT=1; SUDO=()
else
    IS_ROOT=0; SUDO=(sudo)
    command -v sudo >/dev/null || die "sudo is not installed. Run this installer as root instead (it can create your user)."
fi

IS_LAPTOP=0
compgen -G "/sys/class/power_supply/BAT*" >/dev/null && IS_LAPTOP=1

CURRENT_DM="$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" 2>/dev/null || true)"
[[ $CURRENT_DM == "display-manager.service" || $CURRENT_DM == "greetd.service" ]] && CURRENT_DM=""

HAVE_TTY=0
{ : </dev/tty >/dev/tty; } 2>/dev/null && HAVE_TTY=1

# Non-root: get sudo once now (visible prompt), then keep it alive so it
# never prompts invisibly behind the progress screen.
if [[ $IS_ROOT -eq 0 ]]; then
    info "Administrator rights are needed to install packages."
    sudo -v </dev/tty || die "sudo authentication failed."
    ( while kill -0 $$ 2>/dev/null; do sudo -n true; sleep 45; done ) 2>/dev/null &
    KEEPALIVE_PID=$!
fi

# ---------- UI layer (whiptail TUI or plain prompts) ----------
UI=plain

pac_install_quiet() {  # install packages from current db; full -Syu only if needed
    "${SUDO[@]}" pacman -S --needed --noconfirm "$@" >>"$LOG" 2>&1 \
        || "${SUDO[@]}" pacman -Syu --needed --noconfirm "$@" >>"$LOG" 2>&1
}

init_ui() {
    [[ $ASSUME_YES -eq 1 || $NO_TUI -eq 1 || $HAVE_TTY -eq 0 ]] && return 0
    if ! command -v whiptail >/dev/null; then
        info "Installing whiptail (libnewt) for the installer UI…"
        pac_install_quiet libnewt || { warn "Couldn't install whiptail — using plain prompts."; return 0; }
    fi
    local lines cols
    read -r lines cols < <(stty size </dev/tty 2>/dev/null || echo "24 80")
    if (( lines < 20 || cols < 76 )); then
        warn "Terminal is ${cols}x${lines}; the TUI needs at least 76x20 — using plain prompts."
        return 0
    fi
    UI=tui
    TERM_LINES=$lines
    export NEWT_COLORS='
root=white,black
border=magenta,black
window=white,black
title=magenta,black
textbox=white,black
button=black,magenta
actbutton=black,white
checkbox=white,black
actcheckbox=black,magenta
listbox=white,black
actlistbox=black,magenta
actsellistbox=black,magenta
entry=white,black
compactbutton=white,black
roottext=magenta,black
'
}

# whiptail draws on the TTY; its answer comes back on stdout of $( ).
wt() { whiptail --backtitle "$BT" "$@" 2>&1 >/dev/tty </dev/tty; }

cancelled() {
    [[ $UI == tui ]] && clear >/dev/tty
    echo "Installer cancelled. No changes were made to your system configuration."
    exit 0
}

TERM_LINES=24
box_height() {  # box_height "text" -> rows that fit the text, capped to the screen
    local n; n=$(printf '%s\n' "$1" | wc -l)
    local h=$(( n + 7 )) max=$(( TERM_LINES - 2 ))
    (( h < 8 )) && h=8
    (( h > max )) && h=$max
    echo "$h"
}

msg() {  # msg title text
    if [[ $UI == tui ]]; then
        local h scroll=() n; h="$(box_height "$2")"
        n=$(printf '%s\n' "$2" | wc -l)
        # Only scroll if the text truly can't fit (scroll mode makes Enter scroll, not OK).
        (( n + 7 > TERM_LINES - 2 )) && scroll=(--scrolltext)
        whiptail --backtitle "$BT" --title "$1" "${scroll[@]}" --msgbox "$2" "$h" 76 >/dev/tty </dev/tty 2>&1 || true
    else
        printf '\n%s\n%s\n\n' "$1" "$2"
    fi
}

ask() {  # ask "question" default(y/n) [title]
    local q="$1" def="${2:-y}" title="${3:-Confirm}" reply
    [[ $ASSUME_YES -eq 1 ]] && { [[ $def == y ]]; return; }
    if [[ $UI == tui ]]; then
        local extra=(); [[ $def == n ]] && extra=(--defaultno)
        whiptail --backtitle "$BT" --title "$title" "${extra[@]}" --yesno "$q" "$(box_height "$q")" 76 >/dev/tty </dev/tty 2>&1
        return
    fi
    [[ $def == y ]] && q+=" [Y/n] " || q+=" [y/N] "
    read -r -p "$q" reply </dev/tty || reply=""
    reply="${reply:-$def}"
    [[ $reply =~ ^[Yy] ]]
}

radio() {  # radio title text current tag desc [tag desc ...]  -> echoes tag
    local title="$1" text="$2" cur="$3"; shift 3
    local items=() n=0
    while (( $# )); do
        items+=("$1" "$2" "$([[ $1 == "$cur" ]] && echo ON || echo OFF)"); shift 2; n=$((n+1))
    done
    wt --title "$title" --radiolist "$text\n\nUse ↑/↓, Space to select, Enter to confirm." 18 76 "$n" "${items[@]}" || cancelled
}

# ---------- decisions ----------
existing_users() { getent passwd | awk -F: '$3>=1000 && $3<60000 && $7 !~ /(nologin|false)$/ {print $1}'; }

pick_target_user() {
    if [[ $IS_ROOT -eq 0 ]]; then TARGET_USER="$(id -un)"; return; fi
    local users; mapfile -t users < <(existing_users)

    if [[ -n $TARGET_USER ]]; then
        id "$TARGET_USER" &>/dev/null || CREATE_USER=1
    elif [[ $UI == tui ]]; then
        local items=() u
        for u in "${users[@]}"; do items+=("$u" "Set up niri + Noctalia for $u"); done
        items+=("+new" "Create a new user (added to wheel, sudo enabled)")
        local pick
        pick="$(wt --title "User" --menu "You're running as root. Which user should get the desktop?" 18 76 8 "${items[@]}")" || cancelled
        if [[ $pick == "+new" ]]; then CREATE_USER=1; else TARGET_USER="$pick"; fi
    elif (( ${#users[@]} == 1 )); then
        TARGET_USER="${users[0]}"
    else
        die "Running as root: pass --user=NAME (existing users: ${users[*]:-none}). Without users, run the TUI to create one."
    fi

    if [[ $CREATE_USER -eq 1 ]]; then
        [[ $UI == tui ]] || [[ -n $TARGET_USER ]] || die "Use the TUI (or --user=NAME) to create a user."
        while [[ $UI == tui ]]; do
            TARGET_USER="$(wt --title "New user" --inputbox "Username (lowercase letters, digits, - or _):" 10 76 "$TARGET_USER")" || cancelled
            [[ $TARGET_USER =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && ! id "$TARGET_USER" &>/dev/null && break
            msg "Invalid username" "'$TARGET_USER' is invalid or already exists. Try again."
        done
        while [[ $UI == tui ]]; do
            local p1 p2
            p1="$(wt --title "New user" --passwordbox "Password for $TARGET_USER:" 10 76)" || cancelled
            p2="$(wt --title "New user" --passwordbox "Repeat the password:" 10 76)" || cancelled
            [[ -n $p1 && $p1 == "$p2" ]] && { NEW_USER_PASS="$p1"; break; }
            msg "Password" "Passwords were empty or didn't match. Try again."
        done
        [[ $UI == tui ]] || die "User '$TARGET_USER' doesn't exist. Create it first or use the TUI."
    fi
}

tui_decisions() {
    local laptop_txt="no" dm_txt="none (TTY login)"
    [[ $IS_LAPTOP -eq 1 ]] && laptop_txt="yes"
    [[ -n $CURRENT_DM ]] && dm_txt="$CURRENT_DM"

    msg "Welcome" "This installs a complete niri + Noctalia v5 desktop:

  • niri — scrollable tiling Wayland compositor
  • Noctalia v5 — bar, launcher, notifications, lock screen
  • A ready niri config with blur everywhere
  • Optional Noctalia Greeter login screen (greetd)

Detected:  laptop: $laptop_txt   login manager: $dm_txt

Nothing changes until you confirm the summary.
Enter = continue, Esc = quit."

    pick_target_user

    # Components
    local items=(
        apps     "Apps for the keybinds (terminal, files, browser)"  "$([[ $INSTALL_APPS -eq 1 ]] && echo ON || echo OFF)"
        greeter  "Noctalia Greeter login screen (greetd)"            "$([[ $INSTALL_GREETER -eq 1 ]] && echo ON || echo OFF)"
        launch   "Type in niri overview to open the launcher"        ON
        polkit   "Noctalia polkit agent (password prompts for apps)" ON
    )
    [[ $IS_LAPTOP -eq 1 ]] && items+=(lid "Lock screen before suspend on lid close" "$([[ $LID_FIX -eq 1 ]] && echo ON || echo OFF)")
    local sel
    sel="$(wt --title "Components" --separate-output --checklist \
        "niri, Noctalia, portals, audio and fonts are always installed.\nChoose the extras (Space toggles, Enter confirms):" \
        18 76 6 "${items[@]}")" || cancelled
    INSTALL_APPS=0; INSTALL_GREETER=0; TYPE_TO_LAUNCH=0; POLKIT_AGENT=0; LID_FIX=0
    while read -r s; do
        case "$s" in
            apps) INSTALL_APPS=1 ;; greeter) INSTALL_GREETER=1 ;; launch) TYPE_TO_LAUNCH=1 ;;
            polkit) POLKIT_AGENT=1 ;; lid) LID_FIX=1 ;;
        esac
    done <<< "$sel"

    if [[ $INSTALL_APPS -eq 1 ]]; then
        TERM_APP="$(radio "Terminal" "Terminal for Mod+Return:" "$TERM_APP" \
            alacritty "Alacritty — fast, GPU accelerated" \
            kitty     "Kitty — GPU, tabs, images" \
            foot      "Foot — tiny, Wayland-native" \
            ghostty   "Ghostty — modern, GPU" \
            wezterm   "WezTerm — GPU, multiplexer")"
        FM_APP="$(radio "File manager" "File manager for Mod+E:" "$FM_APP" \
            nautilus "Nautilus (GNOME Files)" \
            thunar   "Thunar (Xfce, lightweight)" \
            dolphin  "Dolphin (KDE)" \
            nemo     "Nemo (Cinnamon)" \
            none     "None — leave Mod+E unbound")"
        BROWSER_APP="$(radio "Browser" "Web browser for Mod+B:" "$BROWSER_APP" \
            firefox  "Firefox" \
            chromium "Chromium" \
            none     "None — leave Mod+B unbound")"
    fi

    while true; do
        KB_LAYOUT="$(wt --title "Keyboard" --inputbox "Keyboard layout(s) for niri (xkb), comma separated.\nExamples: us   de   fr   us,ru" 12 76 "$KB_LAYOUT")" || cancelled
        [[ $KB_LAYOUT =~ ^[a-z]{2,}(,[a-z]{2,})*$ ]] && break
        msg "Keyboard" "'$KB_LAYOUT' doesn't look like an xkb layout list. Try e.g. 'us' or 'us,de'."
    done

    if [[ $INSTALL_GREETER -eq 1 && -n $CURRENT_DM ]]; then
        if ask "$CURRENT_DM is your current login manager.\n\nDisable it and use greetd + Noctalia Greeter instead?\n(Takes effect after reboot; your current session keeps running.)" y "Login manager"; then
            SWITCH_DM=1
        else
            SWITCH_DM=0
        fi
    fi

    # Summary
    local apps_txt="no" greeter_txt="no" user_txt="$TARGET_USER"
    [[ $INSTALL_APPS -eq 1 ]] && apps_txt="$TERM_APP, $FM_APP, $BROWSER_APP"
    if [[ $INSTALL_GREETER -eq 1 ]]; then
        greeter_txt="yes"
        [[ -n $CURRENT_DM && $SWITCH_DM -eq 0 ]] && greeter_txt="installed, but $CURRENT_DM stays active"
        [[ -n $CURRENT_DM && $SWITCH_DM -eq 1 ]] && greeter_txt="yes (replaces $CURRENT_DM)"
    fi
    [[ $CREATE_USER -eq 1 ]] && user_txt="$TARGET_USER (new, wheel + sudo)"

    ask "Ready to install:

  User ............ $user_txt
  Core ............ niri, noctalia, portals, pipewire, fonts
                    (runs a full system upgrade: pacman -Syu)
  Apps ............ $apps_txt
  Keyboard ........ $KB_LAYOUT
  Login screen .... $greeter_txt
  Type-to-launch .. $([[ $TYPE_TO_LAUNCH -eq 1 ]] && echo yes || echo no)    Polkit agent .. $([[ $POLKIT_AGENT -eq 1 ]] && echo yes || echo no)    Lid lock .. $([[ $LID_FIX -eq 1 ]] && echo yes || echo no)

Existing ~/.config/niri/config.kdl is backed up first.
Install now?" y "Summary" || cancelled
}

plain_decisions() {
    pick_target_user
    if [[ $INSTALL_GREETER -eq 1 ]]; then
        ask "Install Noctalia Greeter (login screen) with greetd?" y || INSTALL_GREETER=0
    fi
    if [[ $INSTALL_GREETER -eq 1 && -n $CURRENT_DM ]]; then
        ask "Disable current display manager ($CURRENT_DM) and use greetd?" y || SWITCH_DM=0
    fi
    if [[ $IS_LAPTOP -eq 1 && $LID_FIX -eq 0 ]]; then
        ask "Laptop detected. Lock before suspend on lid close (edit logind)?" n && LID_FIX=1
    fi
    info "User: $TARGET_USER | apps: $([[ $INSTALL_APPS -eq 1 ]] && echo "$TERM_APP $FM_APP $BROWSER_APP" || echo none) | layout: $KB_LAYOUT"
    ask "Continue with installation (includes pacman -Syu)?" y || die "Aborted."
}

# ---------- install steps ----------
# progress PCT "message": drives the TUI gauge (fd 3) or prints in plain mode.
progress() {
    if [[ $UI == tui ]]; then
        printf 'XXX\n%d\n%s\nXXX\n' "$1" "$2" >&3
        printf '\n==> [%d%%] %s\n' "$1" "$2"
    else
        info "$2"
    fi
}

# Run a long command; in TUI mode creep the gauge from→to while it runs.
run_long() {  # run_long FROM TO "message" cmd...
    local from=$1 to=$2 text=$3; shift 3
    if [[ $UI != tui ]]; then "$@"; return $?; fi
    "$@" & local pid=$! p=$from
    while kill -0 "$pid" 2>/dev/null; do
        progress "$p" "$text"
        (( p < to - 1 )) && p=$((p + 1))
        sleep 4
    done
    wait "$pid"
}

as_root() { "${SUDO[@]}" "$@"; }

mk_user_dir() {  # create dirs owned by the target user
    local d
    for d in "$@"; do
        if [[ $IS_ROOT -eq 1 ]]; then
            install -d -o "$TARGET_USER" -g "$TARGET_GROUP" "$d"
        else
            mkdir -p "$d"
        fi
    done
}

put_user_file() {  # put_user_file SRC DEST
    if [[ $IS_ROOT -eq 1 ]]; then
        install -m 644 -o "$TARGET_USER" -g "$TARGET_GROUP" "$1" "$2"
    else
        install -m 644 "$1" "$2"
    fi
}

backup_if_exists() {
    [[ -f $1 ]] || return 0
    local b; b="$1.bak.$(date +%Y%m%d-%H%M%S)"
    cp -p "$1" "$b"; ok "Backed up $1 -> $b"
}

# Set `key = "value"` inside [default_session] of greetd's config,
# keeping every other line/section untouched.
greetd_set() {  # greetd_set key value
    local key="$1" val="$2" tmp
    tmp="$(mktemp)"
    as_root cat "$GREETD_CONF" | awk -v key="$key" -v val="$val" '
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
    as_root install -m 644 "$tmp" "$GREETD_CONF"
    rm -f "$tmp"
}

run_steps() {
    set -e

    # 1. User (root on a minimal install)
    if [[ $CREATE_USER -eq 1 ]]; then
        progress 2 "Creating user $TARGET_USER…"
        pacman -S --needed --noconfirm sudo
        getent group wheel >/dev/null || groupadd wheel
        useradd -m -G wheel -s /bin/bash "$TARGET_USER"
        printf '%s:%s\n' "$TARGET_USER" "$NEW_USER_PASS" | chpasswd
        NEW_USER_PASS=""
        echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
        chmod 440 /etc/sudoers.d/10-wheel
        ok "Created $TARGET_USER (wheel, sudo enabled)"
    fi
    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    TARGET_GROUP="$(id -gn "$TARGET_USER")"
    [[ -d $TARGET_HOME ]] || die "Home directory for $TARGET_USER not found."
    if [[ $IS_ROOT -eq 1 ]]; then
        CONFIG_HOME="$TARGET_HOME/.config"
    else
        CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
    fi
    NIRI_DIR="$CONFIG_HOME/niri"
    NOCTALIA_DIR="$CONFIG_HOME/noctalia"

    # 2. Get + customise config.kdl
    progress 4 "Preparing niri config…"
    local work="$TMP_DIR/config.kdl"
    if [[ -n $SCRIPT_DIR && -f $SCRIPT_DIR/niri/config.kdl ]]; then
        cp "$SCRIPT_DIR/niri/config.kdl" "$work"
    else
        curl -fsSL "$REPO_RAW/niri/config.kdl" -o "$work" || die "Could not download config.kdl"
    fi
    sed -i "s/layout \"us\"/layout \"$KB_LAYOUT\"/" "$work"
    sed -i "s/spawn \"alacritty\"/spawn \"$TERM_APP\"/" "$work"
    if [[ $FM_APP == none ]]; then sed -i '/spawn "nautilus"/ s|^|//|' "$work"
    else sed -i "s/spawn \"nautilus\"/spawn \"$FM_APP\"/" "$work"; fi
    if [[ $BROWSER_APP == none ]]; then sed -i '/spawn "firefox"/ s|^|//|' "$work"
    else sed -i "s/spawn \"firefox\"/spawn \"$BROWSER_APP\"/" "$work"; fi

    # 3. Packages
    local pkgs=(
        niri noctalia xwayland-satellite
        xdg-desktop-portal-gnome xdg-desktop-portal-gtk gnome-keyring
        pipewire wireplumber pipewire-pulse
        playerctl brightnessctl
        noto-fonts noto-fonts-emoji ttf-jetbrains-mono-nerd
    )
    # Always install the terminal: Mod+Return is your way into the system.
    pkgs+=("$TERM_APP")
    if [[ $INSTALL_APPS -eq 1 ]]; then
        [[ $FM_APP != none ]] && pkgs+=("$FM_APP")
        [[ $BROWSER_APP != none ]] && pkgs+=("$BROWSER_APP")
    fi
    [[ $INSTALL_GREETER -eq 1 ]] && pkgs+=(noctalia-greeter)
    # polkit: greeter appearance sync and/or Noctalia's polkit agent.
    if [[ $INSTALL_GREETER -eq 1 || $POLKIT_AGENT -eq 1 ]]; then pkgs+=(polkit); fi

    run_long 6 70 "Upgrading system and installing packages (this can take a while)…" \
        as_root pacman -Syu --needed --noconfirm "${pkgs[@]}" \
        || die "pacman failed — see $LOG"
    ok "Packages installed"

    if pacman -Qq noctalia-shell &>/dev/null || pacman -Qq noctalia-shell-git &>/dev/null; then
        warn "Noctalia v4 (noctalia-shell) is still installed. Remove it once v5 works: sudo pacman -Rns noctalia-shell noctalia-qs"
    fi

    # 4. User config files
    progress 72 "Installing niri config…"
    mk_user_dir "$CONFIG_HOME" "$NIRI_DIR" "$NOCTALIA_DIR" \
        "$TARGET_HOME/Pictures" "$TARGET_HOME/Pictures/Screenshots" "$TARGET_HOME/Pictures/Wallpapers"
    backup_if_exists "$NIRI_DIR/config.kdl"
    put_user_file "$work" "$NIRI_DIR/config.kdl"
    ok "Installed $NIRI_DIR/config.kdl"

    progress 75 "Writing Noctalia settings…"
    local toml="$TMP_DIR/10-niri.toml"
    {
        echo "# Written by noctalia-niri-config-setup/install.sh"
        echo "[shell]"
        [[ $TYPE_TO_LAUNCH -eq 1 ]] && echo "niri_overview_type_to_launch_enabled = true"
        [[ $TYPE_TO_LAUNCH -eq 1 ]] && echo "niri_overview_close_on_launch_enabled = true"
        [[ $POLKIT_AGENT -eq 1 ]] && echo "polkit_agent = true"
        true
    } > "$toml"
    backup_if_exists "$NOCTALIA_DIR/10-niri.toml"
    put_user_file "$toml" "$NOCTALIA_DIR/10-niri.toml"
    ok "Wrote $NOCTALIA_DIR/10-niri.toml"

    progress 78 "Validating niri config…"
    if niri validate -c "$NIRI_DIR/config.kdl"; then
        ok "niri config is valid"
    else
        warn "niri validate failed. If it mentions 'background-effect' or 'blur', your niri is too old for blur — update niri. Details in $LOG"
    fi

    # 5. Laptop lid
    if [[ $LID_FIX -eq 1 ]]; then
        progress 80 "Configuring lid close…"
        as_root mkdir -p /etc/systemd/logind.conf.d
        printf '[Login]\nHandleLidSwitch=ignore\nHandleLidSwitchExternalPower=ignore\n' \
            | as_root tee /etc/systemd/logind.conf.d/10-noctalia-lid.conf >/dev/null
        ok "Lid close handled by niri/Noctalia (after reboot)"
    fi

    # 6. Noctalia Greeter + greetd
    if [[ $INSTALL_GREETER -eq 1 ]]; then
        progress 84 "Configuring greetd for Noctalia Greeter…"
        local session
        session="$(command -v noctalia-greeter-session || echo /usr/bin/noctalia-greeter-session)"
        [[ -x $session ]] || die "noctalia-greeter-session not found at $session"
        as_root mkdir -p /etc/greetd
        if as_root test -f "$GREETD_CONF"; then
            as_root cp -p "$GREETD_CONF" "$GREETD_CONF.bak.$(date +%Y%m%d-%H%M%S)"
        else
            printf '[terminal]\nvt = 1\n\n[default_session]\n' | as_root tee "$GREETD_CONF" >/dev/null
        fi
        greetd_set command "$session"
        greetd_set user "greeter"
        ok "greetd starts $session as 'greeter'"

        progress 90 "Setting up the greeter…"
        id greeter &>/dev/null || die "User 'greeter' missing (should come with greetd)."
        as_root systemd-tmpfiles --create
        if as_root noctalia-greeter-apply-appearance --setup-system; then
            ok "Greeter config initialised"
        else
            warn "noctalia-greeter-apply-appearance --setup-system failed — run it manually later."
        fi

        progress 95 "Enabling the login screen…"
        if [[ -n $CURRENT_DM && $SWITCH_DM -eq 1 ]]; then
            as_root systemctl disable "$CURRENT_DM"
            ok "Disabled $CURRENT_DM"
        fi
        if [[ -z $CURRENT_DM || $SWITCH_DM -eq 1 ]]; then
            as_root systemctl enable greetd.service
            ok "greetd enabled"
            echo 1 > "$TMP_DIR/greeter_enabled"
        else
            warn "Kept $CURRENT_DM; greetd was not enabled (two login managers would conflict)."
        fi
    fi

    progress 100 "Done."
    sleep 1
}

# ---------- main ----------
: > "$LOG"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"

init_ui
if [[ $UI == tui ]]; then tui_decisions; else plain_decisions; fi

# In the TUI, sudo must never prompt (it would be hidden behind the gauge).
[[ $UI == tui && $IS_ROOT -eq 0 ]] && SUDO=(sudo -n)

if [[ $UI == tui ]]; then
    set +e
    ( run_steps ) 3>&1 >>"$LOG" 2>&1 \
        | whiptail --backtitle "$BT" --title "Installing" --gauge "Starting…" 8 76 0 >/dev/tty 2>&1
    rc=${PIPESTATUS[0]}
    set -e
    if [[ $rc -ne 0 ]]; then
        msg "Installation failed" "Last lines of the log:

$(tail -n 12 "$LOG" | cut -c1-72)

Full log: $LOG"
        clear >/dev/tty
        die "Installation failed. Full log: $LOG"
    fi
else
    run_steps 3>/dev/null
fi

# ---------- finish ----------
GREETER_ENABLED=0; [[ -f $TMP_DIR/greeter_enabled ]] && GREETER_ENABLED=1
if [[ $GREETER_ENABLED -eq 1 ]]; then
    LOGIN_HINT="Reboot: Noctalia Greeter appears. Pick the \"Niri\" session and log in as $TARGET_USER."
elif [[ -n $CURRENT_DM ]]; then
    LOGIN_HINT="Log out and pick \"Niri\" in $CURRENT_DM."
else
    LOGIN_HINT="Log in on a TTY as $TARGET_USER and run:  niri-session"
fi
WARNINGS="$(cat "$WARN_FILE")"
FINAL="$LOGIN_HINT

Noctalia starts automatically with niri.

Keys:
  Mod+Return  terminal ($TERM_APP)
  Mod+Space   launcher            Mod+S  control center
  Mod+O       overview            Mod+Shift+Comma  Noctalia settings
  Mod+Shift+/ all keybinds

Log: $LOG${WARNINGS:+

Warnings:
$WARNINGS}"

if [[ $UI == tui ]]; then
    msg "All done" "$FINAL"
    if [[ $GREETER_ENABLED -eq 1 ]] && ask "Reboot now to start the Noctalia Greeter?" y "Reboot"; then
        clear >/dev/tty
        as_root systemctl reboot
    fi
    clear >/dev/tty
fi
echo
ok "All done."
echo "$FINAL"
echo
