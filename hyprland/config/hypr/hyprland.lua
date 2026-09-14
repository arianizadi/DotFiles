-- Frost / Haunt · Hyprland 0.55+
-- The installer selects this file on versions with the Lua configuration API.
-- Personal changes belong in ~/.config/arian-hypr-local/local.lua.
-- Reference: https://wiki.hypr.land/Configuring/Start/

local config_home = os.getenv("HOME") .. "/.config"
local actions = '"$HOME/.config/arian-hypr/scripts/actions.sh" '

local function load_if_present(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        dofile(path)
    end
end

-- Let VMware advertise the resolution; start at 100% scaling.
-- Add an explicit output rule in local.lua if a different resolution is needed.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

hl.config({
    general = {
        gaps_in = 8,
        gaps_out = 16,
        border_size = 2,
        resize_on_border = true,
        allow_tearing = false,
        layout = "dwindle",
        col = {
            active_border = "rgba(a9d9e8ff)",
            inactive_border = "rgba(33414fcc)",
        },
    },
    decoration = {
        rounding = 12,
        active_opacity = 1,
        inactive_opacity = 1,
        -- Keep compositor cost modest on the VMware virtual GPU.
        blur = { enabled = false },
        shadow = {
            enabled = true,
            range = 12,
            render_power = 3,
            color = "rgba(00000044)",
        },
    },
    animations = { enabled = true },
    dwindle = { preserve_split = true },
    input = {
        kb_layout = "us",
        follow_mouse = 1,
        sensitivity = 0,
        touchpad = { natural_scroll = true },
    },
    misc = {
        disable_hyprland_logo = true,
        force_default_wallpaper = -1,
    },
})

hl.curve("arianEase", { type = "bezier", points = { { 0.22, 1 }, { 0.36, 1 } } })
hl.animation({ leaf = "windows", enabled = true, speed = 3, bezier = "arianEase", style = "popin 96%" })
hl.animation({ leaf = "border", enabled = true, speed = 3, bezier = "arianEase" })
hl.animation({ leaf = "fade", enabled = true, speed = 2, bezier = "arianEase" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 2, bezier = "arianEase", style = "fade" })

-- dofile reloads the selected theme on every config reload (require caches it).
load_if_present(config_home .. "/arian-hypr/current/hyprland.lua")

hl.on("hyprland.start", function()
    hl.exec_cmd('"$HOME/.config/arian-hypr/scripts/session.sh"')
end)

-- Daily tools. Super is the Windows key, or Command when VMware passes it through.
hl.bind("SUPER + Return", hl.dsp.exec_cmd(actions .. "terminal"))
hl.bind("SUPER + Space", hl.dsp.exec_cmd(actions .. "launcher"))
hl.bind("SUPER + E", hl.dsp.exec_cmd(actions .. "files"))
hl.bind("SUPER + W", hl.dsp.exec_cmd(actions .. "browser"))
hl.bind("SUPER + V", hl.dsp.exec_cmd(actions .. "clipboard"))
hl.bind("SUPER + CTRL + V", hl.dsp.exec_cmd(actions .. "clear-clipboard"))
hl.bind("SUPER + L", hl.dsp.exec_cmd(actions .. "lock"))
hl.bind("SUPER + Escape", hl.dsp.exec_cmd(actions .. "power"))
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd(actions .. "screenshot"))
hl.bind("Print", hl.dsp.exec_cmd(actions .. "screenshot"))
hl.bind("SUPER + slash", hl.dsp.exec_cmd(actions .. "help"))
hl.bind("SUPER + comma", hl.dsp.exec_cmd(actions .. "settings"))
hl.bind("SUPER + SHIFT + T", hl.dsp.exec_cmd('"$HOME/.config/arian-hypr/scripts/theme.sh" toggle'))
hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("hyprctl reload"))

-- Windows and workspaces.
hl.bind("SUPER + Q", hl.dsp.window.close())
hl.bind("SUPER + F", hl.dsp.window.fullscreen())
hl.bind("SUPER + ALT + Space", hl.dsp.window.float({ action = "toggle" }))
hl.bind("SUPER + J", hl.dsp.layout("togglesplit"))

for _, direction in ipairs({ "left", "right", "up", "down" }) do
    hl.bind("SUPER + " .. direction, hl.dsp.focus({ direction = direction }))
    hl.bind("SUPER + SHIFT + " .. direction, hl.dsp.window.move({ direction = direction }))
end

for workspace = 1, 9 do
    hl.bind("SUPER + " .. workspace, hl.dsp.focus({ workspace = workspace }))
    hl.bind("SUPER + SHIFT + " .. workspace, hl.dsp.window.move({ workspace = workspace }))
end

hl.bind("ALT + Tab", function()
    hl.dispatch(hl.dsp.window.cycle_next())
    hl.dispatch(hl.dsp.window.bring_to_top())
end)
hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "e-1" }))
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

-- These settings win over defaults and themes and survive repository updates.
load_if_present(config_home .. "/arian-hypr-local/local.lua")
