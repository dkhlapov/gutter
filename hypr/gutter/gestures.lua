local vars = require("gutter.vars")
local fn = require("gutter.utils.functions")

-- A finger count of 0, or one outside 2..9, leaves the gesture off.
local function fingers(n)
    n = tonumber(n)
    if n and n >= 2 and n <= 9 then return math.floor(n) end
end

local ws = fingers(vars.gesture_workspace_fingers)
if ws then
    hl.gesture({ fingers = ws, direction = "horizontal", action = "workspace" })
end

local scratch = fingers(vars.gesture_scratch_fingers)
if scratch then
    -- Swipe up opens the scratch workspace, following the fingers
    hl.gesture({ fingers = scratch, direction = "up", action = "special", workspace_name = "special" })

    -- Swipe down closes whichever special workspace is open, and does nothing when none is (a toggle would open one)
    hl.gesture({
        fingers = scratch,
        direction = "down",
        action = function()
            local open = hl.get_active_special_workspace()
            if open and open.name and open.name:sub(1, 8) == "special:" then
                fn.toggle("specialws")()
            end
        end,
    })
end

local sleep = fingers(vars.gesture_sleep_fingers)
if sleep and type(vars.sleep_command) == "string" and vars.sleep_command:match("%S") then
    hl.gesture({
        fingers = sleep,
        direction = "down",
        action = function() hl.exec_cmd(vars.sleep_command) end,
    })
end
