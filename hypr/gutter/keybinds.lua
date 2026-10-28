local vars = require("gutter.vars")
local fn = require("gutter.utils.functions")

-- Flatten a key, list, or nested lists into non-blank strings.
local function keys_of(spec, out)
  out = out or {}
  if type(spec) == "string" then
    if spec:match("%S") then out[#out + 1] = spec end
  elseif type(spec) == "table" then
    for _, v in ipairs(spec) do keys_of(v, out) end
  end
  return out
end

local function is_pointer(key)
  return key:find("mouse", 1, true) ~= nil
end

-- A chord that ends in a modifier key itself (a bare tap of SUPER) can only fire when that key is released.
local MODIFIER_KEYS = { super_l = true, super_r = true, shift_l = true, shift_r = true,
                        control_l = true, control_r = true, alt_l = true, alt_r = true }
local function ends_in_modifier(key)
  local last = key:match("([^%s+]+)%s*$")
  return last ~= nil and MODIFIER_KEYS[last:lower()] == true
end

-- flags: locked, repeating, mouse, release, non_consuming
local function bind(spec, action, flags)
  flags = flags or {}
  for _, key in ipairs(keys_of(spec)) do
    local opts = {}
    for k, v in pairs(flags) do opts[k] = v end
    if is_pointer(key) then opts.repeating = nil end
    if ends_in_modifier(key) then opts.release = true end
    hl.bind(key, action, opts)
  end
end

local function glob(name) return hl.dsp.global("gutter:" .. name) end
local function run(cmd) return hl.dsp.exec_cmd(cmd) end
local function cmd_of(v)
  if type(v) == "string" and v:match("%S") then return run(v) end
  return hl.dsp.no_op()
end

-- Shell
bind(vars.bind_toggle_shell, glob("toggle"))
bind(vars.bind_launcher, glob("launcher"))
bind(vars.bind_session, glob("session"))
bind(vars.bind_lock, glob("lock"))
bind("Caps_Lock", glob("capsLock"), { locked = true, non_consuming = true })
bind("Num_Lock", glob("numLock"), { locked = true, non_consuming = true })
bind(vars.bind_brightness_up, glob("brightnessUp"), { locked = true })
bind(vars.bind_brightness_down, glob("brightnessDown"), { locked = true })

bind(vars.bind_media_toggle, glob("mediaToggle"), { locked = true })
bind(vars.bind_media_next, glob("mediaNext"), { locked = true })
bind(vars.bind_media_prev, glob("mediaPrev"), { locked = true })
bind(vars.bind_media_stop, glob("mediaStop"), { locked = true })
bind(vars.bind_volume_mute, glob("volumeMute"), { locked = true })
bind(vars.bind_volume_up, glob("volumeUp"), { locked = true, repeating = true })
bind(vars.bind_volume_down, glob("volumeDown"), { locked = true, repeating = true })
bind(vars.bind_mic_mute, run("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })

-- Workspaces by number
local function modded(mod, key)
  if type(mod) ~= "string" or not mod:match("%S") then return nil end
  return mod .. " + " .. key
end

for slot = 1, 10 do
  local digit = tostring(slot % 10)
  bind(modded(vars.mod_workspace_go, digit), fn.wsaction("focus", "decade", slot))
  bind(modded(vars.mod_workspace_move, digit), fn.wsaction("move", "decade", slot))
  bind(modded(vars.mod_workspace_group_go, digit), fn.wsaction("focus", "group", slot))
  bind(modded(vars.mod_workspace_group_move, digit), fn.wsaction("move", "group", slot))
end

-- Workspace stepping
bind(vars.bind_workspace_prev, hl.dsp.focus({ workspace = "-1" }), { repeating = true })
bind(vars.bind_workspace_next, hl.dsp.focus({ workspace = "+1" }), { repeating = true })
bind(vars.bind_workspace_group_prev, hl.dsp.focus({ workspace = "-10" }), { repeating = true })
bind(vars.bind_workspace_group_next, hl.dsp.focus({ workspace = "+10" }), { repeating = true })
bind(vars.bind_move_window_next, hl.dsp.window.move({ workspace = "+1" }), { repeating = true })
bind(vars.bind_move_window_prev, hl.dsp.window.move({ workspace = "-1" }), { repeating = true })
bind(vars.bind_move_to_scratch, hl.dsp.window.move({ workspace = "special:special" }))
bind(vars.bind_move_from_scratch, hl.dsp.window.move({ workspace = "e+0" }))
bind(vars.bind_scratch_toggle, fn.toggle("specialws"))
bind(vars.bind_game_toggle, fn.toggle("game"))

-- Groups and cycling
bind(vars.bind_cycle_next, hl.dsp.window.cycle_next({ next = true }), { repeating = true })
bind(vars.bind_cycle_prev, hl.dsp.window.cycle_next({ next = false }), { repeating = true })
bind(vars.bind_group_next, hl.dsp.group.next(), { repeating = true })
bind(vars.bind_group_prev, hl.dsp.group.prev(), { repeating = true })
bind(vars.bind_group_toggle, hl.dsp.group.toggle())
bind(vars.bind_group_leave, hl.dsp.window.move({ out_of_group = true }))
bind(vars.bind_group_lock, hl.dsp.group.lock_active({ action = "toggle" }))

-- Windows
for key, dir in pairs({ Left = "left", Right = "right", Up = "up", Down = "down" }) do
  bind(modded(vars.mod_focus_direction, key), hl.dsp.focus({ direction = dir }))
  bind(modded(vars.mod_move_direction, key), hl.dsp.window.move({ direction = dir }))
end

bind(vars.bind_resize_narrower, fn.resize_active_window(-10, 0), { repeating = true })
bind(vars.bind_resize_wider, fn.resize_active_window(10, 0), { repeating = true })
bind(vars.bind_resize_shorter, fn.resize_active_window(0, -10), { repeating = true })
bind(vars.bind_resize_taller, fn.resize_active_window(0, 10), { repeating = true })

bind(vars.bind_drag_window, hl.dsp.window.drag(), { mouse = true })
bind(vars.bind_drag_resize, hl.dsp.window.resize(), { mouse = true })
bind(vars.bind_center_window, hl.dsp.window.center())

bind(vars.bind_default_size, function()
  local size = fn.resize_by_screen(55, 70)
  if size then hl.dispatch(hl.dsp.window.resize(size)) end
  hl.dispatch(hl.dsp.window.center())
end)

bind(vars.bind_pip, function()
  local win = hl.get_active_window()
  if not win then return end
  local ref = "address:" .. tostring(win.address)
  if not win.floating then
    hl.dispatch(hl.dsp.window.float({ action = "enable", window = ref }))
  end
  local moves = fn.move_actions(win)
  if moves then
    for _, a in ipairs(moves) do hl.dispatch(a) end
  end
  hl.dispatch(hl.dsp.window.pin({ action = "enable", window = ref }))
end)

bind(vars.bind_pin, hl.dsp.window.pin({ action = "toggle" }))
bind(vars.bind_fullscreen, hl.dsp.window.fullscreen({ mode = "fullscreen" }))
bind(vars.bind_maximize, hl.dsp.window.fullscreen({ mode = "maximized" }))
bind(vars.bind_toggle_floating, hl.dsp.window.float({ action = "toggle" }))
bind(vars.bind_close_window, hl.dsp.window.close())

-- Apps
bind(vars.bind_terminal, cmd_of(vars.terminal))
bind(vars.bind_browser, cmd_of(vars.browser))
bind(vars.bind_editor, cmd_of(vars.editor))
bind(vars.bind_file_manager, cmd_of(vars.file_manager))
bind(vars.bind_audio_mixer, cmd_of(vars.audio_mixer))
bind(vars.bind_color_picker, run("hyprpicker -a"))
bind(vars.bind_sleep, cmd_of(vars.sleep_command), { locked = true })
