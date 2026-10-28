local vars = require("gutter.vars")
local fn = require("gutter.utils.functions")

-- Tagging rules come first: Hyprland needs a tag set before a rule can read it.
local function tag(name, match)
  hl.window_rule({ match = match, tag = "+" .. name })
end

local function tag_classes(name, classes)
  for _, c in ipairs(classes) do tag(name, { class = c }) end
end

-- float
tag_classes("float", {
  "^(wev)$", "^(blueman-manager)$", "^(yad)$", "^(zenity)$",
  "^(file-roller)$", "^(org\\.gnome\\.FileRoller)$", "^(org\\.quickshell)$",
  "^(steam)$", -- every Steam window floats; the main one is taken back out below
})
for _, t in ipairs({
  "^(File Operation Progress)$", "^(Copying.*)$", "^(Moving.*)$", "^(Deleting.*)$",
  "^(.* Properties)$", "^(Rename.*)$",
}) do
  tag("float", { title = t })
end

-- sized floats
tag_classes("float_small", { "^(nwg-look)$", "^(system-config-printer.*)$" })
tag_classes("float_medium", { "^(org\\.pulseaudio\\.pavucontrol)$", "^(com\\.saivert\\.pwvucontrol)$" })
for _, t in ipairs({
  "^(Open File)$", "^(Select a File)$", "^(Choose Files?)$", "^(Select a Folder)$",
  "^(Open Folder)$", "^(Save As)$", "^(Save File)$", "^(Library)$",
}) do
  tag("float_medium", { title = t })
end
tag_classes("float_large", { "^(org\\.gnome\\.Settings)$" })

-- opaque
tag_classes("opaque", {
  "^(foot)$", "^(org\\.quickshell)$", "^(feh)$", "^(imv)$", "^(swappy)$", "^(krita)$", "^(gimp.*)$",
  "^(org\\.inkscape\\.Inkscape)$", "^(inkscape)$", "^(darktable)$", "^(resolve)$",
  "^(kdenlive)$", "^(org\\.kde\\.kdenlive)$", "^(shotcut)$", "^(Shotcut)$",
  "^(blender)$", "^(Blender)$", "^(Godot)$", "^(godot)$",
})

-- game
tag_classes("game", { "^(steam_app_\\d+)$", "^(steam_app_default)$", "^(gamescope)$" })

-- xwayland popups
hl.window_rule({
  match = { xwayland = true, class = "^$", title = "^$", initial_title = "^$", initial_class = "^$" },
  tag = "+xpopup",
})
hl.window_rule({ match = { xwayland = true, title = "^(win\\d+)$" }, tag = "+xpopup" })
-- Steam's title-less windows are popups; its main window stays tiled
hl.window_rule({ match = { class = "^(steam)$", title = "^$" }, tag = "+xpopup" })
hl.window_rule({ match = { class = "^(steam)$", title = "^$" }, tag = "-float" })
hl.window_rule({ match = { class = "^(steam)$", title = "^(Steam)$" }, tag = "-float" })

-- effects, one rule per tag
hl.window_rule({ match = { tag = "float" }, float = true })
for name, size in pairs({
  float_small = { "monitor_w*0.5", "monitor_h*0.6" },
  float_medium = { "monitor_w*0.6", "monitor_h*0.7" },
  float_large = { "monitor_w*0.7", "monitor_h*0.8" },
}) do
  hl.window_rule({ match = { tag = name }, float = true, center = true, size = size })
end
hl.window_rule({ match = { tag = "opaque" }, opaque = true })
hl.window_rule({
  match = { tag = "game" },
  opaque = true, immediate = true, idle_inhibit = "always", workspace = "special:game",
})
hl.window_rule({ match = { tag = "xpopup" }, no_dim = true, no_shadow = true, no_blur = true, opaque = true })

hl.window_rule({ match = { class = ".*" }, suppress_event = "maximize" })
hl.window_rule({ match = { float = true, xwayland = false }, center = true })

-- picture in picture
hl.window_rule({
  match = { title = "^([Pp]icture[- ]in[- ][Pp]icture)$" },
  float = true,
  pin = true,
  keep_aspect_ratio = true,
  move = { "monitor_w*0.98-window_w", "monitor_h*0.97-window_h" },
})

-- Some browsers set the title after the window opens.
local function pip_fixup(win)
  fn.resizer(win, "^[Pp]icture[- ]in[- ][Pp]icture$", 0, 0, fn.move_actions(win), false)
end
hl.on("window.open", pip_fixup)
hl.on("window.title", pip_fixup)

-- workspace rules
for _, sel in ipairs({ "w[tv1]s[false]", "f[1]s[false]", "s[true]" }) do
  hl.workspace_rule({ workspace = sel, gaps_out = vars.gaps_outer_alone })
end

-- layers
for _, ns in ipairs({ "hyprpicker", "logout_dialog", "selection", "wayfreeze", "gutter-wallpaper" }) do
  hl.layer_rule({ match = { namespace = ns }, animation = "fade" })
end
hl.layer_rule({ match = { namespace = "launcher" }, animation = "popin 80%", blur = true })
