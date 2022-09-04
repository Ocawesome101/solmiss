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

local inputs = settings.get("solmiss.input_chests") or {}
local api_port = settings.get("solmiss.comm_port") or 3155
local api_modem = common.getModem()

local maxItems = 0
local totalItems = 0

local function build_index()
  io.write("Probing for chests... ")
  local x, y = term.getCursorPos()

  maxItems, totalItems = 0, 0

  local chests = peripheral.getNames()
  for i=#chests, 1, -1 do
    if not common.inventoryFilter(chests[i]) then
      table.remove(chests, i)
    else
      wrappers[chests[i]] = peripheral.wrap(chests[i])
    end
    common.progress(y+1, #chests - i, #chests)
  end

--[[  for k, v in pairs(index) do
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
  end]]

  common.at(x, y).write("done")
  print'\n'

  io.write("Reading chest sizes... ")
  x, y = term.getCursorPos()

  local scanners = {}
  local searchers = {}
  local stage = 0
  local total = 0

  for name, chest in pairs(wrappers) do
    if not common.itemIn(inputs, name) then
      total = total + 1
      scanners[#scanners+1] = function()
        for i=1, chest.size() do
          maxItems = chest.getItemLimit(i) + maxItems
        end
        stage = stage + 1

        common.progress(y+1, stage, total)
      end

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
        common.progress(y+1, stage, total)
      end
    end
  end

  parallel.waitForAll(table.unpack(scanners))

  common.at(x, y).write("done")
  print'\n'

  stage = 0
  io.write("Reading items... ")
  x, y = term.getCursorPos()

  parallel.waitForAll(table.unpack(searchers))

  common.at(x, y).write("done")
  print'\n'
end

build_index(true)

local function _find_location(item, nbt)
  nbt = nbt or ""
  for chest, slots in pairs(index) do
    for slot, detail in pairs(slots) do
      if slot ~= "size" then
        if ((detail.name == item) or detail.tags[item]) and
            (detail.nbt or "") == nbt then
          return chest, slot, detail.maxCount - detail.count, detail.count
        end
      end
    end
  end
end

local function withdraw(io, item, count, nbt)
  while count > 0 do
    local chest, slot, _, has = _find_location(item, nbt)
    if not chest then return end
    has = math.min(count, has)

    index[chest][slot].count = index[chest][slot].count - has
    if index[chest][slot].count <= 0 then
      index[chest][slot] = nil
    end

    count = count - has
    totalItems = totalItems - has
    wrappers[chest].pushItems(io, slot, has)
  end

  return true
end

-- api exposed to clients
local api = {}
api.rebuild_index = build_index

function api.deposit(io, ...)
  io = wrappers[io]
  local movers = {}
  local slots = table.pack(...)
  if type(slots[1]) == "string" then
    slots = textutils.unserialize(slots[1])
  elseif type(slots[1]) == "table" then
    slots = slots[1]
  end
  slots.n = nil

  local warn
  local reason

  for _, slot in pairs(slots) do
    movers[#movers+1] = function()
      local item = io.getItemDetail(slot)
      if item then
        while item.count > 0 do
          local should_break = true

          for chest, slots in pairs(index) do
            local did_deposit = false

            if item.count == 0 then break end

            for dslot, detail in pairs(slots) do
              if dslot ~= "size" then
                if detail.name == item.name and detail.count < detail.maxCount
                    and (detail.nbt or "") == (item.nbt or "") then

                  local depositing = math.min(item.count,
                    detail.maxCount - detail.count)

                  reason = "DEPOSITED " .. depositing

                  item.count = item.count - depositing
                  detail.count = detail.count + depositing

                  did_deposit = true
                  should_break = false

                  totalItems = totalItems + depositing
                  io.pushItems(chest, slot, depositing, dslot)
                end

                if item.count == 0 then break end
              end
            end

            if item.count == 0 then break end

            if item.count > 0 and not did_deposit then
              reason = "NO SLOT FOUND"
              for i=1, slots.size, 1 do
                if slots[i] == nil then
                  should_break = false

                  slots[i] = {
                    count = 0, name = item.name,
                    displayName = item.displayName,
                    maxCount = item.maxCount,
                    nbt = item.nbt, tags = item.tags
                  }
                  reason = "WTF"
                  break
                end
              end
            end
          end

          if should_break then warn = true break end
        end
      end
    end
  end

  parallel.waitForAll(table.unpack(movers))

  if warn then return "warn", reason end
end

function api.stored_items()
  local items = {}

  for _, chest in pairs(index) do
    for dslot, detail in pairs(chest) do
      if dslot ~= "size" then
        local name = detail.name .. (detail.nbt or "")

        if items[name] then
          items[name].count = items[name].count + detail.count

        else
          items[name] = {
            count = detail.count,
            displayName = detail.displayName,
            name = detail.name,
            nbt = detail.nbt
          }
        end
      end
    end
  end

  return textutils.serialize(items)
end

function api.in_input_chest(io)
  local items = {}

  local funcs = {}
  for dslot in pairs(wrappers[io].list()) do
    if dslot ~= "size" then
      funcs[#funcs+1] = function()
        local detail = wrappers[io].getItemDetail(dslot)
        local name = detail.name .. (detail.nbt or "")

        if items[name] then
          items[name].count = items[name].count + detail.count
          items[name].slots[#items[name].slots+1] = dslot

        else
          items[name] = {
            count = detail.count,
            displayName = detail.displayName,
            name = detail.name,
            nbt = detail.nbt,
            slots = { dslot }
          }
        end
      end
    end
  end

  parallel.waitForAll(table.unpack(funcs))

  return textutils.serialize(items)
end

function api.withdraw(io, is)
  withdraw(io, is.name, is.count, is.nbt)
end

function api.deposit_all()
  local retrievers = {}
  for i=1, #inputs, 1 do
    retrievers[#retrievers+1] = function()
      local slots = {}
      for slot in pairs(wrappers[inputs[i]].list()) do
        slots[#slots+1] = slot
      end
      api.deposit(inputs[i], table.unpack(slots))
    end
  end
  parallel.waitForAll(table.unpack(retrievers))
end

function api.stored_percent()
  return totalItems, maxItems
end

function api.input_options()
  return textutils.serialize(inputs)
end

function api.ping()
  return "pong"
end

api_modem.open(api_port)

common.handleEvent("modem_message", function(event)
  if event[3] == api_port then
    local message = event[5]
    local message_id = table.remove(message, 1)
    local message_type = table.remove(message, 1)

    if api[message[1]] and message_type == "solmiss_request" then
      api_modem.transmit(api_port, api_port,
        { message_id, "solmiss_reply",
          api[message[1]](table.unpack(message, 2)) })
    end
  end
end)

common.menu {
  title = "SoLMISS Server Software",
  {
    text = "Configure IO chests",
    action = function()
      local names = {
        title = "Select chests",
      }

      for key in pairs(wrappers) do
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
      settings.save()
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
    text = "Update",
    action = function()
      common.update(true)
      os.reboot()
    end
  },
  {
    text = "Exit",
    action = function() return true end
  }
}

settings.set("solmiss.input_chests", inputs)
common.at(1,1).clear()
settings.save()
