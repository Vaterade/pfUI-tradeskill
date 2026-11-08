-- Offline test with stubs of the 1.12 and ClassicAPI calls. Run from the addon folder:
--   luajit tools/test.lua
-- LuaJIT because ui.lua's module runs under pfUI's setfenv, and that's Lua 5.1.

table.getn = table.getn or function(t) return #t end

-- [ A frame that accepts anything ]

local handlers = {}
local function NewFrame(kind, name)
  local frame = { scripts = {}, shown = true, kind = kind, children = {} }
  setmetatable(frame, { __index = function(_, key)
    return handlers[key] or function() end
  end })
  if name then _G[name] = frame end
  return frame
end

function handlers.SetScript(self, script, func) self.scripts[script] = func end
function handlers.HookScript(self, script, func) self.scripts[script] = func end
function handlers.Show(self) self.shown = true end
function handlers.Hide(self) self.shown = false end
function handlers.IsShown(self) return self.shown end
function handlers.IsVisible(self) return self.shown end
function handlers.GetRight() return 700 end
function handlers.GetFrameLevel(self) return rawget(self, "level") or 1 end
function handlers.SetFrameLevel(self, level) self.level = level end
function handlers.EnableMouse(self, on) self.mouse = on end
function handlers.SetPoint(self, point, relative) self.point = { point, relative } end
function handlers.GetChildren(self) return unpack(self.children) end
function handlers.CreateFontString()
  local text = NewFrame("FontString")
  text.SetText = function(self, value) self.text = value end
  return text
end
function handlers.CreateTexture() return NewFrame("Texture") end
function handlers.SetText(self, value) self.label = value end
function handlers.GetNumber() return 3 end
function handlers.Enable(self) self.enabled = true end
function handlers.Disable(self) self.enabled = false end

function CreateFrame(kind, name, parent)
  local frame = NewFrame(kind, name)
  frame.parent = parent
  if parent then
    frame.level = parent:GetFrameLevel() + 1
    table.insert(parent.children, frame)
  end
  return frame
end

function handlers.GetParent(self) return self.parent end
function handlers.SetParent(self, parent) self.parent = parent end

-- [ World ]

local carried, banked = {}, {}
C_Item = {
  GetItemCount = function(id, bank)
    return (carried[id] or 0) + (bank and banked[id] or 0)
  end,
  GetItemNameByID = function(id) return "Fetched " .. id end,
  GetItemIconByID = function() return "fetched icon" end,
}

local now, casts, stopped = 100, {}, 0
function GetTime() return now end
function UnitName() return "Main" end
function UnitFactionGroup() return "Horde" end
function GetRealmName() return "Realm" end
function SpellStopCasting() stopped = stopped + 1 end
function IsShiftKeyDown() return false end
local said
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) said = text end }

local BAR, ORE, COAL, BLADE = 2840, 2770, 3857, 7000

-- Row order as the player sees it. Hidden rows only come back with the filters cleared.
local fullList = {
  { "Mining", "header" },
  { "Smelt Copper", "easy", reagents = { { ORE, "Copper Ore", 2 } }, item = BAR, made = 1 },
  { "Copper Blade", "easy", reagents = { { BAR, "Copper Bar", 4 }, { COAL, "Coal", 1 } }, item = BLADE, made = 1 },
}
local list = fullList
local selected = 2
local cleared = 0

local function Link(id) return id and ("|cffffffff|Hitem:" .. id .. ":0:0:0|h[x]|h|r") end

function GetTradeSkillLine() return "Blacksmithing" end
function IsTradeSkillLinked() return false end
function GetNumTradeSkills() return table.getn(list) end
function GetTradeSkillSelectionIndex() return selected end
function GetTradeSkillInfo(i) local r = list[i]; if r then return r[1], r[2], 0, true end end
function GetTradeSkillIcon() return "icon" end
function GetTradeSkillItemID(i) return list[i].item end
function GetTradeSkillRecipeLink(i) return "|cffffd000|Henchant:" .. (1000 + i) .. "|h[x]|h|r" end
function GetTradeSkillNumMade(i) return list[i].made, list[i].made end
function GetTradeSkillNumReagents(i) return table.getn(list[i].reagents) end
function GetTradeSkillReagentInfo(i, r) local x = list[i].reagents[r]; return x[2], "ricon", x[3] end
function GetTradeSkillReagentItemID(i, r) return list[i].reagents[r][1] end
function DoTradeSkill(i, n) table.insert(casts, { list[i][1], n, table.getn(list) }) end
function GetTradeSkillSubClasses() return "A", "B" end
function GetTradeSkillInvSlots() return "A" end
local subFilter = 0
function GetTradeSkillSubClassFilter(i) return i == subFilter end
function GetTradeSkillInvSlotFilter(i) return i == 0 end
function SetTradeSkillSubClassFilter(i)
  subFilter = i
  list = i == 0 and fullList or { fullList[1], fullList[2] }
  cleared = cleared + 1
end
function SetTradeSkillInvSlotFilter() end
function ExpandTradeSkillSubClass() end
function CollapseTradeSkillSubClass() end
function SelectTradeSkill() end
function TradeSkillFrame_SetSelection(i) selected = i end
function TradeSkillFrame_Update() end
function GetCraftDisplaySkillLine() return nil end -- Beast Training

-- [ Load ]

local module
pfUI = {
  bootup = nil,
  font_default = "font",
  RegisterModule = function(_, _, func) module = func end,
  UpdateConfig = function(_, group, _, key, value)
    pfUI_config[group] = pfUI_config[group] or {}
    if pfUI_config[group][key] == nil then pfUI_config[group][key] = value end
  end,
}
pfUI_config = {}

GetLocale = GetLocale or function() return "enUS" end
dofile("core.lua")
dofile("recipes.lua")
dofile("recipes-locale.lua")
dofile("ui.lua")

local M = pfUITrades
local failures, passed = 0, 0
local function Eq(got, want, what)
  if got == want then
    passed = passed + 1
  else
    failures = failures + 1
    print("FAIL " .. what .. ": got " .. tostring(got) .. ", want " .. tostring(want))
  end
end

local function Fire(name, a1, a4, a3)
  event, arg1, arg3, arg4 = name, a1, a3, a4
  M.driver.scripts.OnEvent()
