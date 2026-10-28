-- Settings you can override. A partial table returned from ~/.config/gutter/hypr-vars.lua is merged over this one,
-- key by key (hypr/gutter.lua), so list only what you change.
--
-- A bind setting is one chord ("SUPER + F"), a list of chords, or "" to turn the bind off. Hyprland's key names
-- apply (SUPER, SHIFT, CTRL, ALT; Return, Space, Tab, Page_Up, comma, XF86AudioMute, mouse:272, mouse_up ...).
-- A finger count of 0 turns a gesture off.
return {
    -- Programs, started by their binds
    terminal     = "foot",
    browser      = "firefox",
    editor       = "code",
    file_manager = "thunar",
    audio_mixer  = "pavucontrol",

    -- Cursor. An empty theme leaves the cursor alone: no environment variables, no hyprctl setcursor, no gsettings.
    cursor_theme = "",
    cursor_size  = 24,

    -- Touchpad
    touchpad_disable_while_typing = true,
    touchpad_scroll_factor        = 0.7, -- 1 is the libinput default speed

    -- Touchpad gestures: finger counts. Workspace swipe is horizontal; the scratch gestures swipe up to open and
    -- down to close; the sleep gesture swipes down.
    gesture_workspace_fingers = 3,
    gesture_scratch_fingers   = 4,
    gesture_sleep_fingers     = 5,
    sleep_command             = "systemctl suspend", -- sleep bind and sleep gesture

    -- Window shadows: how fast the falloff is rendered, 1 to 4 (the colour and size come from the generated look)
    shadow_render_power = 3,

    -- Gaps in pixels
    gaps_workspaces  = 0,  -- between workspaces while switching
    gaps_inner       = 5,  -- between windows
    gaps_outer       = 10, -- between windows and the screen edge
    gaps_outer_alone = 20, -- the same for a window alone on its workspace, and for any special workspace (the pill floats above it)

    -- Modifiers of the workspace-number binds (SUPER + 1 .. 0). The "group" variants keep the position inside
    -- the group of ten and change the group: with workspace 13 active, group 2 + key 5 goes to 25.
    mod_workspace_go         = "SUPER",
    mod_workspace_move       = "SUPER + SHIFT",
    mod_workspace_group_go   = "SUPER + ALT",
    mod_workspace_group_move = "SUPER + SHIFT + ALT",

    -- Modifiers of the arrow-key binds
    mod_focus_direction = "SUPER",
    mod_move_direction  = "SUPER + SHIFT",

    -- Shell
    bind_launcher     = { "SUPER + SUPER_L", "SUPER + Space" }, -- a bare tap of SUPER (on release), or SUPER + Space
    bind_toggle_shell = "SUPER + I",
    bind_session      = "CTRL + ALT + Delete",
    bind_lock         = "SUPER + L",
    bind_sleep        = "SUPER + SHIFT + L",

    -- Media and volume
    bind_media_toggle = { "XF86AudioPlay", "XF86AudioPause", "SUPER + ALT + Space" },
    bind_media_next   = { "XF86AudioNext", "SUPER + ALT + Right" },
    bind_media_prev   = { "XF86AudioPrev", "SUPER + ALT + Left" },
    bind_media_stop   = "XF86AudioStop",
    bind_volume_mute  = { "XF86AudioMute", "SUPER + ALT + M" },
    bind_volume_up    = "XF86AudioRaiseVolume",
    bind_volume_down  = "XF86AudioLowerVolume",
    bind_mic_mute     = "XF86AudioMicMute",
    bind_brightness_up   = "XF86MonBrightnessUp",
    bind_brightness_down = "XF86MonBrightnessDown",

    -- Apps
    bind_terminal     = { "SUPER + T", "SUPER + Return" },
    bind_browser      = "SUPER + W",
    bind_editor       = "SUPER + SHIFT + E",
    bind_file_manager = "SUPER + E",
    bind_audio_mixer  = "SUPER + CTRL + V",
    bind_color_picker = "SUPER + X",

    -- Workspaces
    bind_workspace_prev       = { "SUPER + Page_Up", "SUPER + mouse_up" },
    bind_workspace_next       = { "SUPER + Page_Down", "SUPER + mouse_down" },
    bind_workspace_group_prev = "SUPER + CTRL + Page_Up",
    bind_workspace_group_next = "SUPER + CTRL + Page_Down",
    bind_move_window_prev     = "SUPER + SHIFT + Page_Up",
    bind_move_window_next     = "SUPER + SHIFT + Page_Down",
    bind_scratch_toggle       = "SUPER + S",
    bind_game_toggle          = "SUPER + G",
    bind_move_to_scratch      = "SUPER + ALT + S",
    bind_move_from_scratch    = "SUPER + ALT + R", -- to the regular workspace under the special one

    -- Window cycling and groups
    bind_cycle_next       = "ALT + Tab",
    bind_cycle_prev       = "ALT + SHIFT + Tab",
    bind_group_next       = "SUPER + Tab",
    bind_group_prev       = "SUPER + SHIFT + Tab",
    bind_group_toggle     = "SUPER + K",
    bind_group_leave      = "SUPER + SHIFT + K", -- take the window out of its group
    bind_group_lock       = "SUPER + CTRL + K",

    -- Windows
    bind_resize_narrower  = "SUPER + CTRL + Left",
    bind_resize_wider     = "SUPER + CTRL + Right",
    bind_resize_shorter   = "SUPER + CTRL + Up",
    bind_resize_taller    = "SUPER + CTRL + Down",
    bind_drag_window      = "SUPER + mouse:272",
    bind_drag_resize      = "SUPER + mouse:273",
    bind_center_window    = "SUPER + C",
    bind_default_size     = "SUPER + SHIFT + C", -- a comfortable size, centred
    bind_pip              = "SUPER + SHIFT + P", -- float, shrink to the corner and pin
    bind_pin              = "SUPER + P",
    bind_fullscreen       = "SUPER + F",
    bind_maximize         = "SUPER + SHIFT + F", -- fullscreen that keeps the bar and gaps
    bind_toggle_floating  = "SUPER + V",
    bind_close_window     = { "SUPER + Q", "ALT + F4" },
}
