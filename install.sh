#!/usr/bin/env bash
# =====================================================================
#  niri + Noctalia v5 installer for Arch Linux
#  https://github.com/Abijspy/noctalia-niri-config-setup
#
#  A full-screen installer in Noctalia's colors. Works on a fresh
#  minimal Arch install (bare TTY, even as root): it installs gum
#  itself and repaints the console with the Noctalia palette.
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
#    --no-apps                        # skip file manager and browser
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

usage() { sed -n '3,27p' "${BASH_SOURCE[0]:-$0}" 2>/dev/null | sed 's/^# \{0,1\}//'; }

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

# ---------- plain output helpers ----------
c_blue=$'\e[1;34m'; c_green=$'\e[1;32m'; c_yellow=$'\e[1;33m'; c_red=$'\e[1;31m'; c_off=$'\e[0m'
WARN_FILE="$(mktemp)"
TMP_DIR="$(mktemp -d)"
STATE="$TMP_DIR/state"
UI=plain
INSTALL_STARTED=0

info() { printf '%s==>%s %s\n' "$c_blue" "$c_off" "$*"; }
ok()   { printf '%s ✓ %s %s\n' "$c_green" "$c_off" "$*"; }
warn() { printf '%s !  %s %s\n' "$c_yellow" "$c_off" "$*"; echo "$*" >> "$WARN_FILE"; }
die()  { printf '%s ✗  %s %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }

cleanup() {
    [[ $UI == tui ]] && ui_restore
    rm -rf "$TMP_DIR" "$WARN_FILE"
    [[ -n ${KEEPALIVE_PID:-} ]] && kill "$KEEPALIVE_PID" 2>/dev/null
    true
}
trap cleanup EXIT

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

if [[ $IS_ROOT -eq 0 ]]; then
    info "Administrator rights are needed to install packages."
    sudo -v </dev/tty || die "sudo authentication failed."
    ( while kill -0 $$ 2>/dev/null; do sudo -n true; sleep 45; done ) 2>/dev/null &
    KEEPALIVE_PID=$!
fi

pac_install_quiet() {  # install from the current db; full -Syu only if that fails
    "${SUDO[@]}" pacman -S --needed --noconfirm "$@" >>"$LOG" 2>&1 \
        || "${SUDO[@]}" pacman -Syu --needed --noconfirm "$@" >>"$LOG" 2>&1
}

# =====================================================================
#  Noctalia theme
#  Colors from Noctalia's built-in "Noctalia" palette.
# =====================================================================
#            role        hex     console slot
THEME=(      surface    070722  0
             error      fd4663  1
             tertiary   9bfece  2
             primary    fff59b  3
             dim        7c80b4  4
             secondary  a9aefe  5
             outline    21215f  6
             text       f3edf7  7 )

IS_CONSOLE=0
[[ ${TERM:-} == linux ]] && IS_CONSOLE=1

declare -A HEX SLOT
for ((i = 0; i < ${#THEME[@]}; i += 3)); do
    HEX[${THEME[i]}]=${THEME[i+1]}; SLOT[${THEME[i]}]=${THEME[i+2]}
done

fg() { if [[ $IS_CONSOLE -eq 1 ]]; then printf '\e[3%dm' "${SLOT[$1]}"
       else local h=${HEX[$1]}; printf '\e[38;2;%d;%d;%dm' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"; fi; }
bg() { if [[ $IS_CONSOLE -eq 1 ]]; then printf '\e[4%dm' "${SLOT[$1]}"
       else local h=${HEX[$1]}; printf '\e[48;2;%d;%d;%dm' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"; fi; }
gc() { if [[ $IS_CONSOLE -eq 1 ]]; then echo "${SLOT[$1]}"; else echo "#${HEX[$1]}"; fi; }  # gum color

R=$'\e[0m'; B=$'\e[1m'; EL=$'\e[K'

setup_theme() {
    P="$(fg primary)"; S="$(fg secondary)"; T="$(fg tertiary)"; E="$(fg error)"
    D="$(fg dim)"; O="$(fg outline)"; X="$(fg text)"
    BP="$(bg primary)"; BS="$(bg secondary)"; BO="$(bg outline)"; ON="$(fg surface)"

    if [[ $IS_CONSOLE -eq 1 ]]; then
        # The kernel console's font only has CP437-style glyphs.
        SYM_DONE="√"; SYM_CUR="►"; SYM_TODO="·"; SYM_BUL="•"; SYM_FAIL="x"
        SYM_ARROW="»"; SYM_MOON=""; SYM_X="+"; SYM_ON="■"; SYM_OFF="·"
        BX=(┌ ┐ └ ┘ ─ │); SPIN=('|' '/' '-' '\'); BAR_ON="█"; BAR_OFF="░"
        # Repaint the console palette with Noctalia (bright slots = same colors,
        # since the console shows bold text in the bright slot).
        local i role
        for role in surface error tertiary primary dim secondary outline text; do
            i=${SLOT[$role]}
            printf '\e]P%X%s\e]P%X%s' "$i" "${HEX[$role]}" "$((i + 8))" "${HEX[$role]}" >/dev/tty
        done
    else
        SYM_DONE="✓"; SYM_CUR="●"; SYM_TODO="○"; SYM_BUL="•"; SYM_FAIL="✗"
        SYM_ARROW="›"; SYM_MOON="☾ "; SYM_X="×"; SYM_ON="◉"; SYM_OFF="○"
        BX=(╭ ╮ ╰ ╯ ─ │); SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏); BAR_ON="━"; BAR_OFF="━"
        # Ask xterm-compatible terminals to use Noctalia's surface/text colors.
        printf '\e]11;#%s\a\e]10;#%s\a' "${HEX[surface]}" "${HEX[text]}" >/dev/tty
    fi
    export GUM_CHOOSE_SHOW_HELP=false GUM_INPUT_SHOW_HELP=false   # we draw our own key hints
}

ui_restore() {
    printf '\e[0m\e[?25h' >/dev/tty 2>/dev/null || true
    if [[ $IS_CONSOLE -eq 1 ]]; then printf '\e]R' >/dev/tty 2>/dev/null || true
    else printf '\e]110\a\e]111\a' >/dev/tty 2>/dev/null || true; fi
    printf '\e[H\e[2J' >/dev/tty 2>/dev/null || true
}

# ---------- drawing primitives ----------
COLS=80; ROWS=24
out()  { printf '%s' "$*" >/dev/tty; }
at()   { printf '\e[%d;%dH' "$1" "$2" >/dev/tty; }
cls()  { printf '\e[0m\e[H\e[2J' >/dev/tty; }
vlen() { local s; s="$(printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g')"; echo "${#s}"; }
rep()  { local s="" i; for ((i = 0; i < $2; i++)); do s+="$1"; done; printf '%s' "$s"; }
pill() { printf '%s%s%s %s %s' "$2" "${3:-$ON}" "$B" "$1" "$R"; }   # pill TEXT BG_ESC [FG_ESC]

# Step tracker shown under the header.
STEPS=()
build_steps() {
    STEPS=(Welcome)
    [[ $IS_ROOT -eq 1 ]] && STEPS+=(User)
    STEPS+=(Components Apps Keyboard Review Install)
}

header() {  # header CURRENT_STEP_NAME
    local cur="$1" line="" i name state seen=0
    at 2 3; out "${P}${B}${SYM_MOON}noctalia${R} ${D}${SYM_X}${R} ${S}${B}niri${R}"
    local right="Arch Linux installer"
    at 2 $(( COLS - ${#right} - 2 )); out "${D}${right}${R}"
    at 3 3; out "${O}$(rep "─" $(( COLS - 4 )))${R}"
    for name in "${STEPS[@]}"; do
        if [[ $name == "$cur" ]]; then state=cur; seen=1
        elif [[ $seen -eq 0 ]]; then state="done"
        else state=todo; fi
        case $state in
            done) line+="${T}${SYM_DONE}${R} ${D}${name}${R}  " ;;
            cur)  line+="${P}${SYM_CUR}${R} ${X}${B}${name}${R}  " ;;
            todo) line+="${O}${SYM_TODO}${R} ${D}${name}${R}  " ;;
        esac
    done
    at 4 3; out "$line"
}

footer() {  # footer "key" "label" ["key" "label" ...]
    local line=""
    while (( $# )); do line+="${P}${B}$1${R} ${D}$2${R}    "; shift 2; done
    out $'\e7'; at "$ROWS" 3; out "$line"; out $'\e8'   # save/restore cursor
}

screen() {  # screen STEP "Title" "Subtitle"
    cls; header "$1"
    at 6 3; out "${X}${B}$2${R}"
    [[ -n ${3:-} ]] && { at 7 3; out "${D}$3${R}"; }
    at 9 1
}

card() {  # card ROW "line" "line" ...   (outline border, 2-col padding)
    local row=$1; shift
    local w=$(( COLS - 6 )) l pad
    at "$row" 3; out "${O}${BX[0]}$(rep "${BX[4]}" $(( w - 2 )))${BX[1]}${R}"
    for l in "$@"; do
        row=$((row + 1)); pad=$(( w - 4 - $(vlen "$l") )); (( pad < 0 )) && pad=0
        at "$row" 3; out "${O}${BX[5]}${R} ${l}$(rep " " "$pad") ${O}${BX[5]}${R}"
    done
    row=$((row + 1))
    at "$row" 3; out "${O}${BX[2]}$(rep "${BX[4]}" $(( w - 2 )))${BX[3]}${R}"
}

err_line() { at 8 3; out "${E}${SYM_FAIL} $1${R}"; }

# Read one key: prints enter / esc / other.
read_key() {
    local k rest=""
    IFS= read -rsn1 k </dev/tty || { echo esc; return; }
    if [[ $k == $'\e' ]]; then
        IFS= read -rsn2 -t 0.05 rest </dev/tty || true
        [[ -z $rest ]] && { echo esc; return; }
        echo other; return
    fi
    [[ -z $k ]] && { echo enter; return; }
    echo other
}

# Continue / quit prompt for info screens.
press_continue() {  # press_continue ROW [label]
    at "$1" 3; out "$(pill "${2:-Continue}" "$BP")"
    footer "enter" "continue" "esc" "quit"
    printf '\e[?25l' >/dev/tty
    while true; do
        case "$(read_key)" in
            enter) printf '\e[?25h' >/dev/tty; return 0 ;;
            esc)   printf '\e[?25h' >/dev/tty; [[ $INSTALL_STARTED -eq 0 ]] && cancelled; return 0 ;;
        esac
    done
}

cancelled() {
    ui_restore; UI=plain   # UI=plain: the exit trap must not clear the screen again
    echo "Installer cancelled. No changes were made to your system configuration."
    exit 0
}

# ---------- gum widgets (themed) ----------
gchoose() {  # gchoose [extra gum flags...] -- "Label|value" ...  (labels: no commas, gum --selected splits on them)
    local flags=()
    while [[ $1 != -- ]]; do flags+=("$1"); shift; done; shift
    gum choose --header "" --label-delimiter "|" --show-help=false \
        --cursor "  ${SYM_ARROW} " --cursor.foreground "$(gc primary)" \
        --item.foreground "$(gc text)" --selected.foreground "$(gc primary)" \
        --height 10 "${flags[@]}" "$@" 2>/dev/tty </dev/tty
}

ginput() {  # ginput "placeholder" "value" [--password]
    gum input --placeholder "$1" --value "$2" "${@:3}" --width 50 \
        --prompt "  ${SYM_ARROW} " --prompt.foreground "$(gc primary)" \
        --cursor.foreground "$(gc primary)" --placeholder.foreground "$(gc dim)" \
        2>/dev/tty </dev/tty
}

# ---------- UI setup ----------
init_ui() {
    [[ $ASSUME_YES -eq 1 || $NO_TUI -eq 1 || $HAVE_TTY -eq 0 ]] && return 0
    if ! command -v gum >/dev/null; then
        info "Installing gum for the installer UI…"
        pac_install_quiet gum || { warn "Couldn't install gum — using plain prompts."; return 0; }
    fi
    read -r ROWS COLS < <(stty size </dev/tty 2>/dev/null || echo "24 80")
    if (( ROWS < 22 || COLS < 76 )); then
        warn "Terminal is ${COLS}x${ROWS}; the installer UI needs at least 76x22 — using plain prompts."
        return 0
    fi
    (( COLS > 100 )) && COLS=100
    # Make sure bash and gum handle the UI's UTF-8 characters.
    if locale -a 2>/dev/null | grep -qi '^c\.utf-\?8$'; then export LC_ALL=C.UTF-8; fi
    UI=tui
    setup_theme
    build_steps
}

# ---------- TUI screens ----------
existing_users() { getent passwd | awk -F: '$3>=1000 && $3<60000 && $7 !~ /(nologin|false)$/ {print $1}'; }

scr_welcome() {
    screen "Welcome" "" ""
    at 7 5;  out "${P}${B}█▄ █ █▀█ █▀▀ ▀█▀ ▄▀█ █   █ ▄▀█${R}   ${S}${B}█▄ █ █ █▀█ █${R}"
    at 8 5;  out "${P}${B}█ ▀█ █▄█ █▄▄  █  █▀█ █▄▄ █ █▀█${R}   ${S}${B}█ ▀█ █ █▀▄ █${R}"
    at 10 5; out "${X}A complete Noctalia v5 desktop on the niri compositor.${R}"

    local laptop dm
    [[ $IS_LAPTOP -eq 1 ]] && laptop="$(pill laptop "$BS")" || laptop="$(pill desktop "$BS")"
    [[ -n $CURRENT_DM ]] && dm="$(pill "$CURRENT_DM" "$BO" "$X")" || dm="$(pill "no login manager" "$BO" "$X")"
    card 12 \
        "${P}${SYM_BUL}${R} ${X}niri${R}              ${D}scrollable tiling Wayland compositor${R}" \
        "${P}${SYM_BUL}${R} ${X}Noctalia v5${R}       ${D}bar, launcher, notifications, lock${R}" \
        "${P}${SYM_BUL}${R} ${X}Blur everywhere${R}   ${D}ready-made niri config${R}" \
        "${P}${SYM_BUL}${R} ${X}Noctalia Greeter${R}  ${D}optional login screen (greetd)${R}"
    at 19 5; out "${D}Detected${R}  ${laptop} ${dm}"
    at 20 5; out "${D}Nothing changes until you confirm the review.${R}"
    press_continue 22 "Get started"
}

scr_user() {
    [[ $IS_ROOT -eq 1 ]] || { TARGET_USER="$(id -un)"; return; }
    if [[ -n $TARGET_USER ]]; then
        id "$TARGET_USER" &>/dev/null || CREATE_USER=1
        [[ $CREATE_USER -eq 0 ]] && return
    fi
    local users opts=() u pick
    mapfile -t users < <(existing_users)
    if [[ $CREATE_USER -eq 0 ]]; then
        screen "User" "Who is this desktop for?" "You're running as root. Pick a user, or create one."
        for u in "${users[@]}"; do opts+=("$u|$u"); done
        opts+=("Create a new user|+new")
        footer "↑↓" "move" "enter" "continue" "esc" "quit"
        pick="$(gchoose -- "${opts[@]}")" || cancelled
        [[ $pick == "+new" ]] && CREATE_USER=1 || TARGET_USER="$pick"
    fi
    [[ $CREATE_USER -eq 1 ]] || return 0

    local errmsg=""
    while true; do
        screen "User" "Create a user" "Lowercase letters, digits, - or _. Gets sudo via the wheel group."
        [[ -n $errmsg ]] && err_line "$errmsg"
        footer "enter" "continue" "esc" "quit"
        TARGET_USER="$(ginput "username" "$TARGET_USER")" || cancelled
        if [[ ! $TARGET_USER =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then errmsg="'$TARGET_USER' isn't a valid username."
        elif id "$TARGET_USER" &>/dev/null; then errmsg="'$TARGET_USER' already exists."
        else break; fi
    done
    errmsg=""
    while true; do
        local p1 p2
        screen "User" "Password for $TARGET_USER" "Type it twice. Nothing is shown while typing."
        [[ -n $errmsg ]] && err_line "$errmsg"
        footer "enter" "continue" "esc" "quit"
        p1="$(ginput "password" "" --password)" || cancelled
        at 11 1
        p2="$(ginput "repeat password" "" --password)" || cancelled
        if [[ -z $p1 ]]; then errmsg="The password can't be empty."
        elif [[ $p1 != "$p2" ]]; then errmsg="The passwords didn't match."
        else NEW_USER_PASS="$p1"; break; fi
    done
}

scr_components() {
    local opts=(
        "Apps for the keybinds     terminal · files · browser|apps"
        "Noctalia Greeter          login screen with greetd|greeter"
        "Type-to-launch            type in overview to open the launcher|launch"
        "Polkit agent              Noctalia asks for app passwords|polkit"
    )
    [[ $IS_LAPTOP -eq 1 ]] && opts+=("Lid lock                  lock before suspend on lid close|lid")
    local sel=() o
    for o in "${opts[@]}"; do
        case "${o##*|}" in
            apps) [[ $INSTALL_APPS -eq 1 ]] && sel+=("${o%|*}") ;;
            greeter) [[ $INSTALL_GREETER -eq 1 ]] && sel+=("${o%|*}") ;;
            launch) [[ $TYPE_TO_LAUNCH -eq 1 ]] && sel+=("${o%|*}") ;;
            polkit) [[ $POLKIT_AGENT -eq 1 ]] && sel+=("${o%|*}") ;;
            lid) [[ $LID_FIX -eq 1 ]] && sel+=("${o%|*}") ;;
        esac
    done
    local IFS_old=$IFS; IFS=,; local selected="${sel[*]}"; IFS=$IFS_old

    screen "Components" "Choose your extras" "niri, Noctalia, portals, audio and fonts are always installed."
    footer "↑↓" "move" "space" "toggle" "enter" "continue" "esc" "quit"
    local picked
    picked="$(gchoose --no-limit --selected "$selected" --selected.foreground "$(gc secondary)" \
        --cursor-prefix "${SYM_OFF} " --unselected-prefix "${SYM_OFF} " --selected-prefix "${SYM_ON} " \
        -- "${opts[@]}")" || cancelled
    INSTALL_APPS=0; INSTALL_GREETER=0; TYPE_TO_LAUNCH=0; POLKIT_AGENT=0; LID_FIX=0
    while read -r o; do
        case "$o" in
            apps) INSTALL_APPS=1 ;; greeter) INSTALL_GREETER=1 ;; launch) TYPE_TO_LAUNCH=1 ;;
            polkit) POLKIT_AGENT=1 ;; lid) LID_FIX=1 ;;
        esac
    done <<< "$picked"
}