end

local function Reset()
  pfUITrades_DB, pfUITrades_Tasks = nil, nil
  casts, stopped = {}, 0
  carried, banked = {}, {}
  M.running, M.confirm = nil, nil
  M.pendingBuys = {}
  said = nil
  list, subFilter, selected = fullList, 0, 2
  Altoholic = nil
  -- queueing what a recipe needs has its own tests; the others add recipes one at a time
  pfUI_config.trades = { intermediates = "0" }
end

local function Row(plan, id)
  for _, row in ipairs(plan.materials) do
    if row.id == id then return row end
  end
end

-- [ Tasks ]

Reset()
M.AddSelected("TradeSkill", 3)
M.AddSelected("TradeSkill", 2)
local tasks = M.Tasks("Blacksmithing")
Eq(table.getn(tasks), 1, "adding a recipe twice merges it")
Eq(tasks[1].count, 5, "merged count")
Eq(tasks[1].reagents[1].id, ORE, "reagent id comes from its link")

selected = 1
M.AddSelected("TradeSkill", 1)
Eq(table.getn(tasks), 1, "a header can't be added")

selected = 3
M.AddSelected("TradeSkill", 1)
M.Move("Blacksmithing", tasks[2], -1)
Eq(tasks[1].name, "Copper Blade", "moving up")
M.Move("Blacksmithing", tasks[1], -1)
Eq(tasks[1].name, "Copper Blade", "moving past the top does nothing")
M.Adjust("Blacksmithing", tasks[1], -1)
Eq(table.getn(tasks), 1, "counting down to zero removes the task")

Eq(tasks[1].spell, 1002, "spell ID comes from the recipe link")

Reset()
local realInfo = GetTradeSkillReagentInfo
function GetTradeSkillReagentInfo(i, r) return nil, nil, list[i].reagents[r][3] end
selected = 2
M.AddSelected("TradeSkill", 1)
Eq(M.Tasks("Blacksmithing")[1].reagents[1].name, "Fetched " .. ORE, "uncached reagent still adds")
GetTradeSkillReagentInfo = realInfo

-- Queued from Altoholic for another character, then filled in when they open the window
Reset()
M.QueueFor("Alt", "Blacksmithing", { name = "Copper Blade", item = BLADE, made = 1,
  reagents = { { id = BAR, name = "Copper Bar", count = 4 } } }, 2)
M.QueueFor("Alt", "Blacksmithing", { name = "Copper Blade", item = BLADE, reagents = {} }, 1)
local altTasks = pfUITrades_Tasks.Realm.Alt.Blacksmithing
Eq(table.getn(altTasks), 1, "queueing for an alt twice merges")
Eq(altTasks[1].count, 3, "queued count")
Eq(M.QueuedFor("Alt", "Blacksmithing", "Copper Blade"), 3, "QueuedFor reads it back")
Eq(M.Tasks("Blacksmithing")[1], nil, "the logged-in character's list is untouched")

-- the same, for the logged-in character, then the window opens
M.QueueFor("Main", "Blacksmithing", { name = "Copper Blade", item = BLADE, made = 1,
  reagents = { { id = BAR, name = "Copper Bar", count = 4 } } }, 1)
local queued = M.Tasks("Blacksmithing")[1]
Eq(queued.stale, true, "a queued task waits to be filled in")
Eq(queued.spell, nil, "Altoholic has no spell ID")
M.RefreshTasks("TradeSkill")
Eq(queued.spell, 1003, "the spell ID comes from the open window")
Eq(table.getn(queued.reagents), 2, "and the full reagent list")
Eq(queued.stale, nil, "it is no longer stale")
Eq(queued.count, 1, "the count stays")

-- A cast counts against the task with its spell ID, whatever else shares the name
Reset()
pfUITrades_Tasks = { ["Realm|Horde"] = { Main = {
  Tailoring = { { name = "Same Name", spell = 1, count = 3, reagents = {} } },
  Leatherworking = { { name = "Same Name", spell = 2, count = 3, reagents = {} } },
} } }
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Same Name", 2)
Eq(M.Tasks("Tailoring")[1].count, 3, "the other recipe's task is untouched")
Eq(M.Tasks("Leatherworking")[1].count, 2, "the recipe cast counts down")
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Same Name", 99)
local byName = M.Tasks("Tailoring")[1].count + M.Tasks("Leatherworking")[1].count
Eq(byName, 4, "an unknown spell ID falls back to the name")

-- [ Plan ]

Reset()
selected = 2
M.AddSelected("TradeSkill", 4)   -- Smelt Copper x4: 8 ore, makes 4 bars
selected = 3
M.AddSelected("TradeSkill", 2)   -- Copper Blade x2: 8 bars, 2 coal
tasks = M.Tasks("Blacksmithing")

carried = { [ORE] = 6, [COAL] = 1 }
banked = { [ORE] = 1, [COAL] = 5 }
local plan = M.Plan("Blacksmithing")
Eq(plan.ready[tasks[1]], 3, "ready limited by carried ore, not banked")
Eq(plan.ready[tasks[2]], 0, "3 smelted bars don't make a blade")
Eq(Row(plan, BAR).need, 4, "planned bars come off what's needed")
Eq(Row(plan, ORE).bags, 6, "bags")
Eq(Row(plan, ORE).bank, 1, "bank is apart from bags")
Eq(Row(plan, ORE).status, "short", "not enough anywhere")
Eq(Row(plan, COAL).status, "bank", "1 coal in bags, 5 in bank, 2 needed")
Eq(plan.alts, "missing", "no Altoholic")
Eq(M.MyTasks().Blacksmithing[1].ready, nil, "plan results aren't saved on the task")

carried = { [ORE] = 8, [BAR] = 4, [COAL] = 2 }
plan = M.Plan("Blacksmithing")
Eq(plan.ready[tasks[2]], 2, "bars from the earlier task are used by the next")
Eq(Row(plan, BAR).status, "bags", "the 4 bars not covered by smelting are in the bags")

