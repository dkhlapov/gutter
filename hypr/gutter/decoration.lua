local vars = require("gutter.vars")

-- What the generated look leaves alone: it owns rounding, blur, the shadow's colour, size and offset.
hl.config({
    decoration = {
        -- An open special workspace does not dim the windows behind it
        dim_special  = 0.0,
        dim_inactive = false,

        shadow = {
            render_power = vars.shadow_render_power,
        },
    },
})
