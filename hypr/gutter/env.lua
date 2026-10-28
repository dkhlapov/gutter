local vars = require("gutter.vars")

local function env(name, value)
    hl.env(name, tostring(value))
end

-- Who we are to portals, toolkits and the desktop-entry filters. Hyprland warns when XDG_CURRENT_DESKTOP is not "Hyprland".
env("XDG_CURRENT_DESKTOP", "Hyprland")
env("XDG_SESSION_TYPE", "wayland")
env("XDG_SESSION_DESKTOP", "Hyprland")

-- Qt: Wayland first, X11 as the fallback. Gutter themes Qt apps through qtengine (tools/apps.py).
env("QT_QPA_PLATFORM", "wayland;xcb")
env("QT_QPA_PLATFORMTHEME", "qtengine")
env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")

-- GTK, Electron and Chromium, Firefox, Clutter, Java
env("GDK_BACKEND", "wayland,x11,*")
env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
env("MOZ_ENABLE_WAYLAND", "1")
env("CLUTTER_BACKEND", "wayland")
env("_JAVA_AWT_WM_NONREPARENTING", "1")

-- Cursor: only when the user named a theme (an empty cursor_theme leaves the cursor alone)
if type(vars.cursor_theme) == "string" and vars.cursor_theme ~= "" then
    local size = vars.cursor_size or 24
    env("XCURSOR_THEME", vars.cursor_theme)
    env("XCURSOR_SIZE", size)
    env("HYPRCURSOR_THEME", vars.cursor_theme)
    env("HYPRCURSOR_SIZE", size)
end
