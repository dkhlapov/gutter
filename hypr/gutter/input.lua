local vars = require("gutter.vars")

hl.config({
    input = {
        kb_layout    = "us",
        repeat_rate  = 35,
        repeat_delay = 300,

        follow_mouse = 1,
        -- Switching a window between tiled and floating focuses the one under the cursor
        float_switch_override_focus = 1,

        touchpad = {
            natural_scroll       = true,
            disable_while_typing = vars.touchpad_disable_while_typing,
            scroll_factor        = vars.touchpad_scroll_factor,
        },
    },

    cursor = {
        hide_on_key_press = true,
    },

    binds = {
        -- Pressing the number of the workspace you are on goes back to the previous one
        workspace_back_and_forth = true,
        -- Changing workspace closes an open special workspace
        hide_special_on_workspace_change = true,
    },
})
