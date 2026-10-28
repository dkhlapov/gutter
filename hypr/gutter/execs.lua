local vars = require("gutter.vars")

local polkit_agents = {
  "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1",
  "/usr/libexec/polkit-gnome/polkit-gnome-authentication-agent-1",
  "/usr/libexec/polkit-gnome-authentication-agent-1",
  "/usr/lib/polkit-gnome-authentication-agent-1",
  "/usr/lib/x86_64-linux-gnu/polkit-gnome/polkit-gnome-authentication-agent-1",
  "/usr/lib/x86_64-linux-gnu/libexec/polkit-kde-authentication-agent-1",
  "/usr/lib/kf6/polkit-kde-authentication-agent-1",
  "/usr/libexec/kf6/polkit-kde-authentication-agent-1",
  "/usr/lib/polkit-kde-authentication-agent-1",
  "/usr/libexec/polkit-kde-authentication-agent-1",
}

local function polkit_command()
  local parts = {}
  for _, p in ipairs(polkit_agents) do
    parts[#parts + 1] = string.format("[ -x %s ] && exec %s", p, p)
  end
  return "systemctl --user start hyprpolkitagent.service || { "
    .. table.concat(parts, "; ") .. "; }"
end

hl.on("hyprland.start", function()
  hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE")
  hl.exec_cmd("sh -c '" .. polkit_command():gsub("'", "'\\''") .. "'")
  hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
  hl.exec_cmd("wl-paste --type text --watch cliphist store")
  hl.exec_cmd("wl-paste --type image --watch cliphist store")

  local theme = vars.cursor_theme
  if type(theme) == "string" and theme ~= "" then
    local size = vars.cursor_size or 24
    hl.exec_cmd(string.format("hyprctl setcursor %s %s", theme, size))
    hl.exec_cmd(string.format("gsettings set org.gnome.desktop.interface cursor-theme '%s'", theme))
    hl.exec_cmd(string.format("gsettings set org.gnome.desktop.interface cursor-size %s", size))
  end

  hl.exec_cmd("qs -c gutter -n -d")
end)
