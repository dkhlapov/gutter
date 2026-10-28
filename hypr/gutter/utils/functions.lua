local M = {}

local function num(v, default)
  v = tonumber(v)
  if v == nil then return default end
  return v
end

-- Window/monitor objects may expose size as {x,y}, {w,h} or flat fields.
local function size_of(obj)
  if not obj then return nil end
  local s = obj.size
  if type(s) == "table" then
    local w, h = tonumber(s.x or s.w or s.width or s[1]), tonumber(s.y or s.h or s.height or s[2])
    if w and h then return w, h end
  end
  local w, h = tonumber(obj.width), tonumber(obj.height)
  if w and h then return w, h end
  return nil
end

local function active_monitor()
  local ok, mon = pcall(hl.get_active_monitor)
  if ok then return mon end
end

local function win_ref(win)
  return "address:" .. tostring(win.address)
end

function M.wsaction(verb, scope, slot)
  return function()
    local ws = hl.get_active_workspace()
    if not ws or not ws.id then return end
    local id = tonumber(ws.id)
    if not id or id < 1 then return end
    local target
    if scope == "group" then
      local position = ((id - 1) % 10) + 1
      target = (slot - 1) * 10 + position
    else
      target = math.floor((id - 1) / 10) * 10 + slot
    end
    if verb == "move" then
      hl.dispatch(hl.dsp.window.move({ workspace = target }))
    else
      hl.dispatch(hl.dsp.focus({ workspace = target }))
    end
  end
end

function M.resize_by_screen(pct_x, pct_y)
  local mon = active_monitor()
  if not mon then return nil end
  local w, h = size_of(mon)
  if not w then return nil end
  pct_x, pct_y = num(pct_x, 0), num(pct_y, 0)
  if pct_x == 0 and pct_y == 0 then return nil end
  local x = pct_x == 0 and w or w * pct_x / 100
  local y = pct_y == 0 and h or h * pct_y / 100
  return { x = math.floor(x + 0.5), y = math.floor(y + 0.5), relative = false }
end

function M.resize_active_window(pct_x, pct_y)
  return function()
    local win = hl.get_active_window()
    if not win then
      hl.dispatch(hl.dsp.no_op())
      return
    end
    local w, h = size_of(win)
    if not w then
      hl.dispatch(hl.dsp.no_op())
      return
    end
    hl.dispatch(hl.dsp.window.resize({
      x = math.floor(w * num(pct_x, 0) / 100 + 0.5),
      y = math.floor(h * num(pct_y, 0) / 100 + 0.5),
      relative = true,
    }))
  end
end

function M.move_actions(win)
  local mon = active_monitor()
  if not mon or not win then return nil end
  local mw, mh = size_of(mon)
  local ww, wh = size_of(win)
  if not (mw and mh and ww and wh) or ww <= 0 or wh <= 0 then return nil end
  local scale = num(mon.scale, 1)
  if scale <= 0 then scale = 1 end
  mw, mh = mw / scale, mh / scale

  local new_h = mh / 4
  local new_w = new_h * ww / wh
  new_w, new_h = math.max(new_w, 200), math.max(new_h, 150)
  new_w, new_h = math.floor(new_w + 0.5), math.floor(new_h + 0.5)

  local margin = 0.03 * math.min(mw, mh)
  local mx, my = num(mon.x, 0), num(mon.y, 0)
  local x = math.floor(mx + mw - new_w - margin + 0.5)
  local y = math.floor(my + mh - new_h - margin + 0.5)
  local ref = win_ref(win)

  return {
    hl.dsp.window.resize({ x = new_w, y = new_h, relative = false, window = ref }),
    hl.dsp.window.move({ x = x, y = y, relative = false, window = ref }),
  }
end

function M.resizer(win, pattern, pct_x, pct_y, actions, plain, field)
  local value = win[field or "title"]
  if type(value) ~= "string" or not value:find(pattern, 1, plain) then return end
  if actions ~= nil then
    -- a single dispatcher is a function/userdata or a table with no array part
    if type(actions) == "table" and #actions > 0 then
      for _, a in ipairs(actions) do hl.dispatch(a) end
    else
      hl.dispatch(actions)
    end
  end
  local ref = win_ref(win)
  local size = M.resize_by_screen(pct_x, pct_y)
  if size then
    size.window = ref
    hl.dispatch(hl.dsp.window.resize(size))
  end
  hl.dispatch(hl.dsp.window.set_prop({ prop = "keep_aspect_ratio", value = "true", window = ref }))
end

function M.toggle(name)
  return function()
    if name == "specialws" then
      local open = hl.get_active_special_workspace()
      if open and open.name and open.name:sub(1, 8) == "special:" then
        hl.dispatch(hl.dsp.workspace.toggle_special(open.name:sub(9)))
        return
      end
      hl.dispatch(hl.dsp.workspace.toggle_special("special"))
    else
      hl.dispatch(hl.dsp.workspace.toggle_special(name))
    end
  end
end

return M