-- Each task uses up what earlier ones took
Reset()
list = { fullList[1], { "One", "easy", reagents = { { COAL, "Coal", 2 } }, made = 0 }, { "Two", "easy", reagents = { { COAL, "Coal", 2 } }, made = 0 } }
selected = 2; M.AddSelected("TradeSkill", 2)
selected = 3; M.AddSelected("TradeSkill", 2)
carried = { [COAL] = 6 }
tasks = M.Tasks("Blacksmithing")
plan = M.Plan("Blacksmithing")
Eq(plan.ready[tasks[1]], 2, "first task takes what it needs")
Eq(plan.ready[tasks[2]], 1, "second gets the rest")

-- [ Altoholic ]

local function DefaultsTable(t)
  -- like Altoholic's: reading a missing key creates it
  return setmetatable(t, { __index = function(self, key)
    local entry = {}
    rawset(self, key, entry)
    return entry
  end })
end

Reset()
selected = 2
M.AddSelected("TradeSkill", 10)  -- 20 ore
carried = { [ORE] = 2 }
banked = { [ORE] = 3 }
Altoholic = { db = { account = { data = DefaultsTable({
  Horde = DefaultsTable({ Realm = DefaultsTable({ char = DefaultsTable({
    Main = {
      bag = { Bag0 = { size = 4, ids = { ORE }, counts = { 99 } } },
      mail = { { link = Link(ORE), count = 2 } },
    },
    Alt = {
      bag = {
        Bag0 = { size = 2, ids = { ORE, ORE, ORE }, counts = { 5, nil, 40 } }, -- slot 3 is stale
        Bag100 = { size = 1, ids = { ORE }, counts = { 4 } },
        Bag6 = { size = 1, ids = { ORE }, counts = { 2 } },
        ["Bag-2"] = { size = 1, ids = { COAL }, counts = {} },
      },
      mail = { { link = Link(ORE), count = 3 }, { link = Link(COAL) } },
    },
  }) }) }),
  Alliance = DefaultsTable({ Realm = DefaultsTable({ char = DefaultsTable({
    Enemy = { bag = { Bag0 = { size = 1, ids = { ORE }, counts = { 50 } } } },
  }) }) }),
}) } } }

plan = M.Plan("Blacksmithing")
local ore = Row(plan, ORE)
Eq(plan.alts, 2, "alts of both factions on this realm")
Eq(ore.mail, 2, "own mail counted, own stale bags not")
Eq(ore.alts, 65, "alt bags 6, bank 6, mail 3, the other faction's 50; stale slot left out")
Eq(ore.chars[1].name, "Alt", "alts sorted by name")
Eq(ore.chars[1].bags, 6, "alt bags, with an uncounted single item as 1")
Eq(ore.chars[1].bank, 6, "Bag100 and bank bags are bank")
Eq(ore.chars[1].mail, 3, "alt mail")
Eq(ore.chars[2].name, "Enemy", "the other faction is included")
Eq(ore.status, "elsewhere", "2 bags + 3 bank + 2 mail + 15 alts covers 20")
Eq(rawget(Altoholic.db.account.data, "Neutral"), nil, "reading creates nothing")

pfUI_config.trades = { altoholic = "1", mail = "0" }
ore = Row(M.Plan("Blacksmithing"), ORE)
Eq(ore.mail, 0, "mail setting off: own mail")
Eq(ore.alts, 62, "mail setting off: alt mail")

pfUI_config.trades = { altoholic = "0" }
plan = M.Plan("Blacksmithing")
Eq(plan.alts, "off", "Altoholic setting off")
Eq(Row(plan, ORE).alts, 0, "no alts when off")
pfUI_config.trades = { intermediates = "0" }

-- [ Bank reminder ]

local alerts = {}
UIErrorsFrame = { AddMessage = function(_, text) table.insert(alerts, text) end }
local chat = {}
DEFAULT_CHAT_FRAME.AddMessage = function(_, text) said = text; table.insert(chat, text) end

Reset()
selected = 2; M.AddSelected("TradeSkill", 10) -- 20 ore
selected = 3; M.AddSelected("TradeSkill", 1)  -- 4 bars, 1 coal; the 10 smelted cover the bars
M.MyTasks().Mining = { { name = "Other", count = 1, made = 0, reagents = { { id = ORE, name = "Copper Ore", count = 5 } } } }
carried = { [ORE] = 5, [COAL] = 1 }
banked = { [ORE] = 100 }
local bank = M.BankMaterials()
Eq(table.getn(bank), 1, "only what's short and in the bank")
Eq(bank[1].id, ORE, "the ore")
Eq(bank[1].take, 20, "25 needed across professions, 5 carried")

banked = { [ORE] = 8 }
Eq(M.BankMaterials()[1].take, 8, "no more than the bank has")

Fire("BANKFRAME_OPENED")
Eq(table.getn(alerts), 1, "alerts on screen")
Eq(chat[table.getn(chat)], "  8 x Copper Ore", "lists it in chat")

alerts = {}
pfUI_config.trades = { bankreminder = "0" }
Fire("BANKFRAME_OPENED")
Eq(table.getn(alerts), 0, "can be turned off")
pfUI_config.trades = { intermediates = "0" }

carried = { [ORE] = 25, [COAL] = 1 }
Fire("BANKFRAME_OPENED")
Eq(table.getn(alerts), 0, "quiet when the bags already cover it")

carried = { [COAL] = 1 }
banked = {}
Fire("BANKFRAME_OPENED")
Eq(table.getn(alerts), 0, "quiet when the bank has none")

-- [ Alt reminder ]

local function Alt(name, professions)
  M.AccountTasks()[name] = professions
end
local function OreTask(count)
  return { Mining = { { name = "Smelt", count = count, made = 1, item = BAR, reagents = { { id = ORE, name = "Copper Ore", count = 2 } } } } }
end
local function Sends(rows, alt)
  for _, row in ipairs(rows) do
    if row.alt == alt then return row.send end
  end
end

Reset()
pfUITrades_DB = { tasks = { Alchemy = { { name = "Old", count = 1, reagents = {} } }, Empty = {} } }
Fire("PLAYER_LOGIN")
Eq(M.AccountTasks().Main.Alchemy[1].name, "Old", "per-character lists move across at login")
Eq(pfUITrades_DB.tasks, nil, "and leave the old place")
Eq(M.MyTasks().Empty, nil, "empty ones aren't kept")

Reset()
Alt("Aaa", OreTask(5))  -- 10 ore
carried = { [ORE] = 4 }
banked = { [ORE] = 2 }
Eq(Sends(M.AltMaterials(), "Aaa"), 6, "bags and bank both count")

