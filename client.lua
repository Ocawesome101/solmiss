-- SoLMISS client

local common = require("solmiss.common")

local api_port = common.port
local api_modem = common.getModem()

api_modem.open(api_port)

local TIMEOUT = 1

local function api_call(visible, ...)
  local id = math.random(111111, 999999)
  api_modem.transmit(api_port, api_port, {id, "solmiss_request", ...})
  local resp
  local tid = os.startTimer(TIMEOUT)
  if visible then
    common.at(2, 2, colors.white).clear()
    term.write("calling ")
    term.setTextColor(colors.yellow)
    term.write((...))
    term.setTextColor(colors.white)
    term.write("...")
  end
  local x, y = term.getCursorPos()
  repeat
    resp = table.pack(common.handledPullEvent())
    if resp[1] == "timer" and resp[2] == tid then
      error("timed out", 0)
    elseif resp[1] == "modem_message" and resp[3] == api_port and
          resp[5][1] == id and resp[5][2] == "solmiss_progress" then
      common.at(x, y).write(tostring(resp[5][3]).."  ")
      os.cancelTimer(tid)
      tid = os.startTimer(TIMEOUT)
    end
  until resp[1] == "modem_message" and resp[3] == api_port and
    resp[5][1] == id and resp[5][2] == "solmiss_reply"

  os.cancelTimer(tid)
  if visible then
    if resp[5][3] == "warn" then
      term.setTextColor(colors.orange)
      term.write(resp[5][4] or "WARN")
      os.sleep(1)
    else
      term.setTextColor(colors.green)
      term.write("OK")
      os.sleep(0.1)
    end
  end
  return table.unpack(resp[5], 3)
end

common.at(1,1).clear()
print("Waiting for a server to come online...")
repeat io.write(".") until pcall(api_call, false, "ping")

TIMEOUT = settings.get("solmiss.api_timeout") or 45

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
      local input = io.read()
      count = tonumber(input)
      if input == "*" then count = spec.count end
    until count and count <= spec.count
    api_call(true, "withdraw", io_chest, {name=spec.name,
      count=count, nbt=spec.nbt})
    return true
  end
end

local function deposit_action(spec)
  return function()
    api_call(true, "deposit", io_chest, table.unpack(spec.slots))
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
      local server = false
      repeat
        common.at(2, 2, colors.white).clear()
        term.write("Update server also? [y/N]: ")
        local input = io.read()
        server = input:lower() == "y"
      until input:lower() == "y" or input:lower() == "n" or input == ""
      if server then api_call(true, "update") end
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
