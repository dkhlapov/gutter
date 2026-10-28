local vars = require("gutter.vars")

-- Layout, gaps and resizing. Border size, border colours and rounding belong to the generated look (tools/hypr.py).
hl.config({
    general = {
        layout = "dwindle",

        gaps_in         = vars.gaps_inner,
        gaps_out        = vars.gaps_outer,
        gaps_workspaces = vars.gaps_workspaces,

        -- Drag a border or a gap to resize
        resize_on_border        = true,
        extend_border_grab_area = 12,
        hover_icon_on_border    = true,

        -- Floating windows snap to the screen edge and to each other
        snap = {
            enabled      = true,
            window_gap   = 12,
            monitor_gap  = 12,
            respect_gaps = true,
        },

        -- Allows tearing; the `immediate` rule on tagged games (rules.lua) is what asks for it
        allow_tearing = true,
    },

    dwindle = {
        preserve_split  = true,
        smart_resizing  = true,
        force_split     = 2, -- new windows open to the right of / below the focused one
    },
})