carried = { [ORE] = 40 }
banked = {}
Eq(Sends(M.AltMaterials(), "Aaa"), 10, "no more than the alt needs")

Alt("Bbb", OreTask(25)) -- 50 ore
Eq(Sends(M.AltMaterials(), "Bbb"), 30, "what one alt gets isn't offered to the next")

Reset()
Alt("Aaa", OreTask(5))
selected = 2; M.AddSelected("TradeSkill", 18) -- 36 ore for this character
carried = { [ORE] = 40 }
Eq(Sends(M.AltMaterials(), "Aaa"), 4, "keeps what its own tasks need")

carried = { [ORE] = 30 }
Eq(table.getn(M.AltMaterials()), 0, "nothing spare, nothing offered")

Reset()
pfUITrades_Tasks = { ["Realm|Alliance"] = { Enemy = OreTask(5) }, ["Realm|Horde"] = { Main = {} }, ["Other|Horde"] = { Far = OreTask(5) } }
carried = { [ORE] = 40 }
Eq(Sends(M.AltMaterials(), "Enemy"), 10, "lists saved by faction move across, and the other faction can be mailed")
Eq(pfUITrades_Tasks["Realm|Alliance"], nil, "the old key is gone")
Eq(Sends(M.AltMaterials(), "Far"), nil, "another realm's lists aren't read")

Reset()
Alt("Aaa", OreTask(5))
carried = { [ORE] = 40 }
Altoholic = { db = { account = { data = { Horde = { Realm = { char = {
  Aaa = { bag = { Bag0 = { size = 1, ids = { ORE }, counts = { 3 } } }, mail = { { link = Link(ORE), count = 2 } } },
} } } } } } }
Eq(Sends(M.AltMaterials(), "Aaa"), 5, "what the alt holds comes off")
Altoholic = nil

Reset()
Alt("Aaa", { Mining = {
  { name = "Smelt", count = 5, made = 1, item = BAR, reagents = { { id = ORE, name = "Copper Ore", count = 2 } } },
  { name = "Blade", count = 1, made = 1, reagents = { { id = BAR, name = "Copper Bar", count = 4 } } },
} })
carried = { [ORE] = 40, [BAR] = 40 }
local rows = M.AltMaterials()
Eq(table.getn(rows), 1, "what the alt will make isn't asked for")
Eq(rows[1].id, ORE, "only the ore")

alerts, chat = {}, {}
carried = { [ORE] = 40 }
Fire("MAIL_SHOW")
Eq(table.getn(alerts), 1, "alerts at the mailbox")
Eq(chat[table.getn(chat)], "  10 x Copper Ore for Aaa", "says how many, what and for whom")

alerts = {}
Fire("BANKFRAME_OPENED")
Eq(table.getn(alerts), 1, "and at the bank")

alerts = {}
pfUI_config.trades = { altreminder = "0" }
Fire("MAIL_SHOW")
Eq(table.getn(alerts), 0, "can be turned off")
pfUI_config.trades = { intermediates = "0" }

-- [ Materials you can make ]

local function Names(profession)
  local names = {}
  for _, task in ipairs(M.Tasks(profession)) do table.insert(names, task.name .. " " .. task.count) end
  return table.concat(names, ", ")
end

-- from the open window: the bars a blade needs are smelted first
Reset()
pfUI_config.trades = {}
selected = 3; M.AddSelected("TradeSkill", 2)  -- 8 bars, 2 coal
Eq(Names("Blacksmithing"), "Smelt Copper 8, Copper Blade 2", "the bars are queued above the blade")
Eq(said, "|cff33ffccpf|cffffffffUI|cffaaaaaa Tradeskill:|r also queued 8 x Smelt Copper for Copper Blade.", "and it says so")
M.AddSelected("TradeSkill", 1)
Eq(Names("Blacksmithing"), "Smelt Copper 12, Copper Blade 3", "adding more tops the bars up")

-- what this character holds anywhere comes off
Reset()
pfUI_config.trades = {}
banked = { [BAR] = 3 }
selected = 3; M.AddSelected("TradeSkill", 2)
Eq(Names("Blacksmithing"), "Smelt Copper 5, Copper Blade 2", "bars in the bank come off")
Reset()
pfUI_config.trades = {}
carried = { [BAR] = 8 }
selected = 3; M.AddSelected("TradeSkill", 2)
Eq(Names("Blacksmithing"), "Copper Blade 2", "nothing to make when the bags have them")
Reset()
pfUI_config.trades = {}
Altoholic = { db = { account = { data = { Horde = { Realm = { char = {
  Alt = { bag = { Bag0 = { size = 1, ids = { BAR }, counts = { 6 } } } },
} } } } } } }
selected = 3; M.AddSelected("TradeSkill", 2)
Eq(Names("Blacksmithing"), "Smelt Copper 2, Copper Blade 2", "an alt's bars come off")

-- a smelting task already below the blade moves above it
Reset()
selected = 3; M.AddSelected("TradeSkill", 1)
selected = 2; M.AddSelected("TradeSkill", 1)
pfUI_config.trades = {}
selected = 3; M.AddSelected("TradeSkill", 1)
Eq(Names("Blacksmithing"), "Smelt Copper 8, Copper Blade 2", "the existing task grows and moves up")

-- turned off
Reset()
selected = 3; M.AddSelected("TradeSkill", 2)
Eq(Names("Blacksmithing"), "Copper Blade 2", "nothing extra with the setting off")

-- from another profession: the window has no smelting, the recipe list and IsPlayerSpell do
Reset()
pfUI_config.trades = {}
list = { fullList[1], fullList[3] }
IsPlayerSpell = function(spell) return spell == 2657 end -- Smelt Copper
selected = 2; M.AddSelected("TradeSkill", 2)
local smelt = M.Tasks("Mining")[1]
Eq(smelt and smelt.name, "Smelt Copper", "smelting goes on the Mining list")
Eq(smelt and smelt.count, 8, "as many as the bars needed")
Eq(smelt and smelt.stale, true, "filled in when Mining is opened")
Eq(smelt and smelt.reagents[1].id, ORE, "its ore comes from the recipe list")
Eq(Row(M.Plan("Blacksmithing"), BAR), nil, "the blade's bars count as planned")
Eq(Names("Blacksmithing"), "Copper Blade 2", "the blade's list only has the blade")
Eq(string.find(said, "8 x Smelt Copper (Mining)", 1, true) ~= nil, true, "the message names the profession")
IsPlayerSpell = nil

