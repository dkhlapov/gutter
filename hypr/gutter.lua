-- Gutter's Hyprland config. The loader (hypr/loader.lua.in) puts this folder on package.path and runs this file.
--   ${XDG_CONFIG_HOME:-~/.config}/gutter/hypr-vars.lua   user overrides of gutter.vars, loaded first
--   ${XDG_CONFIG_HOME:-~/.config}/gutter/hypr-user.lua   the user's own config, loaded last
--   ${XDG_STATE_HOME:-~/.local/state}/gutter/hypr-gutter.lua   the generated look (tools/hypr.py), loaded before hypr-user
local home   = os.getenv("HOME") or ""
local config = (os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")) .. "/gutter"
local state  = (os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")) .. "/gutter"
-- The loader sets package.path; this adds the two user folders only when it did not (a direct verify of this file).
-- Appended, so the repo's own modules always win over a file of the same name in these folders.
local function append_path(dir)
    local entry = dir .. "/?.lua"
    if not (";" .. package.path .. ";"):find(";" .. entry .. ";", 1, true) then
        package.path = package.path .. ";" .. entry
    end
end
append_path(config)
append_path(state)

-- Requires a module that may not exist. In Hyprland 0.56 a missing module makes require raise, which is fine here,
-- but a broken one does not raise: Hyprland records the error itself (the config error bar, and a failing
-- `Hyprland --verify-config`, which the migration refuses) and require returns an empty table.
local function optional(name)
    local ok, result = pcall(require, name)
    return ok and result or nil
end

-- User variables
local vars = require("gutter.vars")
local overrides = optional("hypr-vars")
if type(overrides) == "table" then
    for k, v in pairs(overrides) do
        vars[k] = v
    end
end

-- Default monitor conf
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
})

-- Configs
require("gutter.env")
require("gutter.general")
require("gutter.input")
require("gutter.misc")
require("gutter.animations")
require("gutter.decoration")
require("gutter.group")
require("gutter.execs")
require("gutter.rules")
require("gutter.gestures")

-- The keybinds are loaded like the loader loads this file, because require would not raise for a broken module and
-- the session would have no binds at all. The failsafe (set by the loader) binds SUPER + Return to a terminal.
local keybinds_path = package.searchpath("gutter.keybinds", package.path)
local keybinds_ok, keybinds_err = false, 'module "gutter.keybinds" not found in ' .. package.path
if keybinds_path then
    local chunk
    chunk, keybinds_err = loadfile(keybinds_path)
    if chunk then
        keybinds_ok, keybinds_err = pcall(chunk, "gutter.keybinds", keybinds_path)
    end
end
if not keybinds_ok then
    local failsafe = rawget(_G, "GutterFailsafe")
    if failsafe then
        failsafe(keybinds_err, false)
    else
        hl.bind("SUPER + Return", hl.dsp.exec_cmd("foot")) -- not started by the loader: only the bind
    end
end


-- The generated look (borders, rounding, shadow, blur, opacity, window animations), then the user's config
optional("hypr-gutter")
optional("hypr-user")
