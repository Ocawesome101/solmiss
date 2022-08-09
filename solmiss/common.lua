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
    for _, reg in pairs(handlers) do
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
  local nbt = itemspec.nbt and #itemspec.nbt > 0 and
    " (+"..itemspec.nbt:sub(1,6)..")" or ""
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
    if (i - m.scroll + 3) > (h - 2) then break end
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

settings.define("solmiss.comm_modem", {
  description = "The modem SoLMISS should use to communicate.",
  type = "string",
})

settings.define("solmiss.comm_port", {
  description = "The network port SoLMISS should communicate on.",
  default = 3155,
  type = "number",
})

settings.define("solmiss.io_chest", {
  description = "The input chest that this SoLMISS client should use.",
  type = "string"
})

common.port = settings.get("solmiss.comm_port")

function common.getModem()
  local options = {}

  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "modem") and not
          peripheral.call(name, "isWireless") then
      options[#options+1] = name
    end
  end

  if #options == 0 then
    error("no modem is present", 0)
  end

  local api_modem = settings.get("solmiss.comm_modem")
  while not (api_modem and peripheral.isPresent(api_modem)) do
    api_modem = common.selectOne("Select a modem", options)
  end

  settings.set("solmiss.comm_modem", api_modem)
  api_modem = peripheral.wrap(api_modem)
  if api_modem.isWireless() then
    error("cannot use a wireless modem for the SoLMISS API", 0)
  end

  return api_modem
end

function common.getIOChest(func)
  local io_chest = settings.get("solmiss.io_chest")
  while not (io_chest and peripheral.isPresent(io_chest)) do
    if func then func() else
    error("you must set solmiss.io_chest to a valid peripheral", 0) end
    io_chest = settings.get("solmiss.io_chest")
  end

  return io_chest
end

function common.selectOne(title, list, default)
  expect(1, title, "string")
  expect(2, list, "table")

  local names = {
    title = title
  }

  for i=1, #list, 1 do
    names[#names+1] = {
      text = list[i],
      toggle = true,
      on = list[i] == default,
      action = function(self)
        if self.on then
          for i=1, #names, 1 do
            if names[i] ~= self and names[i].on then
              names[i].on = false
            end
          end
        else
          local other_is_on = false
          for i=1, #names, 1 do
            if names[i].on then
              other_is_on = true
            end
          end
          if not other_is_on then self.on = true end
        end
      end
    }
  end

  names[#names+1] = {
    text = "Done",
    action = function()
      return true
    end
  }

  common.menu(names)

  for i=1, #names, 1 do
    if names[i].on then
      return names[i].text
    end
  end
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

-- updating
local url = "https://raw.githubusercontent.com/ocawesome101/solmiss/primary/"

local function dl(f)
  local hand, err = http.get(url..f, nil, true)
  if not hand then
    error(err, 0)
  end

  local data = hand.readAll()
  hand.close()

  return data
end

-- TODO: improve somehow?
function common.update(isServer)
  local files = isServer and files_server or files_client

  local common = dl("solmiss/common.lua")
  local special = dl(isServer and "server.lua" or "client.lua")

  io.open("/solmiss/common.lua", "w"):write(common):close()
  io.open("/startup.lua", "w"):write(special):close()
end

return common