-- two recipes make the same thing: neither is guessed
Reset()
pfUI_config.trades = {}
list = { fullList[1], fullList[2], { "Other Smelt", "easy", reagents = { { COAL, "Coal", 1 } }, item = BAR, made = 1 }, fullList[3] }
selected = 4; M.AddSelected("TradeSkill", 1)
Eq(Names("Blacksmithing"), "Copper Blade 1", "nothing queued when two recipes make the bars")
Eq(string.find(said, "several of your recipes make Copper Bar", 1, true) ~= nil, true, "and it says so")

-- recipes that make each other's materials stop
Reset()
pfUI_config.trades = {}
local X, Y = 8001, 8002
list = { fullList[1],
  { "Make X", "easy", reagents = { { Y, "Y", 1 } }, item = X, made = 1 },
  { "Make Y", "easy", reagents = { { X, "X", 1 } }, item = Y, made = 1 },
  { "Use X", "easy", reagents = { { X, "X", 1 } }, made = 1 } }
selected = 4; M.AddSelected("TradeSkill", 1)
Eq(table.getn(M.Tasks("Blacksmithing")), 3, "a loop ends")

-- [ Buying from vendors ]

local shop, bought, money = {}, {}, 0
C_MerchantFrame = { GetItemInfo = function(slot) return shop[slot] end }
function GetMerchantNumItems() return table.getn(shop) end
function GetMoney() return money end
function BuyMerchantItem(slot, n) table.insert(bought, slot .. "x" .. n) end
C_Item.GetItemMaxStackSizeByID = function() return 20 end
local FLUX, VIAL = 3466, 3371

local function VendorSetup()
  Reset()
  bought, money = {}, 100000
  list = { fullList[1], { "Thing", "easy", reagents = { { FLUX, "Strong Flux", 1 }, { VIAL, "Vial", 1 } }, made = 1 } }
  selected = 2; M.AddSelected("TradeSkill", 52)
  shop = {
    { itemID = 999, price = 5, stackCount = 1, numAvailable = -1 },
    { itemID = FLUX, price = 10, stackCount = 1, numAvailable = -1 },
    { itemID = VIAL, price = 4, stackCount = 5, numAvailable = -1 },
  }
end

VendorSetup()
carried = { [FLUX] = 50 }
local rows = M.VendorPurchases()
Eq(table.getn(rows), 2, "only what the tasks need")
Eq(rows[1].count, 2, "what the bags are short of")
Eq(rows[2].buys, 11, "52 vials sold by 5 is 11 purchases")
Eq(rows[2].cost, 44, "at the purchase price")
M.BuyVendorMaterials()
Eq(table.concat(bought, " "), "2x2 3x4 3x4 3x3", "a stack's worth per call")
bought = {}
M.BuyVendorMaterials()
Eq(table.getn(bought), 0, "nothing again before they arrive")
carried = { [FLUX] = 52, [VIAL] = 55 }
M.BuyVendorMaterials()
Eq(table.getn(bought), 0, "nor once they have")

VendorSetup()
shop[3].numAvailable = 3
Eq(M.VendorPurchases()[2].buys, 3, "no more than the merchant has")

VendorSetup()
money = 300
rows = M.VendorPurchases()
Eq(rows[1].buys, 30, "the flux takes what money there is")
Eq(rows[1].poor, true, "and is marked short")
Eq(rows[2].buys, 0, "nothing left for vials")

VendorSetup()
banked = { [FLUX] = 52 }
Eq(table.getn(M.VendorPurchases()), 1, "the bank counts")

VendorSetup()
Fire("MERCHANT_SHOW")
Eq(table.getn(bought), 0, "not bought on its own by default")
pfUI_config.trades = { intermediates = "0", autobuy = "1" }
Fire("MERCHANT_SHOW")
Eq(table.getn(bought) > 0, true, "bought on opening with the setting on")
shop = {}

-- [ Crafting ]

local function Tick(seconds)
  now = now + seconds
  M.driver.scripts.OnUpdate()
end

Reset()
selected = 2; M.AddSelected("TradeSkill", 2)  -- Smelt Copper x2
selected = 3; M.AddSelected("TradeSkill", 1)  -- Copper Blade x1
tasks = M.Tasks("Blacksmithing")
carried = { [ORE] = 4, [BAR] = 4, [COAL] = 1 }

M.Start("TradeSkill")
Eq(casts[1][1], "Smelt Copper", "starts with the first task")
Eq(casts[1][2], 2, "as many as it can")
Eq(M.running.left, 2, "running")

Fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "Smelt Copper")
Eq(tasks[1].count, 2, "someone else's cast doesn't count")
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Frostbolt")
Eq(tasks[1].count, 2, "another spell doesn't count")

Fire("UNIT_SPELLCAST_START", "player", "Smelt Copper")
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Smelt Copper")
Eq(tasks[1].count, 1, "counts down")
Eq(M.running ~= nil, true, "batch not done yet")
Fire("UNIT_SPELLCAST_START", "player", "Smelt Copper")
Tick(10)
Eq(M.running ~= nil, true, "a long cast isn't mistaken for the end of the batch")
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Smelt Copper")
Eq(table.getn(tasks), 1, "finished task is removed")
Eq(M.running, nil, "the batch ends, so the button goes back to Start")
Eq(stopped, 0, "finishing a task doesn't stop casting")
Eq(said ~= nil and string.find(said, "Press Start for Copper Blade", 1, true) ~= nil, true, "says what to press next")

Tick(10)
Eq(table.getn(casts), 1, "the next task waits for a click, which the client requires")
carried = { [BAR] = 6, [COAL] = 1 }
M.Start("TradeSkill")
Eq(casts[2][1], "Copper Blade", "the next click casts the next task")
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Copper Blade")
Eq(table.getn(tasks), 0, "all done")
Eq(M.running, nil, "nothing running")
Eq(said ~= nil and string.find(said, "the task list is finished", 1, true) ~= nil, true, "says when the list is done")

