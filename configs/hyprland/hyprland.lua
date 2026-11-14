-- =====================================================================
--  Hyprland + Noctalia v5 — ~/.config/hypr/hyprland.lua
--  Hyprland Lua config (hl.* API, Hyprland 0.55+). Noctalia snippets follow
--  https://docs.noctalia.dev/noctalia/compositor-settings/hyprland/
--
--  Mirrors this repo's niri config: same look (12px gaps, 20px corners,
--  Rosé Pine border, soft shadow), blur on every window and on all of
--  Noctalia's surfaces (bar, panels, notifications, OSD, dock), the
--  Noctalia settings window opening maximized, and niri's key scheme.
-- =====================================================================

local mainMod = "SUPER"
local ipc = "noctalia msg "

-- ---------------------------------------------------------------------
-- Environment and autostart
-- ---------------------------------------------------------------------
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

hl.on("hyprland.start", function()
  hl.exec_cmd("noctalia")
end)

-- ---------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------
hl.config({
  input = {
    kb_layout = "us",
    repeat_delay = 300,
    repeat_rate = 40,
    numlock_by_default = true,
    follow_mouse = 1,
    touchpad = {
      natural_scroll = true,
    },
  },

  general = {
    gaps_in = 6,          -- 6 + 6 between windows = niri's 12px gap
    gaps_out = 12,
    border_size = 2,
    col = {
      active_border = { colors = { "rgba(c4a7e7ff)" }, angle = 45 },
      inactive_border = "rgba(26233aff)",
    },
    layout = "dwindle",
  },

  decoration = {
    rounding = 20,
    rounding_power = 2,

    shadow = {
      enabled = true,
      range = 30,
      render_power = 3,
      color = 0x77000000,
    },

    -- Frosted glass like niri: blur what is behind each window,
    -- not just the wallpaper (xray off).
    blur = {
      enabled = true,
      xray = false,
      size = 3,
      passes = 3,
      noise = 0.02,
      vibrancy = 0.1696,
    },
  },

  dwindle = {
    preserve_split = true,
  },

  misc = {
    force_default_wallpaper = 0,
    disable_hyprland_logo = true,
  },
})

-- Three-finger swipe switches workspaces, like niri's touchpad gestures.
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- ---------------------------------------------------------------------
-- Window rules
-- ---------------------------------------------------------------------
-- Noctalia settings: open full size (maximized, not fullscreen), so the
-- bar stays visible and the window keeps its blur.
hl.window_rule({
  name = "noctalia-settings",
  match = { class = "^dev\\.noctalia\\.Noctalia$" },
  maximize = true,
})

-- Small utility windows float, as in the niri config.
hl.window_rule({ name = "float-pip", match = { title = "^Picture-in-Picture$" }, float = true })
hl.window_rule({ name = "float-calculator", match = { class = "^org\\.gnome\\.Calculator$" }, float = true })
hl.window_rule({ name = "float-pavucontrol", match = { class = "^(org\\.pulseaudio\\.)?pavucontrol$" }, float = true })
hl.window_rule({ name = "float-nm-editor", match = { class = "^nm-connection-editor$" }, float = true })

-- ---------------------------------------------------------------------
-- Noctalia layers: no Hyprland animation, blur everywhere
-- ---------------------------------------------------------------------
-- Noctalia animates its own surfaces; Hyprland's layer animations glitch them.
hl.layer_rule({
  name = "noctalia-no-anim",
  match = {
    namespace = "^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd|window-switcher)$",
  },
  no_anim = true,
})

-- Bar, panels, dock, notifications, OSD and window switcher get blur.
hl.layer_rule({
  name = "noctalia-blur",
  match = {
    namespace = "^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd|window-switcher)$",
  },
  ignore_alpha = 0.5,
  blur = true,
  blur_popups = true,
})

-- ---------------------------------------------------------------------
-- Keybinds (same layout as the niri config)
-- ---------------------------------------------------------------------
-- Noctalia
hl.bind(mainMod .. " + Space", hl.dsp.exec_cmd(ipc .. "panel-toggle launcher"))
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd(ipc .. "panel-toggle launcher"))
hl.bind(mainMod .. " + S", hl.dsp.exec_cmd(ipc .. "panel-toggle control-center"))
hl.bind(mainMod .. " + SHIFT + comma", hl.dsp.exec_cmd(ipc .. "settings-toggle"))
hl.bind("ALT + Tab", hl.dsp.exec_cmd(ipc .. "window-switcher hold"))
hl.bind("ALT + SHIFT + Tab", hl.dsp.exec_cmd(ipc .. "window-switcher hold reverse"))

