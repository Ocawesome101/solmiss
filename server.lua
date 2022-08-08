-- SoLMISS server

local common = require("solmiss.common")

--common.handleEvent("modem_message")

-- chest index
-- e.g. {
--   ["minecraft:chest_3"] = {
--     [16] = <itemDetail>
--   }
-- }
local index = {}

-- chest peripheral wrapper cache
local wrappers = {}
local chest_names = {}

local inputs = settings.get("solmiss.input_chests") or {}

local maxItems = 0
local totalItems = 0

local function build_index(show)
  if show then io.write("Probing for chests... ") end
  local x, y = term.getCursorPos()

  local chests = peripheral.getNames()
  for i=#chests, 1, -1 do
    if common.itemIn(inputs, chests[i]) or not chests[i]:match("chest") then
      if common.itemIn(inputs, chests[i]) then
        chest_names[chests[i]] = true
      end
      table.remove(chests, i)
    else
      chest_names[chests[i]] = true
      wrappers[chests[i]] = peripheral.wrap(chests[i])
    end
    if show then common.progress(y+1, #chests - i, #chests) end
  end

  for k, v in pairs(index) do
    local existant = false
    for i=1, #chests, 1 do
      if chests[i] == k then
        existant = true
        break
      end
    end

    if type(v) == "number" and not existant then
      index[k] = nil
      for _k, detail in pairs(v) do
        if _k ~= "size" then
          totalItems = totalItems - detail.count
        end
      end
    end
  end

  if show then common.at(x, y).write("done")
  print'\n'

  io.write("Reading chest sizes... ")
  x, y = term.getCursorPos() end

  local scanners = {}
  local searchers = {}
  local stage = 0
  local total = 0

  for name, chest in pairs(wrappers) do
    scanners[#scanners+1] = function()
      maxItems = (chest.size() * chest.getItemLimit(1)) + maxItems
      stage = stage + 1

      if show then common.progress(y+1, stage, total) end
    end

    if not index[name] then
      searchers[#searchers+1] = function()
        local items = chest.list()

        index[name] = { size = chest.size() }

        for slot in pairs(items) do
          local detail = chest.getItemDetail(slot)
          detail.tags = detail.tags or {}
          detail.nbt = detail.nbt or ""

          totalItems = totalItems + detail.count
          index[name][slot] = detail
        end

        stage = stage + 1
        if show then common.progress(y+1, stage, total) end
      end
    end
  end

  parallel.waitForAll(table.unpack(scanners))

  if show then
  common.at(x, y).write("done")
  print'\n'

  stage = 0
  io.write("Reading items... ")
  x, y = term.getCursorPos() end

  parallel.waitForAll(table.unpack(searchers))

  if show then common.at(x, y).write("done")
  print'\n' end
end

build_index(true)

-- api exposed to clients
local api = {}
api.rebuild_index = build_index

local function _find_location(item, nbt)
  nbt = nbt or ""
  for chest, slots in pairs(index) do
    for slot, detail in pairs(slots) do
      if slot ~= "size" then
        if (detail.name == item or detail.tags[item]) and detail.nbt == nbt then
          return chest, slot, detail.maxCount - detail.count, detail.count
        end
      end
    end
  end
end

function api.withdraw()
end

function api.deposit()
end

common.menu {
  title = "SoLMISS Server Software",
  {
    text = "Configure IO chests",
    action = function()
      local names = {
        title = "Select chests",
      }

      for key in pairs(chest_names) do
        names[#names+1] = {
          text = key,
          toggle = true,
          on = common.itemIn(inputs, key),
          action = function(self)
            if self.on then
              inputs[#inputs+1] = key
            else
              common.removeFrom(inputs, key)
            end
            return true
          end,
        }
      end

      table.sort(names, function(a,b) return a.text < b.text end)

      common.menu(names)

      common.at(1,1).clear()
      build_index(true)
    end,
  },
  {
    text = "Rebuild index",
    action = function()
      common.at(1,1).clear()
      build_index(true)
    end,
  },
  {
    text = "Exit",
    action = function() return true end
  }
}

settings.set("solmiss.input_chests", inputs)
common.at(1,1).clear()
