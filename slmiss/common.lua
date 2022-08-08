-- Common things, e.g. menus, searching, filtering, event handling

local expectlib = require("cc.expect")
local expect = expectlib.expect
local field = expectlib.field
local range = expectlib.range

local common = {}
local handlers = {}

---- Event Handling ----

function common.handleEvent(name, handler)
  expect(1, name, "string")
  expect(2, handler, "function")

  local id = math.random(111111, 999999)
  handlers[id] = { event = name, handler = handler }
  return id
end

function common.ignoreHandler(id)
  expect(1, id, "number")
  handlers[id] = nil
end

function common.handledPullEvent(filter)
  expect(1, filter, "string", "nil")

  local event
  repeat
    event = table.pack(os.pullEventRaw())
    for _, reg in ipairs(handlers) do
      if event[1] == reg.event then
        reg.handler(event)
      end
    end
  until event[1] == filter or not filter

  return table.unpack(event)
end

---- Menus ----

function common.checkItemspec(itemspec)
  expect(1, itemspec, "table")
  field(itemspec, "count", "number")
  field(itemspec, "displayName", "string")
  field(itemspec, "name", "string")
  field(itemspec, "maxCount", "number", "nil")
  field(itemspec, "tags", "table", "nil")
  field(itemspec, "nbt", "string", "nil")
end

function common.formatItemName(itemspec)
  common.checkItemspec(itemspec)
  local nbt = itemspec.nbt and " (+"..itemspec.nbt:sub(1,6)..")" or ""
  return string.format("%6dx %s%s", itemspec.count,
    itemspec.displayName, nbt)
end

function common.filter(options, search_term)
  local ret = {}

  for i=1, #options, 1 do
    if options[i].text:lower():match(search_term:lower()) then
      ret[#ret+1] = options[i]
      ret[#ret].realIndex = i
    end
  end

  return ret
end

local function at(x, y, c)
  term.setCursorPos(x, y)
  if c then term.setTextColor(c) end
  return term
end

common.at = at

local function draw_menu(m)
  if term.setVisible then term.setVisible(false) end
  term.clear()
  local w, h = term.getSize()
  if m.title then at(2, 2, colors.yellow).write(m.title) end
  at(2, h - 1).write("\x18\x19 - navigate   \x1b - back   \x14\x1a - select")
  if m.state then at(1, h, colors.white).write(m.state) end

  local opts = m
  if m.search and #m.search > 0 then
    opts = common.filter(m, m.search)
  end

  if (not m.search) or #m.search == 0 then
    at(2, 3, colors.white).write("> (type to search)")
  else
    at(2, 3, colors.white).write("> " .. m.search:sub(-(w - 4)) .. "_ ")
  end

  if m.selected - m.scroll < 2 then
    m.scroll = math.max(0, m.selected - 2)
  elseif m.selected - m.scroll > h - 5 then
    m.scroll = m.selected - (h - 5)
  end

  for i=m.scroll+1, #opts, 1 do
    local prefix =
      i == m.selected and (
      ( opts[i].toggle and (opts[i].on and "+> " or "-> ")) or
      ( type(opts[i].action) == "function" and "*> " ) or
      ( type(opts[i].action) == "table" and "-> " )
      ) or " . "
    local color =
      i == m.selected and (
      ( type(opts[i].action) == "function" and colors.lightBlue ) or
      ( type(opts[i].action) == "table" and colors.yellow )
      ) or colors.white
    if opts[i].toggle then
      color = i == m.selected
          and (opts[i].on and colors.yellow or colors.lightGray)
          or  (opts[i].on and colors.orange or colors.gray)
    end
    at(2, i - m.scroll + 3, color).write(prefix .. (opts[i].text or ""))
  end

  if term.setVisible then term.setVisible(true) end

  return opts
end

function common.menu(menu)
  expect(1, menu, "table")
  menu.scroll = menu.scroll or 0
  menu.selected = 1
  menu.search = ""

  while true do
    local filtered = draw_menu(menu)
    local _, h = term.getSize()

    local sig, cc = common.handledPullEvent()

    if sig == "char" then
      menu.search = menu.search .. cc
      menu.selected = 1
      menu.scroll = 0

    elseif sig == "key" then
      if cc == keys.enter or cc == keys.right then
        local selected = filtered[menu.selected]

        if type(selected.action) == "table" then
          common.menu(selected.action)
        elseif selected.toggle then
          selected.on = not selected.on
          if selected.action then selected.action(selected) end
        elseif selected.action(selected) then
          return
        end

      elseif cc == keys.backspace then
        if #menu.search > 0 then menu.search = menu.search:sub(1, -2) end

      elseif cc == keys.up then
        menu.selected = math.max(1, menu.selected - 1)

      elseif cc == keys.down then
        menu.selected = math.min(#filtered, menu.selected + 1)

      elseif cc == keys.left then
        term.clear()
        return

      elseif cc == keys.pageUp then
        menu.selected = math.max(1, menu.selected - (h - 8))

      elseif cc == keys.pageDown then
        menu.selected = math.min(#filtered, menu.selected + (h + 8))
      end
    end
  end
end

-- networking

settings.define("slmiss.comm_modem", {
  description = "The modem MISS should use to communicate.  Only required if more than one is present.",
  type = "string",
})

settings.define("slmiss.comm_port", {
  description = "The network port MISS should communicate on.",
  default = 3155,
  type = "number",
})

common.port = settings.get("slmiss.comm_port")

function common.findWiredModems()
  return table.pack(peripheral.find("modem", function(_, m)
    return not m.isWireless()
  end))
end

---- Misc ----

function common.itemIn(tab, item)
  for i=1, #tab, 1 do
    if tab[i] == item then return true end
  end
end

function common.removeFrom(tab, item)
  for i=#tab, 1, -1 do
    if tab[i] == item then table.remove(tab, i) end
  end
end

-- y is the y level at which to draw the bar
-- a is either a percentage, or...
-- ...if b is present, a/b*100 is the percentage.
function common.progress(y, a, b)
  expect(1, y, "number")
  expect(2, a, "number")
  expect(3, b, "number", "nil")

  local progress = a/100
  if b then progress = a/b end

  local w = term.getSize()
  at(1, y, colors.yellow).write("[")
  at(2, y, colors.white).write(("#"):rep(math.ceil(progress * (w - 2))))
  at(w, y, colors.yellow).write("]")
  term.setTextColor(colors.white)
end

return common
