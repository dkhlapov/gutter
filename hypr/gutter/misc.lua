hl.config({
    misc = {
        -- No logo, no default wallpaper: the shell draws its own wallpaper
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        background_color         = "rgb(000000)",

        -- Lock screen (Gutter's own client, ext-session-lock-v1)
        -- A crashed or reloaded lock client can start again and take the held lock back instead of leaving the session
        -- stuck locked. The workspaces are not rendered under the lock (session_lock_xray stays off), so nothing leaks
        -- into a frame the client has not drawn yet.
        allow_session_lock_restore = true,
        session_lock_xray          = false,
        session_lock_blur          = false,
        lockdead_screen_delay      = 1500, -- ms before a lock that has no client yet shows the "lockdead" screen

        -- Focus: an app asking for attention does not steal it
        focus_on_activate  = false,
        mouse_move_focuses_monitor = true,

        -- Screens turned off by idle come back on any input
        mouse_move_enables_dpms = true,
        key_press_enables_dpms  = true,

        -- Dragging or resizing a window by hand follows the pointer without easing
        animate_manual_resizes       = false,
        animate_mouse_windowdragging = false,
    },
})
