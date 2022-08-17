-- SoLMISS client

local common = require("solmiss.common")

local api_port = common.port
local api_modem = common.getModem()

api_modem.open(api_port)

local function api_call(visible, ...)
  local id = math.random(111111, 999999)
  api_modem.transmit(api_port, api_port, {id, "solmiss_request", ...})
  local resp
  local tid = os.startTimer(15)
  if visible then
    common.at(2, 2, colors.white).clear()
    term.write("calling ")
    term.setTextColor(colors.yellow)
    term.write((...))
    term.setTextColor(colors.white)
    term.write("...")
  end
  repeat
    resp = table.pack(common.handledPullEvent())
    if resp[1] == "timer" and resp[2] == tid then
      error("timed out", 0)
    end
  until resp[1] == "modem_message" and resp[3] == api_port and
    resp[5][1] == id

  os.cancelTimer(tid)
  if visible then
    term.setTextColor(colors.green)
    term.write("OK")
    os.sleep(1)
  end
  return table.unpack(resp[5], 3)
end

print("Waiting for a server to come online...")
repeat until api_call(false, "ping")

local io_chest
local function select_input()
  local chests = textutils.unserialize(api_call(false, "input_options"))
  settings.set("solmiss.io_chest", common.selectOne("Select Input Chest",
    chests, io_chest))
end

io_chest = common.getIOChest(select_input)

local function withdraw_action(spec)
  return function()
    local count
    repeat
      term.clear()
      common.at(2, 2, colors.yellow).write("Retrieving " .. spec.displayName)
      common.at(2, 3, colors.white).write("Quantity? [0-"..spec.count.."]: ")
      count = tonumber(io.read())
    until count and count <= spec.count
    api_call(true, "withdraw", io_chest, {name=spec.name,
      count=count, nbt=spec.nbt})
    return true
  end
end

local function deposit_action(spec)
  return function()
    api_call(true, "deposit", io_chest, spec.slots)--textutils.serialize(spec.slots))
    return true
  end
end

local menu

local function update_status()
  local total, max = api_call(false, "stored_percent")
  menu.state = string.format("%d / %d items (%.2f%%)", total, max,
    (total/max)*100)
end

menu = {
  title = "SoLMISS Client",
  {
    text = "Retrieve",
    action = function()
      update_status()
      local items = textutils.unserialize(api_call(false, "stored_items"))

      local prompt = {
        title = "Select items",
      }

      for _, spec in pairs(items) do
        prompt[#prompt+1] = {
          spec = spec,
          text = common.formatItemName(spec),
          action = withdraw_action(spec),
        }
      end

      if #prompt == 0 then return end

      table.sort(prompt, function(a, b)
        if a.spec.count == b.spec.count then
          return a.spec.displayName > b.spec.displayName
        end
        return a.spec.count > b.spec.count
      end)

      common.menu(prompt)
    end
  },
  {
    text = "Deposit",
    action = function()
      local items = textutils.unserialize(api_call(false, "in_input_chest",
        io_chest))

      local all = {}

      local prompt = {
        title = "Select items",
      }

      for _, spec in pairs(items) do
        prompt[#prompt+1] = {
          text = common.formatItemName(spec),
          action = deposit_action(spec),
        }
        for _, slot in pairs(spec.slots) do
          all[#all+1] = slot
        end
      end

      if #prompt == 0 then return end

      table.sort(prompt, function(a,b) return a.text > b.text end)

      table.insert(prompt, 1, {
        text = "------  (Everything)",
        action = deposit_action({slots = all})
      })
      common.menu(prompt)
      update_status()
    end
  },
  {
    text = "Recall All Items",
    action = function()
      api_call(true, "deposit_all")
      update_status()
    end
  },
  {
    text = "Select Input Chest",
    action = select_input,
  },
  {
    text = "Rebuild Item Index",
    action = function() api_call(true, "rebuild_index"); update_status(); end
  },
  {
    text = "Update",
    action = function()
      common.update()
      os.reboot()
    end
  },
  {
    text = "Exit",
    action = function() return true end
  }
}

update_status()
common.menu(menu)
common.at(1,1).clear()
settings.save()