-- Media keys (Noctalia shows its OSD)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(ipc .. "volume-up"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(ipc .. "volume-down"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd(ipc .. "volume-mute"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd(ipc .. "mic-mute"), { locked = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(ipc .. "brightness-up"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(ipc .. "brightness-down"), { locked = true, repeating = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

-- Apps
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd("alacritty"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd("nautilus"))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("firefox"))

-- Windows
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + C", hl.dsp.window.center())
hl.bind(mainMod .. " + W", hl.dsp.group.toggle())
hl.bind(mainMod .. " + R", hl.dsp.layout("togglesplit"))

-- Focus: arrows / HJKL. Move: Mod+Ctrl + direction.
local dirs = {
  { "left", "left" }, { "right", "right" }, { "up", "up" }, { "down", "down" },
  { "H", "left" }, { "L", "right" }, { "K", "up" }, { "J", "down" },
}
for _, d in ipairs(dirs) do
  hl.bind(mainMod .. " + " .. d[1], hl.dsp.focus({ direction = d[2] }))
  hl.bind(mainMod .. " + CTRL + " .. d[1], hl.dsp.window.move({ direction = d[2] }))
end

-- Resize: Mod+Minus/Equal width, Mod+Shift+Minus/Equal height
hl.bind(mainMod .. " + minus", hl.dsp.window.resize({ x = -80, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + equal", hl.dsp.window.resize({ x = 80, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + SHIFT + minus", hl.dsp.window.resize({ x = 0, y = -80, relative = true }), { repeating = true })
hl.bind(mainMod .. " + SHIFT + equal", hl.dsp.window.resize({ x = 0, y = 80, relative = true }), { repeating = true })

-- Monitors: Mod+Shift+Left/Right focus, Mod+Shift+Ctrl+Left/Right move the window
hl.bind(mainMod .. " + SHIFT + left", hl.dsp.focus({ monitor = "l" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.focus({ monitor = "r" }))
hl.bind(mainMod .. " + SHIFT + CTRL + left", hl.dsp.window.move({ monitor = "l" }))
hl.bind(mainMod .. " + SHIFT + CTRL + right", hl.dsp.window.move({ monitor = "r" }))

-- Workspaces: Mod+1..9, Mod+Ctrl+1..9 moves the window
for i = 1, 9 do
  hl.bind(mainMod .. " + " .. i, hl.dsp.focus({ workspace = i }))
  hl.bind(mainMod .. " + CTRL + " .. i, hl.dsp.window.move({ workspace = i }))
end
-- Next/previous workspace: Page_Down/Page_Up or U/I, wheel too
hl.bind(mainMod .. " + Page_Down", hl.dsp.focus({ workspace = "r+1" }))
hl.bind(mainMod .. " + Page_Up", hl.dsp.focus({ workspace = "r-1" }))
hl.bind(mainMod .. " + U", hl.dsp.focus({ workspace = "r+1" }))
hl.bind(mainMod .. " + I", hl.dsp.focus({ workspace = "r-1" }))
hl.bind(mainMod .. " + CTRL + Page_Down", hl.dsp.window.move({ workspace = "r+1" }))
hl.bind(mainMod .. " + CTRL + Page_Up", hl.dsp.window.move({ workspace = "r-1" }))
hl.bind(mainMod .. " + CTRL + U", hl.dsp.window.move({ workspace = "r+1" }))
hl.bind(mainMod .. " + CTRL + I", hl.dsp.window.move({ workspace = "r-1" }))
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Move / resize with the mouse
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Screenshots (Noctalia)
hl.bind("Print", hl.dsp.exec_cmd(ipc .. "screenshot-region"))
hl.bind("CTRL + Print", hl.dsp.exec_cmd(ipc .. "screenshot-fullscreen"))
hl.bind("ALT + Print", hl.dsp.exec_cmd(ipc .. "screenshot-annotate"))

-- Session
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd(ipc .. "dpms-off"))
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exit())
hl.bind("CTRL + ALT + Delete", hl.dsp.exit())