Reset()
selected = 2; M.AddSelected("TradeSkill", 1)
selected = 3; M.AddSelected("TradeSkill", 1)
carried = { [ORE] = 2 }
M.Start("TradeSkill")
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Smelt Copper")
Eq(said ~= nil and string.find(said, "waiting for materials", 1, true) ~= nil, true, "says when the rest can't be made yet")

Reset()
selected = 2; M.AddSelected("TradeSkill", 2)
carried = { [ORE] = 4 }
said = nil
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Smelt Copper")
Eq(said, nil, "crafting with the window's own button says nothing")

-- A cast that doesn't happen never leaves the button on Stop
local realCast = DoTradeSkill
local function OneTask()
  Reset()
  selected = 2; M.AddSelected("TradeSkill", 3)
  carried = { [ORE] = 6 }
end

OneTask()
function DoTradeSkill() Fire("UNIT_SPELLCAST_FAILED", "player", "Smelt Copper") end
M.Start("TradeSkill")
Eq(M.running, nil, "a refusal from inside the call")
DoTradeSkill = realCast

OneTask()
function DoTradeSkill() Fire("UNIT_SPELLCAST_FAILED_QUIET", "player", "Smelt Copper") end
M.Start("TradeSkill")
Eq(M.running, nil, "a quiet refusal")
Eq(said ~= nil and string.find(said, "busy", 1, true) ~= nil, true, "says the client was busy")
DoTradeSkill = realCast

OneTask()
function DoTradeSkill() end
M.Start("TradeSkill")
Eq(M.running ~= nil, true, "waiting for the cast")
Tick(3.1)
Eq(M.running, nil, "no cast and no event")
Eq(M.Tasks("Blacksmithing")[1].count, 3, "and the task keeps its count")
DoTradeSkill = realCast

OneTask()
M.Start("TradeSkill")
Fire("UNIT_SPELLCAST_START", "player", "Smelt Copper")
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Smelt Copper")
Tick(3.1)
Eq(M.running, nil, "a batch that ends early with no event")
Eq(M.Tasks("Blacksmithing")[1].count, 2, "keeps what's left")

OneTask()
M.Start("TradeSkill")
Fire("UNIT_SPELLCAST_FAILED_QUIET", "player", "Frostbolt")
Eq(M.running ~= nil, true, "another spell's refusal is ignored")

-- Failing, stopping, closing
Reset()
selected = 2; M.AddSelected("TradeSkill", 5)
carried = { [ORE] = 10 }
M.Start("TradeSkill")
Fire("UNIT_SPELLCAST_FAILED", "player", "Other Spell")
Eq(M.running ~= nil, true, "another spell's failure is ignored")
Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Smelt Copper")
Eq(M.running, nil, "interrupted stops the batch")
Eq(M.Tasks("Blacksmithing")[1].count, 5, "and the task keeps its count")

M.Start("TradeSkill")
M.Stop()
Eq(stopped, 1, "Stop interrupts the batch")
Eq(M.Tasks("Blacksmithing")[1].count, 5, "Stop keeps the remaining count")

M.Start("TradeSkill")
Fire("TRADE_SKILL_CLOSE")
Eq(M.running, nil, "closing the window lets go of the batch")
Eq(stopped, 1, "but leaves it going")

M.Start("TradeSkill")
M.Remove("Blacksmithing", M.Tasks("Blacksmithing")[1])
Eq(M.running, nil, "removing the running task stops")
Eq(stopped, 2, "and interrupts it")

-- Nothing ready: no cast
Reset()
selected = 2; M.AddSelected("TradeSkill", 1)
M.Start("TradeSkill")
Eq(table.getn(casts), 0, "no materials, no cast")

-- A task hidden by the subclass filter still gets cast at its real row, and the filter returns
Reset()
selected = 3; M.AddSelected("TradeSkill", 1)
carried = { [BAR] = 4, [COAL] = 1 }
SetTradeSkillSubClassFilter(1)
Eq(table.getn(list), 2, "filter hides the recipe")
M.Start("TradeSkill")
Eq(casts[1][1], "Copper Blade", "hidden recipe is found")
Eq(casts[1][3], 3, "cast with the full list showing")
Eq(subFilter, 1, "filter restored")
Eq(table.getn(list), 2, "list restored")

-- Enchanting: one at a time, no queue
Reset()
local crafts = {
  { "Enchant Bracer", "optimal", reagents = { { COAL, "Strange Dust", 2 } } },
}
local crafted = 0
function GetCraftDisplaySkillLine() return "Enchanting", 100, 300 end
function GetNumCrafts() return 1 end
function GetCraftSelectionIndex() return 1 end
function GetCraftInfo(i) local c = crafts[i]; return c[1], "", c[2], 0, true end
function GetCraftIcon() return "icon" end
function GetCraftNumReagents() return 1 end
function GetCraftReagentInfo(_, r) local x = crafts[1].reagents[r]; return x[2], "ricon", x[3] end
function GetCraftReagentItemID(_, r) return crafts[1].reagents[r][1] end
function GetCraftSpellID() return 7000 end
function IsCraftLinked() return false end
function DoCraft() crafted = crafted + 1 end
M.AddSelected("Craft", 2)
carried = { [COAL] = 4 }
M.Start("Craft")
Eq(crafted, 1, "one enchant")
Eq(M.running, nil, "enchanting doesn't queue")
Eq(M.Tasks("Enchanting")[1].count, 2, "doesn't count until it goes off")
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Enchant Bracer")
Eq(M.Tasks("Enchanting")[1].count, 1, "counts when it goes off")
function GetCraftDisplaySkillLine() return nil end

-- [ The panel ]

T = setmetatable({}, { __index = function(_, key) return key end })
C = pfUI_config
C.global = { font_size = 12 }
for _, name in ipairs({ "SkinButton", "SkinArrowButton", "SkinScrollbar", "SkinCloseButton", "SkinCheckbox", "CreateBackdropShadow", "FauxScrollFrame_OnVerticalScroll" }) do
  _G[name] = function() end