pick_app() {  # pick_app "Title" "Subtitle" current "Label|value"...
    local title="$1" sub="$2" cur="$3"; shift 3
    local o cur_label=""
    for o in "$@"; do [[ ${o##*|} == "$cur" ]] && cur_label="${o%|*}"; done
    screen "Apps" "$title" "$sub"
    footer "↑↓" "move" "enter" "select" "esc" "quit"
    gchoose --selected "$cur_label" -- "$@"
}

scr_apps() {
    TERM_APP="$(pick_app "Terminal" "Opens with Mod+Return. Always installed." "$TERM_APP" \
        "Alacritty   fast and simple, GPU accelerated|alacritty" \
        "Kitty       GPU, tabs, inline images|kitty" \
        "Foot        tiny and Wayland-native|foot" \
        "Ghostty     modern and GPU accelerated|ghostty" \
        "WezTerm     GPU with a built-in multiplexer|wezterm")" || cancelled
    [[ $INSTALL_APPS -eq 1 ]] || return 0
    FM_APP="$(pick_app "File manager" "Opens with Mod+E." "$FM_APP" \
        "Nautilus    GNOME Files|nautilus" \
        "Thunar      Xfce, lightweight|thunar" \
        "Dolphin     KDE, feature-rich|dolphin" \
        "Nemo        Cinnamon|nemo" \
        "None        leave Mod+E unbound|none")" || cancelled
    BROWSER_APP="$(pick_app "Browser" "Opens with Mod+B." "$BROWSER_APP" \
        "Firefox     Mozilla|firefox" \
        "Chromium    open-source Chrome|chromium" \
        "None        leave Mod+B unbound|none")" || cancelled
}

scr_keyboard() {
    local errmsg=""
    while true; do
        screen "Keyboard" "Keyboard layout" "xkb layout(s), comma separated. Examples: us  de  fr  us,ru"
        [[ -n $errmsg ]] && err_line "$errmsg"
        footer "enter" "continue" "esc" "quit"
        KB_LAYOUT="$(ginput "us" "$KB_LAYOUT")" || cancelled
        [[ $KB_LAYOUT =~ ^[a-z]{2,}(,[a-z]{2,})*$ ]] && break
        errmsg="'$KB_LAYOUT' doesn't look like an xkb layout list."
    done
}

scr_dm() {
    SWITCH_DM=1
    [[ $INSTALL_GREETER -eq 1 && -n $CURRENT_DM ]] || return 0
    screen "Review" "Replace $CURRENT_DM?" "Two login managers can't run together."
    card 9 \
        "${X}${CURRENT_DM}${R} ${D}is your current login manager. Replacing it disables${R}" \
        "${D}it and enables greetd with Noctalia Greeter after the next reboot.${R}" \
        "${D}Your current session keeps running.${R}"
    at 15 1
    footer "↑↓" "move" "enter" "select" "esc" "quit"
    local pick
    pick="$(gchoose -- "Replace it with Noctalia Greeter|yes" "Keep $CURRENT_DM (greeter installed, not enabled)|no")" || cancelled
    [[ $pick == yes ]] && SWITCH_DM=1 || SWITCH_DM=0
}

yesno_chip() { if [[ $1 -eq 1 ]]; then out "${T}${SYM_DONE} on ${R}"; else out "${D}${SYM_TODO} off${R}"; fi; }

scr_review() {
    screen "Review" "Ready to install" "Check your choices. Nothing has changed yet."
    local user_txt="$TARGET_USER" apps_txt="$TERM_APP" greeter_txt
    [[ $CREATE_USER -eq 1 ]] && user_txt="$TARGET_USER ${D}(new, sudo)${R}"
    [[ $INSTALL_APPS -eq 1 ]] && apps_txt="$TERM_APP, $FM_APP, $BROWSER_APP"
    if [[ $INSTALL_GREETER -eq 0 ]]; then greeter_txt="${D}off${R}"
    elif [[ -n $CURRENT_DM && $SWITCH_DM -eq 0 ]]; then greeter_txt="installed ${D}(keeps $CURRENT_DM)${R}"
    elif [[ -n $CURRENT_DM ]]; then greeter_txt="Noctalia Greeter ${D}(replaces $CURRENT_DM)${R}"
    else greeter_txt="Noctalia Greeter"; fi

    local on="${T}${SYM_DONE} on${R}" off="${D}${SYM_TODO} off${R}" tl pa ll
    [[ $TYPE_TO_LAUNCH -eq 1 ]] && tl=$on || tl=$off
    [[ $POLKIT_AGENT -eq 1 ]] && pa=$on || pa=$off
    [[ $LID_FIX -eq 1 ]] && ll=$on || ll=$off
    card 8 \
        "${D}User        ${R}${X}${user_txt}${R}" \
        "${D}Core        ${R}${X}niri, noctalia, portals, pipewire, fonts${R}" \
        "${D}            ${R}${D}runs a full system upgrade (pacman -Syu)${R}" \
        "${D}Apps        ${R}${X}${apps_txt}${R}" \
        "${D}Keyboard    ${R}${X}${KB_LAYOUT}${R}" \
        "${D}Login       ${R}${X}${greeter_txt}${R}" \
        "${D}Extras      ${R}${D}type-to-launch${R} ${tl}   ${D}polkit${R} ${pa}   ${D}lid lock${R} ${ll}"
    at 18 1
    footer "↑↓" "move" "enter" "select" "esc" "quit"
    local pick
    pick="$(gchoose --height 3 -- "Install now|install" "Change my choices|change" "Quit|quit")" || cancelled
    case "$pick" in
        install) return 0 ;;
        change)  return 1 ;;
        *)       cancelled ;;
    esac
}

