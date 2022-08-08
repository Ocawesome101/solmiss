-- SoLMISS client

local common = require("solmiss.common")

local api_port = common.port
local api_modem = common.getModem()
local io_chest = common.getIOChest()

api_modem.open(api_port)

local function api_call(...)
  local id = math.random(111111, 999999)
  api_modem.transmit(api_port, api_port, {id, "solmiss_request", ...})
  local resp
  local tid = os.startTimer(5)
  repeat
    resp = table.pack(common.handledPullEvent())
    if resp[1] == "timer" and resp[2] == "tid" then
      return
    end
  until resp[1] == "modem_message" and resp[3] == api_port and
    resp[5][1] == id

  os.cancelTimer(tid)
  return table.unpack(resp[5], 3)
end

print("Waiting for a server to come online...")
repeat until api_call("ping")

local function withdraw_action(spec)
  return function()
    local count
    repeat
      term.clear()
      common.at(2, 2, colors.yellow).write("Retrieving " .. spec.displayName)
      common.at(2, 3, colors.white).write("Quantity? [0-"..spec.count.."]: ")
      count = tonumber(io.read())
    until count and count <= spec.count
    api_call("withdraw", io_chest, {name=spec.name,
      count=count, nbt=spec.nbt})
    return true
  end
end

local function deposit_action(spec)
  return function()
    api_call("deposit", io_chest, table.unpack(spec.slots))
    return true
  end
end

local menu
menu = {
  title = "SoLMISS Client",
  {
    text = "Retrieve",
    action = function()
      local items = textutils.unserialize(api_call("stored_items"))

      local prompt = {
        title = "Select items",
      }

      for _, spec in pairs(items) do
        prompt[#prompt+1] = {
          text = common.formatItemName(spec),
          action = withdraw_action(spec),
        }
      end

      if #prompt == 0 then return end
      common.menu(prompt)
    end
  },
  {
    text = "Deposit",
    action = function()
      local items = textutils.unserialize(api_call("in_input_chest", io_chest))

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
    end
  },
  {
    text = "Rebuild item index",
    action = function() api_call("rebuild_index") end
  }
}

common.menu(menu)