end
-- pfUI's makes the backdrop a child frame, frame.backdrop
function CreateBackdrop(frame) frame.backdrop = rawget(frame, "backdrop") or CreateFrame("Frame", nil, frame) end
function FauxScrollFrame_Update() end
function FauxScrollFrame_GetOffset(frame) return rawget(frame, "offset") end
function FauxScrollFrame_SetOffset(frame, offset) frame.offset = offset end
function HookAddon(_, func) func() end
function HookScript(f, script, func) f.scripts[script] = func end
function IsAddOnLoaded() return false end
pfUI.gui = nil
GameTooltip = NewFrame("GameTooltip")
TradeSkillInputBox = NewFrame("EditBox")
UIParent = NewFrame("Frame")
TradeSkillFrame = NewFrame("Frame")
CraftFrame = NewFrame("Frame")
TradeSkillDetailScrollFrame = NewFrame("ScrollFrame")
TradeSkillListScrollFrame = NewFrame("ScrollFrame")
CraftListScrollFrame = NewFrame("ScrollFrame")
CraftDetailScrollFrame = NewFrame("ScrollFrame")

Reset()
module()
Eq(rawget(TradeSkillListScrollFrame, "offset"), 0, "the stock list has an offset before it's first drawn")
Eq(rawget(CraftListScrollFrame, "offset"), 0, "and so does the craft list")
TradeSkillFrame.scripts.OnShow()
pfUITradesButton1.scripts.OnClick()
local panel = pfUITradesPanel
Eq(panel ~= nil and panel.shown, true, "the Queue button opens the panel")
Eq(pfUITrades_DB.open, 1, "and that's remembered")
panel.close.scripts.OnClick()
Eq(panel.shown, false, "the X closes the queue panel")
Eq(pfUITrades_DB.open, nil, "and forgets it was open")
pfUITradesButton1.scripts.OnClick()
Eq(panel.mouse, true, "the panel catches clicks on its background")
TradeSkillFrame.level = 40
pfUITradesButton1.scripts.OnClick()
pfUITradesButton1.scripts.OnClick()
Eq(panel:GetFrameLevel(), 50, "the panel sits above the window")
Eq(panel.add:GetFrameLevel(), 51, "and its buttons above the panel")
Eq(panel.taskRows[1]:GetFrameLevel(), 51, "and its rows")

selected = 2
carried = { [ORE] = 2 }
banked = { [ORE] = 1 }
panel.add.scripts.OnClick()
Eq(M.Tasks("Blacksmithing")[1].count, 3, "Add uses the window's amount")
Eq(panel.taskRows[1].name.text, "Smelt Copper", "task row")
Eq(panel.taskRows[1].count.text, "|cffffff4d1/3|r", "ready of total")
Eq(panel.materialRows[1].name.text, "Copper Ore", "material row")
Eq(panel.materialRows[1].need.text, "6", "needed")
Eq(panel.materialRows[1].bags.text, "2", "in bags")
Eq(panel.materialRows[1].bank.text, "1", "in bank")
Eq(pfUITradesButton1.label, "Queue (1)", "the button shows how many")
Eq(panel.start.label, "Start", "start label")

panel.start.scripts.OnClick()
Eq(casts[1][1], "Smelt Copper", "Start casts")
Eq(panel.start.label, "Stop", "becomes Stop")
panel.start.scripts.OnClick()
Eq(M.running, nil, "Stop stops")

-- [ Missing recipes ]
-- the stub window is Blacksmithing with Smelt Copper (a Mining recipe) and Copper Blade
local bs = table.getn(M.RecipeDB.Blacksmithing)
local list, total, rank = M.Missing("TradeSkill")
Eq(total, bs, "the list has every Blacksmithing recipe")
Eq(table.getn(list), bs, "none of them is in the stub window")
-- a known recipe by name, and one by spell ID through IsPlayerSpell
fullList[3][1] = "Copper Mace"
IsPlayerSpell = function(spell) return spell == 2660 end	-- Rough Sharpening Stone
list = M.Missing("TradeSkill")
local seen = {}
for _, m in ipairs(list) do seen[m.name] = true end
Eq(seen["Copper Mace"], nil, "a recipe in the window isn't missing")
Eq(seen["Rough Sharpening Stone"], nil, "nor one IsPlayerSpell knows")
Eq(table.getn(list), bs - 2, "the rest are")
IsPlayerSpell = nil
fullList[3][1] = "Copper Blade"

-- with Altoholic loaded first, its copy of the list is used instead of a second one
local ownDB = M.RecipeDB
Altoholic = { RecipeDB = { Mining = {} }, L = { ["Smelt Tin"] = "Zinn verhütten" } }
dofile("recipes.lua")
dofile("recipes-locale.lua")
Eq(M.RecipeDB, Altoholic.RecipeDB, "Altoholic's recipe list is shared")
Eq(M.RecipeName("Smelt Tin"), "Zinn verhütten", "and its translations")
M.RecipeDB, M.RecipeNamesFrom, Altoholic = ownDB, nil, nil

-- with Altoholic loaded, its copy of the shared code runs; without it, this addon's own
Eq(M.sharedWithAltoholic, nil, "alone, it uses its own code")
local own = {}
for _, k in ipairs({ "HasItemSources", "ItemSources", "AddItemSources", "ShowItemOnMap", "EnglishProfession", "RecipeKey", "ParseReagents" }) do
  own[k] = M[k]
end
local calls = {}
Altoholic = {}
for k in pairs(own) do
  Altoholic[k] = function(self, a) table.insert(calls, k) return k == "ParseReagents" and { { 1, 2 } } or "altoholic" end
end
Eq(M.UseAltoholic(), true, "with Altoholic loaded it switches to Altoholic's code")
Eq(M.ItemSources(6053), "altoholic", "item sources come from Altoholic")
Eq(M.ShowItemOnMap(6053), "altoholic", "and so does the map")
Eq(M.ParseReagents("1:2")[1][2], 2, "and the reagent reader")
Eq(table.getn(calls), 3, "each call went to Altoholic")
Altoholic = {}
Eq(M.UseAltoholic(), false, "an Altoholic without that code (no ClassicAPI) isn't used")
Altoholic = nil
for k, f in pairs(own) do M[k] = f end
M.sharedWithAltoholic = nil