tui_decisions() {
    scr_welcome
    scr_user
    while true; do
        scr_components
        scr_apps
        scr_keyboard
        scr_dm
        scr_review && break
    done
}

plain_decisions() {
    if [[ $IS_ROOT -eq 1 ]]; then
        local users; mapfile -t users < <(existing_users)
        if [[ -z $TARGET_USER ]]; then
            (( ${#users[@]} == 1 )) || die "Running as root: pass --user=NAME (existing users: ${users[*]:-none}). To create a user, use the TUI."
            TARGET_USER="${users[0]}"
        fi
        id "$TARGET_USER" &>/dev/null || die "User '$TARGET_USER' doesn't exist. Create it first or use the TUI."
    else
        TARGET_USER="$(id -un)"
    fi
    plain_ask() {  # plain_ask "question" default
        local q="$1" def="$2" reply
        [[ $ASSUME_YES -eq 1 ]] && { [[ $def == y ]]; return; }
        [[ $def == y ]] && q+=" [Y/n] " || q+=" [y/N] "
        read -r -p "$q" reply </dev/tty || reply=""
        [[ ${reply:-$def} =~ ^[Yy] ]]
    }
    if [[ $INSTALL_GREETER -eq 1 ]]; then plain_ask "Install Noctalia Greeter (login screen) with greetd?" y || INSTALL_GREETER=0; fi
    if [[ $INSTALL_GREETER -eq 1 && -n $CURRENT_DM ]]; then plain_ask "Disable $CURRENT_DM and use greetd?" y || SWITCH_DM=0; fi
    if [[ $IS_LAPTOP -eq 1 && $LID_FIX -eq 0 ]]; then plain_ask "Laptop detected. Lock before suspend on lid close?" n && LID_FIX=1; fi
    info "User: $TARGET_USER | apps: $([[ $INSTALL_APPS -eq 1 ]] && echo "$TERM_APP $FM_APP $BROWSER_APP" || echo "$TERM_APP") | layout: $KB_LAYOUT"
    plain_ask "Continue with installation (includes pacman -Syu)?" y || die "Aborted."
}

# =====================================================================
#  Install steps
# =====================================================================
# Step list for the install screen (id|label), built from the choices.
INSTALL_STEPS=()
build_install_steps() {
    INSTALL_STEPS=()
    [[ $CREATE_USER -eq 1 ]] && INSTALL_STEPS+=("user|Create user $TARGET_USER")
    INSTALL_STEPS+=("prep|Prepare niri config" "pkgs|Install packages" "files|Write niri and Noctalia config" "check|Validate config")
    [[ $LID_FIX -eq 1 ]] && INSTALL_STEPS+=("lid|Configure lid close")
    if [[ $INSTALL_GREETER -eq 1 ]]; then INSTALL_STEPS+=("greeter|Set up Noctalia Greeter" "dm|Enable the login screen"); fi
    return 0
}

progress() {  # progress PCT STEP_ID "message"
    if [[ $UI == tui ]]; then
        printf '%s %s\n' "$1" "$2" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
        printf '\n==> [%d%%] %s\n' "$1" "$3"
    else
        info "$3"
    fi
}

run_long() {  # run_long FROM TO STEP_ID "message" cmd...  (TUI: creep the bar while it runs)
    local from=$1 to=$2 id=$3 text=$4; shift 4
    if [[ $UI != tui ]]; then "$@"; return $?; fi
    "$@" & local pid=$! p=$from
    while kill -0 "$pid" 2>/dev/null; do
        progress "$p" "$id" "$text"
        (( p < to - 1 )) && p=$((p + 1))
        sleep 2
    done
    wait "$pid"
}

as_root() { "${SUDO[@]}" "$@"; }

mk_user_dir() {
    local d
    for d in "$@"; do
        if [[ $IS_ROOT -eq 1 ]]; then install -d -o "$TARGET_USER" -g "$TARGET_GROUP" "$d"
        else mkdir -p "$d"; fi
    done
}

put_user_file() {  # put_user_file SRC DEST
    if [[ $IS_ROOT -eq 1 ]]; then install -m 644 -o "$TARGET_USER" -g "$TARGET_GROUP" "$1" "$2"
    else install -m 644 "$1" "$2"; fi
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

    if [[ $CREATE_USER -eq 1 ]]; then
        progress 2 user "Creating user $TARGET_USER…"
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
    if [[ $IS_ROOT -eq 1 ]]; then CONFIG_HOME="$TARGET_HOME/.config"
    else CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"; fi
    NIRI_DIR="$CONFIG_HOME/niri"
    NOCTALIA_DIR="$CONFIG_HOME/noctalia"

    progress 4 prep "Preparing niri config…"
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

    local pkgs=(
        niri noctalia xwayland-satellite
        xdg-desktop-portal-gnome xdg-desktop-portal-gtk gnome-keyring
        pipewire wireplumber pipewire-pulse
        playerctl brightnessctl
        noto-fonts noto-fonts-emoji ttf-jetbrains-mono-nerd
    )
    pkgs+=("$TERM_APP")   # always: Mod+Return is your way in
    if [[ $INSTALL_APPS -eq 1 ]]; then
        [[ $FM_APP != none ]] && pkgs+=("$FM_APP")
        [[ $BROWSER_APP != none ]] && pkgs+=("$BROWSER_APP")
    fi
    [[ $INSTALL_GREETER -eq 1 ]] && pkgs+=(noctalia-greeter)
    if [[ $INSTALL_GREETER -eq 1 || $POLKIT_AGENT -eq 1 ]]; then pkgs+=(polkit); fi

    run_long 6 70 pkgs "Upgrading system and installing packages (this can take a while)…" \
        as_root pacman -Syu --needed --noconfirm "${pkgs[@]}" \
        || die "pacman failed — see $LOG"
    ok "Packages installed"

    if pacman -Qq noctalia-shell &>/dev/null || pacman -Qq noctalia-shell-git &>/dev/null; then
        warn "Noctalia v4 (noctalia-shell) is still installed. Remove it once v5 works: sudo pacman -Rns noctalia-shell noctalia-qs"
    fi

    progress 72 files "Installing niri config…"
    mk_user_dir "$CONFIG_HOME" "$NIRI_DIR" "$NOCTALIA_DIR" \
        "$TARGET_HOME/Pictures" "$TARGET_HOME/Pictures/Screenshots" "$TARGET_HOME/Pictures/Wallpapers"
    backup_if_exists "$NIRI_DIR/config.kdl"
    put_user_file "$work" "$NIRI_DIR/config.kdl"
    ok "Installed $NIRI_DIR/config.kdl"

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

    progress 78 check "Validating niri config…"
    if niri validate -c "$NIRI_DIR/config.kdl"; then
        ok "niri config is valid"
    else
        warn "niri validate failed. If it mentions blur or background-effect, update niri. Details in $LOG"
    fi

    if [[ $LID_FIX -eq 1 ]]; then
        progress 80 lid "Configuring lid close…"
        as_root mkdir -p /etc/systemd/logind.conf.d
        printf '[Login]\nHandleLidSwitch=ignore\nHandleLidSwitchExternalPower=ignore\n' \
            | as_root tee /etc/systemd/logind.conf.d/10-noctalia-lid.conf >/dev/null
        ok "Lid close handled by niri/Noctalia (after reboot)"
    fi

    if [[ $INSTALL_GREETER -eq 1 ]]; then
        progress 84 greeter "Configuring greetd for Noctalia Greeter…"
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
        id greeter &>/dev/null || die "User 'greeter' missing (should come with greetd)."
        as_root systemd-tmpfiles --create
        if as_root noctalia-greeter-apply-appearance --setup-system; then
            ok "Greeter config initialised"
        else
            warn "Greeter setup helper failed; run: sudo noctalia-greeter-apply-appearance --setup-system"
        fi

        progress 95 dm "Enabling the login screen…"
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

    progress 100 "done" "Done."
}

# ---------- live install screen ----------
log_tail() {  # last N readable log lines, trimmed to width
    tail -c 6000 "$LOG" 2>/dev/null | tr '\r' '\n' | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' \
        | grep -v '^[[:space:]]*$' | grep -v '^==> \[' | tail -n "$1" | cut -c1-"$(( COLS - 10 ))" \
        | if [[ $IS_CONSOLE -eq 1 ]]; then sed 's/✓/√/g; s/✗/x/g; s/—/-/g; s/…/.../g'; else cat; fi
}

render_install() {  # render_install PID
    local pid=$1 frame=0 pct=0 cur="" i label row line fill w=$(( COLS - 16 ))
    printf '\e[?25l' >/dev/tty
    stty -echo -icanon </dev/tty 2>/dev/null || true   # keys pressed now must not print
    screen "Install" "Installing your desktop" "This can take a while. Please keep this terminal open."
    footer "${SYM_BUL}" "installing, keys are disabled until it finishes"
    while true; do
        [[ -f $STATE ]] && read -r pct cur < "$STATE" || true
        local running=0; kill -0 "$pid" 2>/dev/null && running=1
        local cur_idx=-1
        for i in "${!INSTALL_STEPS[@]}"; do [[ ${INSTALL_STEPS[i]%%|*} == "$cur" ]] && cur_idx=$i; done
        [[ $cur == "done" ]] && cur_idx=${#INSTALL_STEPS[@]}

        row=9
        for i in "${!INSTALL_STEPS[@]}"; do
            label="${INSTALL_STEPS[i]#*|}"
            if (( i < cur_idx )); then line="${T}${SYM_DONE}${R}  ${D}${label}${R}"
            elif (( i == cur_idx )); then
                if [[ $running -eq 1 ]]; then line="${P}${SPIN[frame % ${#SPIN[@]}]}${R}  ${X}${B}${label}${R}"
                else line="${E}${SYM_FAIL}${R}  ${E}${label}${R}"; fi
            else line="${O}${SYM_TODO}${R}  ${D}${label}${R}"; fi
            at "$row" 5; out "${line}${EL}"; row=$((row + 1))
        done

        fill=$(( pct * w / 100 ))
        at $(( row + 1 )) 5
        out "${P}$(rep "$BAR_ON" "$fill")${R}${O}$(rep "$BAR_OFF" $(( w - fill )))${R} ${X}${B}$(printf '%3d%%' "$pct")${R}${EL}"

        local lrow=$(( row + 3 ))
        while IFS= read -r line; do
            at "$lrow" 5; out "${D}${line}${R}${EL}"; lrow=$((lrow + 1))
        done < <(log_tail 4)

        [[ $running -eq 0 ]] && break
        frame=$((frame + 1)); sleep 0.15
    done
    # Drop anything typed during the install, then restore the terminal.
    while IFS= read -rsn1 -t 0.01 _ </dev/tty; do :; done
    stty echo icanon </dev/tty 2>/dev/null || true
    printf '\e[?25h' >/dev/tty
}

scr_failed() {
    screen "Install" "Installation failed" "Nothing after the failed step was changed."
    at 6 3; out "${E}${B}${SYM_FAIL} Installation failed${R}"
    local lines=() l
    while IFS= read -r l; do lines+=("${D}${l}${R}"); done < <(log_tail 9)
    card 8 "${X}Last lines of the log${R}" "" "${lines[@]}"
    at 21 5; out "${D}Full log: ${X}${LOG}${R}"
    press_continue 22 "Exit"
}

scr_done() {
    local login
    if [[ $GREETER_ENABLED -eq 1 ]]; then login="Reboot, pick ${P}Niri${R}${X} in Noctalia Greeter and log in as ${P}${TARGET_USER}${R}"
    elif [[ -n $CURRENT_DM ]]; then login="Log out and pick ${P}Niri${R}${X} in ${CURRENT_DM}"
    else login="Log in on a TTY as ${P}${TARGET_USER}${R}${X} and run ${P}niri-session${R}"; fi

    cls; header "Install"
    local done_line="" name
    for name in "${STEPS[@]}"; do done_line+="${T}${SYM_DONE}${R} ${D}${name}${R}  "; done
    at 4 3; out "$done_line"
    at 6 3; out "${T}${B}${SYM_DONE} Your Noctalia desktop is ready${R}"
    at 7 3; out "${X}${login}${R}"
    keyrow() {  # keyrow KEY LABEL KEY LABEL -> two aligned columns
        local a; a="$(pill "$1" "$BS") ${X}$2${R}"
        printf '%s%s%s' "$a" "$(rep " " $(( 34 - $(vlen "$a") )))" "$(pill "$3" "$BS") ${X}$4${R}"
    }
    card 9 \
        "$(keyrow "Mod+Return" "terminal ($TERM_APP)" "Mod+Space" "launcher")" \
        "$(keyrow "Mod+S" "control center" "Mod+O" "overview")" \
        "$(keyrow "Mod+Shift+," "Noctalia settings" "Mod+Shift+/" "all keys")"
    local row=16 w
    if [[ -s $WARN_FILE ]]; then
        at "$row" 3; out "${P}${B}! Notes${R}"; row=$((row + 1))
        while IFS= read -r w && (( row < 20 )); do
            at "$row" 5; out "${D}$(printf '%s' "$w" | cut -c1-$(( COLS - 8 )))${R}"; row=$((row + 1))
        done < "$WARN_FILE"
        row=$((row + 1))
    fi
    at "$row" 1
    if [[ $GREETER_ENABLED -eq 1 ]]; then
        footer "↑↓" "move" "enter" "select" "esc" "exit"
        local pick
        pick="$(gchoose --height 2 -- "Reboot now|reboot" "Exit to the shell|exit")" || pick="exit"
        if [[ $pick == reboot ]]; then ui_restore; as_root systemctl reboot; fi
    else
        press_continue "$row" "Exit"
    fi
}

# =====================================================================
#  main
# =====================================================================
: > "$LOG"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"

init_ui
if [[ $UI == tui ]]; then tui_decisions; else plain_decisions; fi

INSTALL_STARTED=1
build_install_steps

if [[ $UI == tui ]]; then
    [[ $IS_ROOT -eq 0 ]] && SUDO=(sudo -n)   # sudo must never prompt behind the UI
    trap '' INT                              # don't abort halfway through pacman
    set +e
    ( run_steps ) >>"$LOG" 2>&1 &
    INSTALL_PID=$!
    render_install "$INSTALL_PID"
    wait "$INSTALL_PID"; rc=$?
    set -e
    trap - INT
    if [[ $rc -ne 0 ]]; then
        scr_failed
        ui_restore; UI=plain
        die "Installation failed. Full log: $LOG"
    fi
else
    run_steps
fi

GREETER_ENABLED=0; [[ -f $TMP_DIR/greeter_enabled ]] && GREETER_ENABLED=1

if [[ $UI == tui ]]; then
    scr_done
    ui_restore; UI=plain
fi

echo
ok "All done."
if [[ $GREETER_ENABLED -eq 1 ]]; then echo "Reboot: Noctalia Greeter appears. Pick \"Niri\" and log in as $TARGET_USER."
elif [[ -n $CURRENT_DM ]]; then echo "Log out and pick \"Niri\" in $CURRENT_DM."
else echo "Log in on a TTY as $TARGET_USER and run: niri-session"; fi
[[ -s $WARN_FILE ]] && { echo; echo "Notes:"; sed 's/^/  • /' "$WARN_FILE"; }
echo "Log: $LOG"