-- where a recipe item comes from, with pfQuest's database
Eq(M.HasItemSources(), false, "no sources without pfQuest")
pfDB = {
  items = { data = { [6053] = { V = { [10] = 1 }, U = { [20] = 2.5 } } } },
  units = { data = { [10] = { coords = { { 50, 50, 1519, 0 } } }, [20] = { coords = { { 1, 1, 40, 0 } } } },
    loc = { [10] = "Vendor Vic", [20] = "Mob Max" } },
  objects = { data = {}, loc = {} }, refloot = { data = {} },
  zones = { loc = { [1519] = "Stormwind City", [40] = "Westfall" } },
}
local src = M.ItemSources(6053)
Eq(src and src.vendors[1].name .. " / " .. src.vendors[1].zone, "Vendor Vic / Stormwind City", "a vendor and its zone")
Eq(src and src.drops[1].zone, "Westfall", "a drop's zone")
local mapped
pfDatabase = { SearchItemID = function(_, id) mapped = id return { [1519] = 1 } end, GetBestMap = function(_, m) return next(m) end }
pfMap = { ShowMapID = function(_, map) mapped = mapped and map end, DeleteNode = function() end }
Eq(M.ShowItemOnMap(6053) and mapped, 1519, "the item goes on pfQuest's map")
pfDB, pfDatabase, pfMap = nil, nil, nil

-- the panel
local queueWasOpen = panel.shown
if not panel.shown then pfUITradesButton1.scripts.OnClick() end	-- Queue open first: Missing replaces it
Eq(panel.shown, true, "the queue panel is open")
GetItemInfo = function() end
GetItemQualityColor = function() return 1, 1, 1, "|cffffffff" end
pfUITradesButton2.scripts.OnClick()
local mp = pfUITradesMissingPanel
Eq(mp ~= nil and mp.shown, true, "the Missing button opens the missing panel")
Eq(pfUITrades_DB.missingOpen, 1, "and that's remembered")
Eq(panel.shown, false, "opening Missing closes the queue panel")
Eq(pfUITrades_DB.open, nil, "and the queue panel isn't remembered as open")
Eq(rawget(mp.rows[1], "entry") ~= nil, true, "it lists the missing recipes")
-- the stub window gives no rank, so nothing can be learned now
mp.only.GetChecked = function() return 1 end	-- a click ticks the box before OnClick
this = mp.only
mp.only.scripts.OnClick()
Eq(rawget(mp.rows[1], "entry"), nil, "Learnable now narrows to what the rank allows")
Eq(mp.empty.text, "Nothing more to learn at this skill.", "and says so")
mp.only.GetChecked = function() return nil end
mp.only.scripts.OnClick()
Eq(rawget(mp.rows[1], "entry") ~= nil, true, "All recipes lists them again")
-- the panel follows the window's own layout once it can be measured: a window whose top is
-- at 500, title 490-478, rank bar 460-440, details pane from 430, recipe list pane to 80
local function At(t, b) return { GetTop = function() return t end, GetBottom = function() return b end } end
TradeSkillFrame.GetTop = function() return 500 end
TradeSkillFrameTitleText = At(490, 478)
TradeSkillRankFrame = At(460, 440)
TradeSkillDetailScrollFrame.backdrop = At(430, 200)
TradeSkillListScrollFrame.backdrop = At(430, 80)
TradeSkillCancelButton = At(90, 75)
this, arg1 = mp, 1	-- OnUpdate handlers read the 1.12 globals
mp.scripts.OnUpdate()
Eq(mp.visible, 18, "rows fill the pane from the details' top to the list's bottom")
Eq(mp.only.point[1], "LEFT", "the button is centred on the rank bar")
TradeSkillFrame.GetTop, TradeSkillFrameTitleText, TradeSkillRankFrame, TradeSkillCancelButton = nil, nil, nil, nil
TradeSkillDetailScrollFrame.backdrop, TradeSkillListScrollFrame.backdrop = nil, nil

mp.close.scripts.OnClick()
Eq(mp.shown, false, "the X closes the missing panel")
Eq(pfUITrades_DB.missingOpen, nil, "and forgets it was open")
pfUITradesButton2.scripts.OnClick()
pfUITradesButton1.scripts.OnClick()
Eq(panel.shown and not mp.shown, true, "opening Queue closes the missing panel")
Eq(pfUITrades_DB.missingOpen, nil, "and forgets it was open")
pfUITradesButton1.scripts.OnClick()
pfUITradesButton2.scripts.OnClick()
pfUITradesButton2.scripts.OnClick()
Eq(mp.shown, false, "and Missing closes again")
if queueWasOpen then pfUITradesButton1.scripts.OnClick() end	-- back as the tests below expect

this = panel.materialRows[1]
this.scripts.OnEnter()
panel.clear.scripts.OnClick()
Eq(table.getn(M.Tasks("Blacksmithing")), 0, "Clear empties the list")
Eq(panel.taskRows[1].shown, false, "rows hide")

-- The Queue button sits at the bottom left of the recipe details
Eq(pfUITradesButton1.point[1], "BOTTOMLEFT", "Queue button corner")
Eq(pfUITradesButton1.point[2], TradeSkillDetailScrollFrame, "Queue button anchor")
-- buttons in order: the trade skill window's Queue and Missing, then the craft window's
Eq(pfUITradesButton3.point[2], CraftDetailScrollFrame, "Queue button anchor on the craft window")

-- Beast Training has no profession line, so no button or panel
CraftFrame.scripts.OnShow()
Eq(pfUITradesButton3.shown, false, "no Queue button on Beast Training")
Eq(pfUITradesButton4.shown, false, "nor a Missing one")

-- the merchant button shows while the merchant sells something the tasks are short of
MerchantFrame = NewFrame("Frame")
MerchantFrame:Show()
VendorSetup()
M.onChange()
local buyButton
for i = 1, 200 do
  local b = _G["pfUITradesButton" .. i]
  if b and b.parent == MerchantFrame then buyButton = b end
end
Eq(buyButton ~= nil and buyButton.shown, true, "a Buy button on the merchant window")
this = buyButton
buyButton.scripts.OnEnter()
buyButton.scripts.OnClick()
Eq(table.getn(bought) > 0, true, "it buys")
Eq(buyButton.shown, false, "and hides once nothing is left to buy")
MerchantFrame, shop = nil, {}

print(passed .. " passed, " .. failures .. " failed")
os.exit(failures == 0 and 0 or 1)
