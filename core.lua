-- Tasks, materials and the crafting queue. Nothing here touches the panel: ui.lua sets
-- pfUITrades.onChange and redraws from pfUITrades.Plan().
--
-- A task is { name, spell, count, icon, item, made, reagents = { { id, name, icon, count }, ... } }.
-- Reagents are stored on the task, so materials can be worked out while the recipe's window
-- isn't the one the client has data for. count is the number of crafts left, not of items.

pfUITrades = {}
local M = pfUITrades

local function Say(text)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffUI|cffaaaaaa Tradeskill:|r " .. text)
end
M.Say = Say

local function Changed()
  M.recipeInfo = {} -- what the tooltips worked out may be out of date
  if M.onChange then M.onChange() end
end

local function ItemID(link)
  if not link then return nil end
  local _, _, id = string.find(link, "item:(%d+)")
  return tonumber(id)
end

-- The client can give a reagent's ID before it has the item's name and icon. Asking by ID also
-- makes it fetch them.
local function ReadReagent(id, name, icon, count)
  if not id then return nil end
  return {
    id = id,
    name = name or C_Item.GetItemNameByID(id) or ("item:" .. id),
    icon = icon or C_Item.GetItemIconByID(id),
    count = count,
  }
end

function M.DB()
  pfUITrades_DB = pfUITrades_DB or {}
  return pfUITrades_DB
end

-- Task lists are account-wide so that characters can see each other's:
-- pfUITrades_Tasks[realm][character][profession] = { task, ... }
-- By realm alone: this server lets the two factions mail each other.
function M.AccountTasks()
  pfUITrades_Tasks = pfUITrades_Tasks or {}
  local realm = GetRealmName()
  pfUITrades_Tasks[realm] = pfUITrades_Tasks[realm] or {}

  -- lists from when they were also keyed by faction
  for _, faction in ipairs({ "Alliance", "Horde" }) do
    local old = realm .. "|" .. faction
    if pfUITrades_Tasks[old] then
      for name, professions in pairs(pfUITrades_Tasks[old]) do
        pfUITrades_Tasks[realm][name] = professions
      end
      pfUITrades_Tasks[old] = nil
    end
  end
  return pfUITrades_Tasks[realm]
end

function M.MyTasks()
  local account = M.AccountTasks()
  local me = UnitName("player")
  account[me] = account[me] or {}

  -- lists from when they were saved per character
  local db = M.DB()
  if db.tasks then
    for profession, tasks in pairs(db.tasks) do
      if table.getn(tasks) > 0 then account[me][profession] = tasks end
    end
    db.tasks = nil
  end
  return account[me]
end

function M.Option(key)
  local config = pfUI_config and pfUI_config.trades
  return not config or config[key] ~= "0"
end

-- for settings that are off unless turned on
function M.OptionSet(key)
  local config = pfUI_config and pfUI_config.trades
  return config and config[key] == "1" or false
end

-- [ The two profession windows ]

-- The subclass and slot dropdowns and collapsed headers change which rows exist, and so every
-- row's index. The window's search box and checkboxes don't: they only filter the drawing.
local function ActiveFilter(getFilter, options)
  for i = 0, table.getn(options) do
    if getFilter(i) then return i end
  end
end

local TradeSkill = { batch = true, frame = "TradeSkillFrame" }

function TradeSkill.Profession()
  local name = GetTradeSkillLine()
  if name and name ~= "UNKNOWN" then return name end
end

function TradeSkill.Linked()
  return IsTradeSkillLinked()
end

function TradeSkill.Count() return GetNumTradeSkills() end
function TradeSkill.Selected() return GetTradeSkillSelectionIndex() end
function TradeSkill.Info(i) return GetTradeSkillInfo(i) end
function TradeSkill.Cast(i, count) DoTradeSkill(i, count) end
function TradeSkill.Item(i) return GetTradeSkillItemID(i) end

function TradeSkill.Select(i)
  TradeSkillFrame_SetSelection(i)
  TradeSkillFrame_Update()
end

function TradeSkill.Read(i)
  local name, kind = GetTradeSkillInfo(i)
  if not name or kind == "header" then return nil end

  local _, _, spell = string.find(GetTradeSkillRecipeLink(i) or "", "|Henchant:(%d+)")
  local task = {
    name = name,
    spell = tonumber(spell),
    icon = GetTradeSkillIcon(i),
    item = GetTradeSkillItemID(i),
    made = GetTradeSkillNumMade(i) or 1,
    reagents = {},
  }
  for r = 1, GetTradeSkillNumReagents(i) do
    local rname, ricon, rcount = GetTradeSkillReagentInfo(i, r)
    local reagent = ReadReagent(GetTradeSkillReagentItemID(i, r), rname, ricon, rcount)
    if not reagent then return nil end
    table.insert(task.reagents, reagent)
  end
  return task
end

function TradeSkill.WithFullList(run)
  local subclass = ActiveFilter(GetTradeSkillSubClassFilter, { GetTradeSkillSubClasses() })
  local invslot = ActiveFilter(GetTradeSkillInvSlotFilter, { GetTradeSkillInvSlots() })
  local selected = GetTradeSkillSelectionIndex()
  local collapsed

  if subclass and subclass > 0 then SetTradeSkillSubClassFilter(0, 1, 1) end
  if invslot and invslot > 0 then SetTradeSkillInvSlotFilter(0, 1, 1) end

  for i = 1, GetNumTradeSkills() do
    local name, kind, _, expanded = GetTradeSkillInfo(i)
    if kind == "header" and not expanded then
      collapsed = collapsed or {}
      collapsed[name] = true
    end
  end
  if collapsed then ExpandTradeSkillSubClass(0) end

  -- whatever run does, the player's list has to come back
  local ok, failure = pcall(run)

  if collapsed then
    for i = GetNumTradeSkills(), 1, -1 do
      local name, kind = GetTradeSkillInfo(i)
      if kind == "header" and collapsed[name] then CollapseTradeSkillSubClass(i) end
    end
  end
  if invslot and invslot > 0 then SetTradeSkillInvSlotFilter(invslot, 1, 1) end
  if subclass and subclass > 0 then SetTradeSkillSubClassFilter(subclass, 1, 1) end
  if collapsed or (invslot and invslot > 0) or (subclass and subclass > 0) then
    SelectTradeSkill(selected)
  end

  if not ok then error(failure, 0) end
end

-- Enchanting. A craft waits for the player to click the item it goes on, so it can't repeat or
-- run unattended; Start casts one and the task counts down when the enchant goes off.
local Craft = { batch = false, frame = "CraftFrame" }

function Craft.Profession()
  return (GetCraftDisplaySkillLine()) -- nil for Beast Training, which has no materials
end

function Craft.Linked()
  return IsCraftLinked()
end

function Craft.Count() return GetNumCrafts() end
function Craft.Selected() return GetCraftSelectionIndex() end
function Craft.Cast(i) DoCraft(i) end

function Craft.Info(i)
  local name, _, kind, available, expanded = GetCraftInfo(i)
  return name, kind, available, expanded
end

function Craft.Select(i)
  CraftFrame_SetSelection(i)
  CraftFrame_Update()
end

function Craft.Read(i)
  local name, _, kind = GetCraftInfo(i)
  if not name or kind == "header" then return nil end

  local task = { name = name, spell = GetCraftSpellID(i), icon = GetCraftIcon(i), made = 0, reagents = {} }
  for r = 1, GetCraftNumReagents(i) do
    local rname, ricon, rcount = GetCraftReagentInfo(i, r)
    local reagent = ReadReagent(GetCraftReagentItemID(i, r), rname, ricon, rcount)
    if not reagent then return nil end
    table.insert(task.reagents, reagent)
  end
  return task
end

function Craft.WithFullList(run)
  local selected = GetCraftSelectionIndex()
  local collapsed

  for i = 1, GetNumCrafts() do
    local name, _, kind, _, expanded = GetCraftInfo(i)
    if kind == "header" and not expanded then
      collapsed = collapsed or {}
      collapsed[name] = true
    end
  end
  if collapsed then ExpandCraftSkillLine(0) end

  local ok, failure = pcall(run)

  if collapsed then
    for i = GetNumCrafts(), 1, -1 do
      local name, _, kind = GetCraftInfo(i)
      if kind == "header" and collapsed[name] then CollapseCraftSkillLine(i) end
    end
    SelectCraft(selected)
  end

  if not ok then error(failure, 0) end
end

-- a row's own spell ID, and the player's rank in the window's profession
function TradeSkill.Spell(i)
  local _, _, spell = string.find(GetTradeSkillRecipeLink(i) or "", "enchant:(%d+)")
  return tonumber(spell)
end
function TradeSkill.Rank() local _, rank = GetTradeSkillLine() return rank or 0 end
function Craft.Spell(i) return GetCraftSpellID and GetCraftSpellID(i) end
function Craft.Rank() local _, rank = GetCraftDisplaySkillLine() return rank or 0 end

M.windows = { TradeSkill = TradeSkill, Craft = Craft }

local function FindRow(window, name)
  for i = 1, window.Count() do
    local rowName, kind = window.Info(i)
    if rowName == name and kind ~= "header" then return i end
  end
end

-- Calls found(index) with the recipe's current row, widening the list only if it's hidden.
local function WithRecipe(window, name, found)
  local i = FindRow(window, name)
  if i then
    found(i)
    return true
  end

  local done
  window.WithFullList(function()
    i = FindRow(window, name)
    if i then
      found(i)
      done = true
    end
  end)
  return done
end

-- [ Tasks ]

function M.Tasks(profession)
  local tasks = M.MyTasks()
  tasks[profession] = tasks[profession] or {}
  return tasks[profession]
end

function M.AddSelected(ctx, count)
  local window = M.windows[ctx]
  local profession = window.Profession()
  local selected = window.Selected()
  if not profession or not selected or selected == 0 then return end

  local task = window.Read(selected)
  if not task then
    local name, kind = window.Info(selected)
    if name and kind ~= "header" then Say("couldn't read the materials for " .. name .. ", try again.") end
    return
  end

  local tasks = M.Tasks(profession)
  local added
  for _, existing in ipairs(tasks) do
    if existing.name == task.name then
      existing.count = existing.count + count
      added = existing
      break
    end
  end
  if not added then
    task.count = count
    table.insert(tasks, task)
    added = task
  end

  if M.Option("intermediates") then M.AddIntermediates(ctx, profession, added) end
  Changed()
  return added
end

-- Adds crafts to any character's list on this realm; Altoholic's Recipes page uses it to queue
-- work for an alt. The task is shaped like AddSelected's, but what Altoholic doesn't record
-- (the spell ID, how many one craft makes) may be missing or guessed, so it is marked stale and
-- RefreshTasks fills it in from the recipe the next time that character opens the profession.
-- Until then a cast still finds it by name.
function M.QueueFor(character, profession, task, count)
  if not character or not profession or not task or not task.name then return end
  count = count or 1
  local tasks
  if character == UnitName("player") then
    tasks = M.Tasks(profession)
  else
    local account = M.AccountTasks()
    account[character] = account[character] or {}
    account[character][profession] = account[character][profession] or {}
    tasks = account[character][profession]
  end

  for _, existing in ipairs(tasks) do
    if existing.name == task.name then
      existing.count = existing.count + count
      Changed()
      return existing
    end
  end

  task.count = count
  task.reagents = task.reagents or {}
  task.stale = true
  table.insert(tasks, task)
  Changed()
  return task
end

-- How many crafts of a recipe are on a character's list, for Altoholic to show.
function M.QueuedFor(character, profession, name)
  local account = M.AccountTasks()
  local tasks = account[character] and account[character][profession]
  for _, task in ipairs(tasks or {}) do
    if task.name == name then return task.count end
  end
  return 0
end

-- Fills in the tasks QueueFor added from the recipe itself, once its window is open on the
-- character the list belongs to. Only rows already shown are read, so the player's filters and
-- folded headers stay as they are; a hidden recipe is filled in on a later opening.
function M.RefreshTasks(ctx)
  local window = M.windows[ctx]
  if not window or window.Linked() then return end
  local profession = window.Profession()
  local tasks = profession and M.MyTasks()[profession]
  if not tasks then return end
  local changed
  for _, task in ipairs(tasks) do
    if task.stale then
      local i = FindRow(window, task.name)
      local fresh = i and window.Read(i)
      if fresh then
        task.spell, task.icon, task.item = fresh.spell, fresh.icon, fresh.item
        task.made, task.reagents = fresh.made, fresh.reagents
        task.stale = nil
        changed = true
      end
    end
  end
  if changed then Changed() end
end

local function Position(tasks, task)
  for i, candidate in ipairs(tasks) do
    if candidate == task then return i end
  end
end

function M.Remove(profession, task)
  local tasks = M.Tasks(profession)
  local i = Position(tasks, task)
  if not i then return end
  if M.running and M.running.task == task then M.Stop() end
  table.remove(tasks, i)
  Changed()
end

function M.Adjust(profession, task, delta)
  task.count = task.count + delta
  if task.count <= 0 then
    M.Remove(profession, task)
  else
    Changed()
  end
end

function M.Move(profession, task, delta)
  local tasks = M.Tasks(profession)
  local i = Position(tasks, task)
  local j = i and i + delta
  if not j or j < 1 or j > table.getn(tasks) then return end
  tasks[i], tasks[j] = tasks[j], tasks[i]
  Changed()
end

function M.Clear(profession)
  if M.running and M.running.profession == profession then M.Stop() end
  M.MyTasks()[profession] = {}
  Changed()
end

function M.SelectTask(ctx, task)
  local window = M.windows[ctx]
  local i = FindRow(window, task.name)
  if i then window.Select(i) end
end

-- [ Materials ]

-- Reads the other characters of this realm, of either faction, since this server lets them mail
-- each other, plus this character's own mail. Their bags and banks only change while they're
-- logged in, and this character's are read live, so its bags and bank are skipped. rawget,
-- because reading a missing entry from Altoholic's database creates it.
local function ReadAltoholic(wanted)
  local found = {}
  if not M.Option("altoholic") then return found, "off" end

  local account = Altoholic and Altoholic.db and Altoholic.db.account
  local data = account and rawget(account, "data")
  if not data then return found, "missing" end

  local me = UnitName("player")
  local useMail = M.Option("mail")
  local alts = 0

  local function Add(id, name, source, amount)
    found[id] = found[id] or {}
    found[id][name] = found[id][name] or { name = name, bags = 0, bank = 0, mail = 0 }
    found[id][name][source] = found[id][name][source] + amount
  end

  local function ReadCharacter(name, c)
    if name ~= me then
      alts = alts + 1
      for bagName, b in pairs(rawget(c, "bag") or {}) do
        local isBank = bagName == "Bag100"
        local number = tonumber(string.sub(bagName, 4))
        if number and number > 4 then isBank = true end
        local ids, counts = b.ids or {}, b.counts or {}
        -- only up to size: a smaller bag swapped in leaves old entries past its end
        for slot = 1, b.size or 0 do
          local id = ids[slot]
          if id and wanted[id] then
            local amount = counts[slot]
            if not amount or amount == 0 then amount = 1 end
            Add(id, name, isBank and "bank" or "bags", amount)
          end
        end
      end
    end

    if useMail then
      for _, mail in pairs(rawget(c, "mail") or {}) do
        local id = ItemID(mail.link)
        if id and wanted[id] then
          local amount = mail.count
          if not amount or amount == 0 then amount = 1 end
          Add(id, name, "mail", amount)
        end
      end
    end
  end

  for _, faction in pairs(data) do
    local realm = rawget(faction, GetRealmName())
    local chars = realm and rawget(realm, "char")
    for name, c in pairs(chars or {}) do ReadCharacter(name, c) end
  end

  return found, alts
end

-- How many of each item a character's lists will make, by item ID, over all its professions.
local function Planned(professions)
  local planned = {}
  for _, tasks in pairs(professions) do
    for _, task in ipairs(tasks) do
      if task.item then
        planned[task.item] = (planned[task.item] or 0) + task.count * math.max(task.made or 1, 1)
      end
    end
  end
  return planned
end

-- How many of each wanted item this character can get at: bags, bank, its mail and its alts,
-- the same total as the materials table (and turned off with it).
-- Also returns them by place: parts[id] = { bags, bank, mail, alts }.
local function Holdings(wanted)
  local have, parts = {}, {}
  for id in pairs(wanted) do
    local bags, all = C_Item.GetItemCount(id), C_Item.GetItemCount(id, true)
    have[id] = all
    parts[id] = { bags = bags, bank = all - bags, mail = 0, alts = 0 }
  end
  local me = UnitName("player")
  for id, chars in pairs(ReadAltoholic(wanted)) do
    for name, entry in pairs(chars) do
      local held = entry.bags + entry.bank + entry.mail
      have[id] = have[id] + held
      if name == me then
        parts[id].mail = parts[id].mail + held
      else
        parts[id].alts = parts[id].alts + held
      end
    end
  end
  return have, parts
end

function M.Have(id)
  return Holdings({ [id] = true })[id]
end

-- Works out, for a profession's tasks in order:
--   plan.ready[task]  crafts possible from what's in the bags now. Each task uses up what
--                     earlier tasks leave and can use what they make, so bars smelted by one
--                     task count towards the next.
--   plan.materials    a row per reagent still needed: need, bags, bank, mail, alts (totals),
--                     chars (per-alt breakdown), status bags/bank/elsewhere/short.
--   plan.alts         number of alts read, or "off"/"missing"
function M.Plan(profession)
  local tasks = M.Tasks(profession)
  local plan = { tasks = tasks, ready = {}, materials = {} }
  local stock, needed, order = {}, {}, {}
  -- what any of this character's lists will make, so bars on the Mining list count for Blacksmithing
  local planned = Planned(M.MyTasks())

  local function InBags(id)
    if not stock[id] then stock[id] = C_Item.GetItemCount(id) end
    return stock[id]
  end

  for _, task in ipairs(tasks) do
    local ready = task.count
    for _, reagent in ipairs(task.reagents) do
      ready = math.min(ready, math.floor(InBags(reagent.id) / reagent.count))
      if not needed[reagent.id] then
        needed[reagent.id] = { id = reagent.id, name = reagent.name, icon = reagent.icon, need = 0 }
        table.insert(order, needed[reagent.id])
      end
      needed[reagent.id].need = needed[reagent.id].need + task.count * reagent.count
    end
    for _, reagent in ipairs(task.reagents) do
      stock[reagent.id] = stock[reagent.id] - ready * reagent.count
    end
    if task.item then
      stock[task.item] = InBags(task.item) + ready * task.made
    end
    plan.ready[task] = ready
  end

  local wanted = {}
  for _, row in ipairs(order) do wanted[row.id] = true end
  local found
  found, plan.alts = ReadAltoholic(wanted)

  local me = UnitName("player")
  for _, row in ipairs(order) do
    row.need = row.need - (planned[row.id] or 0)
    if row.need > 0 then
      row.bags = C_Item.GetItemCount(row.id)
      row.bank = C_Item.GetItemCount(row.id, true) - row.bags
      row.mail, row.alts, row.chars = 0, 0, {}

      for name, entry in pairs(found[row.id] or {}) do
        if name == me then
          row.mail = entry.mail
        else
          row.alts = row.alts + entry.bags + entry.bank + entry.mail
          table.insert(row.chars, entry)
        end
      end
      table.sort(row.chars, function(a, b) return a.name < b.name end)

      if row.bags >= row.need then
        row.status = "bags"
      elseif row.bags + row.bank >= row.need then
        row.status = "bank"
      elseif row.bags + row.bank + row.mail + row.alts >= row.need then
        row.status = "elsewhere"
      else
        row.status = "short"
      end
      table.insert(plan.materials, row)
    end
  end

  return plan
end

-- What a character's tasks need overall, by item ID. What any of its tasks makes comes off,
-- as in M.Plan.
local function NetNeeds(professions)
  local needed = {}
  for _, tasks in pairs(professions) do
    for _, task in ipairs(tasks) do
      for _, reagent in ipairs(task.reagents or {}) do
        needed[reagent.id] = needed[reagent.id] or { name = reagent.name, need = 0 }
        needed[reagent.id].need = needed[reagent.id].need + task.count * reagent.count
      end
    end
  end
  local planned, needs = Planned(professions), {}
  for id, row in pairs(needed) do
    local need = row.need - (planned[id] or 0)
    if need > 0 then needs[id] = { name = row.name, need = need } end
  end
  return needs
end

-- What to take out of the bank for the tasks of every profession, as rows of id, name, take: only
-- what the bags are short of and the bank has.
function M.BankMaterials()
  local rows = {}
  for id, row in pairs(NetNeeds(M.MyTasks())) do
    local bags = C_Item.GetItemCount(id)
    local take = math.min(row.need - bags, C_Item.GetItemCount(id, true) - bags)
    if take > 0 then table.insert(rows, { id = id, name = row.name, need = row.need, take = take }) end
  end
  table.sort(rows, function(a, b) return a.name < b.name end)
  return rows
end

local function BankReminder()
  if not M.Option("bankreminder") then return end
  local rows = M.BankMaterials()
  if table.getn(rows) == 0 then return end

  UIErrorsFrame:AddMessage("Your bank has materials for your task list", 1, .8, .2)
  Say("take these from the bank for your task list:")
  for _, row in ipairs(rows) do
    DEFAULT_CHAT_FRAME:AddMessage("  " .. row.take .. " x " .. row.name)
  end
end


-- What this character could send its alts for their task lists, as rows of alt, id, name, send.
-- It keeps what its own tasks need, each item is only offered once, and what an alt already
-- holds comes off, as far as Altoholic knows.
function M.AltMaterials()
  local account = M.AccountTasks()
  local me = UnitName("player")
  local mine = NetNeeds(M.MyTasks())

  local alts, wanted = {}, {}
  for name, professions in pairs(account) do
    if name ~= me then
      local needs = NetNeeds(professions)
      table.insert(alts, { name = name, needs = needs })
      for id in pairs(needs) do wanted[id] = true end
    end
  end
  table.sort(alts, function(a, b) return a.name < b.name end)

  local found = ReadAltoholic(wanted)
  local spare, rows = {}, {}
  for _, alt in ipairs(alts) do
    local sorted = {}
    for id, row in pairs(alt.needs) do
      table.insert(sorted, { id = id, name = row.name, need = row.need })
    end
    table.sort(sorted, function(a, b) return a.name < b.name end)

    for _, row in ipairs(sorted) do
      if not spare[row.id] then
        spare[row.id] = C_Item.GetItemCount(row.id, true) - (mine[row.id] and mine[row.id].need or 0)
      end
      local held = found[row.id] and found[row.id][alt.name]
      local short = row.need - (held and held.bags + held.bank + held.mail or 0)
      local send = math.min(short, spare[row.id])
      if send > 0 then
        spare[row.id] = spare[row.id] - send
        table.insert(rows, { alt = alt.name, id = row.id, name = row.name, send = send })
      end
    end
  end
  return rows
end

-- At the bank and the mailbox, the places these can be fetched and sent from.
local function AltReminder()
  if not M.Option("altreminder") then return end
  local rows = M.AltMaterials()
  if table.getn(rows) == 0 then return end

  UIErrorsFrame:AddMessage("You have materials for an alt's task list", 1, .8, .2)
  Say("you have materials for your alts' task lists:")
  for _, row in ipairs(rows) do
    DEFAULT_CHAT_FRAME:AddMessage("  " .. row.send .. " x " .. row.name .. " for " .. row.alt)
  end
end

-- [ Crafting ]

-- The client only starts these casts from a click. Called from OnUpdate, DoTradeSkill reaches
-- the client's cast function (nampower_debug.log shows "Attempt cast") but no cast begins and no
-- event says so, however long it has been since the last cast. So a queue can't run by itself:
-- each press of Start casts one batch, and M.Start has to be called from a click.
local CONFIRM_TIME = 3 -- how long the next cast has to show up before the batch counts as over

local function EndBatch()
  M.running, M.confirm = nil, nil
end

-- Casts the first task that has its materials, as many as it can.
function M.Start(ctx)
  local window = M.windows[ctx]
  local profession = window.Profession()
  if not profession or window.Linked() then return end

  local plan = M.Plan(profession)

  for _, task in ipairs(plan.tasks) do
    local count = plan.ready[task]
    if count > 0 then
      -- before the cast: the client can turn it down from inside the call
      if window.batch then
        M.running = { ctx = ctx, profession = profession, task = task, left = count }
        M.confirm = GetTime() + CONFIRM_TIME
        M.driver:Show()
      else
        EndBatch()
      end

      local started = WithRecipe(window, task.name, function(i) window.Cast(i, count) end)
      if started then
        Changed()
        return true
      end
      EndBatch()
      Say("this character doesn't know " .. task.name .. ", skipping it.")
    end
  end

  EndBatch()
  if table.getn(plan.tasks) == 0 then
    Say("the task list is finished.")
  else
    Say("the remaining tasks are waiting for materials.")
  end
  Changed()
end

-- Stops the batch in progress.
function M.Stop()
  local wasCasting = M.running
  EndBatch()
  if wasCasting then SpellStopCasting() end
  Changed()
end

-- By spell ID, which two recipes can't share. By name only if no task has that ID, in case a
-- recipe's cast turns out to be a different spell from the one its link names.
local function FindTask(spell, name)
  local byName, byNameProfession
  for profession, tasks in pairs(M.MyTasks()) do
    for _, task in ipairs(tasks) do
      if task.spell == spell then return profession, task end
      if task.name == name then byName, byNameProfession = task, profession end
    end
  end
  return byNameProfession, byName
end

local function IsRunning(spell, name)
  local running = M.running
  return running and (running.task.spell == spell or running.task.name == name)
end

-- Says what's next once a batch is over, since the next task needs another press.
local function AnnounceNext(profession)
  local plan = M.Plan(profession)
  if table.getn(plan.tasks) == 0 then
    Say("the task list is finished.")
    return
  end
  for _, task in ipairs(plan.tasks) do
    if plan.ready[task] > 0 then
      Say("batch finished. Press Start for " .. task.name .. ".")
      return
    end
  end
  Say("batch finished. The remaining tasks are waiting for materials.")
end

-- [ Events ]

local driver = CreateFrame("Frame")
M.driver = driver
driver:Hide() -- OnUpdate only runs while waiting for a cast to show up

driver:SetScript("OnUpdate", function()
  if M.confirm and GetTime() >= M.confirm then
    -- the cast never began or the batch quietly ended early, so don't sit on Stop
    EndBatch()
    Changed()
  end
  if not M.confirm then driver:Hide() end
end)

-- Any successful cast of a listed recipe counts, so crafting with the window's own Create
-- button also works through the list. Args: unit, castGUID, spellID, spellName.
driver:SetScript("OnEvent", function()
  if event == "UNIT_SPELLCAST_SUCCEEDED" then
    if arg1 ~= "player" then return end
    if IsRunning(arg3, arg4) then M.confirm = nil end

    local profession, task = FindTask(arg3, arg4)
    if not profession then return end

    local running = M.running
    local finished
    if running and running.task == task then
      running.left = running.left - 1
      if running.left <= 0 then
        EndBatch()
        finished = true
      else
        -- the next craft of the batch should follow at once
        M.confirm = GetTime() + CONFIRM_TIME
        driver:Show()
      end
    end

    -- not M.Adjust: that stops the batch when a task is removed, and this one is just done
    task.count = task.count - 1
    if task.count <= 0 then
      local tasks = M.Tasks(profession)
      local i = Position(tasks, task)
      if i then table.remove(tasks, i) end
    end
    if finished then AnnounceNext(profession) end
    Changed()

  elseif event == "UNIT_SPELLCAST_START" then
    if arg1 == "player" and IsRunning(arg3, arg4) then M.confirm = nil end

  elseif event == "UNIT_SPELLCAST_FAILED_QUIET" then
    -- the client was still busy, and says nothing to the player about it
    if arg1 == "player" and M.confirm and IsRunning(arg3, arg4) then
      EndBatch()
      Say("the client was busy, press Start again.")
      Changed()
    end

  elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
    -- the client has told the player why, if it needed to
    if arg1 == "player" and IsRunning(arg3, arg4) then
      EndBatch()
      Changed()
    end

  elseif event == "PLAYER_LOGIN" then
    M.MyTasks() -- moves an old per-character list across, so alts can see it

  elseif event == "BANKFRAME_OPENED" then
    M.recipeInfo = {}
    BankReminder()
    AltReminder()

  elseif event == "MAIL_SHOW" then
    M.recipeInfo = {}
    AltReminder()

  elseif event == "MERCHANT_SHOW" then
    M.pendingBuys = {}
    if M.OptionSet("autobuy") then M.BuyVendorMaterials() else Changed() end

  elseif event == "MERCHANT_CLOSED" then
    M.pendingBuys = {}
    Changed()

  elseif event == "TRADE_SKILL_CLOSE" or event == "CRAFT_CLOSE" then
    -- the batch carries on, but the button that would stop it is gone
    EndBatch()
    Changed()

  else
    Changed()
  end
end)

driver:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
driver:RegisterEvent("UNIT_SPELLCAST_START")
driver:RegisterEvent("UNIT_SPELLCAST_FAILED")
driver:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET")
driver:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
driver:RegisterEvent("BAG_UPDATE_DELAYED")

-- tasks queued from Altoholic are filled in once their profession's window has its rows
local refresher = CreateFrame("Frame")
refresher:RegisterEvent("TRADE_SKILL_SHOW")
refresher:RegisterEvent("TRADE_SKILL_UPDATE")
refresher:RegisterEvent("CRAFT_SHOW")
refresher:RegisterEvent("CRAFT_UPDATE")
refresher:SetScript("OnEvent", function()
  M.recipeInfo = {} -- rows may have moved
  local ok, failure = pcall(M.RefreshTasks, string.find(event, "^CRAFT") and "Craft" or "TradeSkill")
  if not ok then Say("couldn't fill in a queued task: " .. tostring(failure)) end
end)
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("BANKFRAME_OPENED")
driver:RegisterEvent("MAIL_SHOW")
driver:RegisterEvent("TRADE_SKILL_CLOSE")
driver:RegisterEvent("CRAFT_CLOSE")
driver:RegisterEvent("MERCHANT_SHOW")
driver:RegisterEvent("MERCHANT_UPDATE")
driver:RegisterEvent("MERCHANT_CLOSED")
driver:RegisterEvent("PLAYERBANKSLOTS_CHANGED") -- the bank's own slots; its bags give BAG_UPDATE_DELAYED

-- [ Missing recipes ]

-- The recipes of the open window's profession that aren't in it, from recipes.lua (converted
-- from LibCrafts-1.0, the list Gromissingcrafts used). A recipe counts as known when a row of
-- the window has its spell ID or its name, every row included, or, for the player's own
-- window, when ClassicAPI's IsPlayerSpell says so. Spell IDs from PLACEHOLDER up are stand-ins
-- in the list (most of Survival's), so those recipes only match by name.
local PLACEHOLDER = 900000
local gmatch = string.gmatch or string.gfind	-- 5.1's name (ClassicAPI), or 5.0's

-- what the ui translates; core has no pfUI environment, so it sets M.T
local function T(text) return M.T and M.T[text] or text end

-- a recipe's name in the client's language
function M.RecipeName(english)
  if M.RecipeNamesFrom then return M.RecipeNamesFrom[english] end
  return M.RecipeNames and M.RecipeNames[english] or english
end

-- the client writes some of Turtle's names with a curly apostrophe, the list a straight one
function M.RecipeKey(name)
  return (string.gsub(name or "", "\226\128\153", "'"))
end
local function Key(name) return M.RecipeKey(name) end

function M.EnglishProfession(profession)
  for english in pairs(M.RecipeDB or {}) do
    if english == profession or M.RecipeName(english) == profession then return english end
  end
end

local LEARNED = { a = "Learned automatically", q = "Quest", t = "Trainer", o = "World object" }
local RECIPE = { c = "Chest", e = "Made by an engineer", d = "Drop", f = "Fishing", g = "Gift",
  p = "Pickpocketing", q = "Quest", v = "Vendor" }

local function Describe(letters, map)
  local parts = {}
  for letter in gmatch(letters or "", ".") do
    if map[letter] then table.insert(parts, T(map[letter])) end
  end
  return table.concat(parts, ", ")
end

-- "itemID:count|..." as the list keeps them, as { { id, count }, ... }
function M.ParseReagents(s)
  local list = {}
  for id, count in gmatch(s or "", "(%d+):(%d+)") do
    table.insert(list, { tonumber(id), tonumber(count) })
  end
  return list
end

-- { { spell, name, skill, how, item, reagents, recipes = { { id, sources } }, level }, ... }
-- by skill level, how many recipes the profession has, and the rank; nil when the list has
-- nothing for the window's profession
function M.Missing(ctx)
  local window = M.windows[ctx]
  local profession = window and window.Profession()
  local english = profession and M.EnglishProfession(profession)
  if not english then return nil end

  local names, spells = {}, {}
  window.WithFullList(function()
    for i = 1, window.Count() do
      local name, kind = window.Info(i)
      if name and kind ~= "header" then
        names[Key(name)] = true
        local spell = window.Spell(i)
        if spell then spells[spell] = true end
      end
    end
  end)
  -- a linked window is someone else's: IsPlayerSpell answers for the player
  local own = not window.Linked() and IsPlayerSpell

  local missing, all = {}, M.RecipeDB[english]
  for _, craft in ipairs(all) do
    local spell, name = craft[1], M.RecipeName(craft[2])
    local known = spells[spell] or names[Key(name)] or names[Key(craft[2])]
      or (own and spell < PLACEHOLDER and IsPlayerSpell(spell))
    if not known then
      local recipes, how = {}, {}
      local learned = Describe(craft[4], LEARNED)
      if learned ~= "" then table.insert(how, learned) end
      for _, r in ipairs(craft[7] or {}) do
        table.insert(recipes, { id = r[1], sources = Describe(r[2], RECIPE) })
        table.insert(how, Describe(r[2], RECIPE))
      end
      table.insert(missing, { spell = spell, name = name, skill = craft[3], how = table.concat(how, "; "),
        item = craft[5], reagents = craft[6], recipes = recipes, level = craft[8] })
    end
  end
  return missing, table.getn(all), window.Rank()
end

-- [ Where an item comes from, with pfQuest ]
-- Read from pfQuest's database when pfQuest is loaded (pfQuest-octo-plus fills it with
-- OctoWoW's data): who sells the item, which mobs drop it, which objects hold it, and where.

local function DB(kind)
  local t = pfDB and pfDB[kind]
  return t and t.data, t and t.loc
end

function M.HasItemSources()
  return (DB("items")) ~= nil
end

local function Zones(data)
  local _, zoneNames = DB("zones")
  local seen, names = {}, {}
  for _, coord in pairs(data and data.coords or {}) do
    local zone = coord[3]
    if zone and zone > 0 and not seen[zone] then
      seen[zone] = true
      local name = zoneNames and zoneNames[zone]
      if not name and C_Map and C_Map.GetAreaInfo then name = C_Map.GetAreaInfo(zone) end
      if name then table.insert(names, name) end
    end
  end
  table.sort(names)
  if table.getn(names) > 2 then return names[1] .. ", " .. names[2] .. ", ..." end
  return table.concat(names, ", ")
end

-- { vendors, drops, objects }, each a list of { name, zone, value }, or nil
function M.ItemSources(itemID)
  local items = DB("items")
  local item = items and items[itemID]
  if not item then return nil end
  local units, unitNames = DB("units")
  local objects, objectNames = DB("objects")
  local refloot = DB("refloot")
  local out = { vendors = {}, drops = {}, objects = {} }

  local function Unit(list, id, value)
    local name = unitNames and unitNames[id]
    if name then table.insert(list, { name = name, zone = Zones(units and units[id]), value = value }) end
  end
  local function Object(id, chance)
    local name = objectNames and objectNames[id]
    if name then table.insert(out.objects, { name = name, zone = Zones(objects and objects[id]), value = chance }) end
  end

  for id, count in pairs(item.V or {}) do Unit(out.vendors, id, count) end
  for id, chance in pairs(item.U or {}) do Unit(out.drops, id, chance) end
  for id, chance in pairs(item.O or {}) do Object(id, chance) end
  for ref, chance in pairs(item.R or {}) do
    local r = refloot and refloot[ref]
    for id in pairs(r and r.U or {}) do Unit(out.drops, id, chance) end
    for id in pairs(r and r.O or {}) do Object(id, chance) end
  end

  local function ByChance(a, b)
    if (a.value or 0) ~= (b.value or 0) then return (a.value or 0) > (b.value or 0) end
    return a.name < b.name
  end
  table.sort(out.vendors, function(a, b) return a.name < b.name end)
  table.sort(out.drops, ByChance)
  table.sort(out.objects, ByChance)
  if table.getn(out.vendors) + table.getn(out.drops) + table.getn(out.objects) == 0 then return nil end
  return out
end

-- adds at most `max` lines of sources (8 by default) to a tooltip; false when there are none
function M.AddItemSources(tooltip, itemID, max)
  local s = M.ItemSources(itemID)
  if not s then return false end
  max = max or 8
  local shown = 0
  local total = table.getn(s.vendors) + table.getn(s.drops) + table.getn(s.objects)
  local function Line(left, right)
    if shown >= max then return end
    tooltip:AddDoubleLine(left, right, 1, 1, 1, .7, .7, .7)
    shown = shown + 1
  end
  local function Chance(v) return v and v > 0 and string.format(" (%.1f%%)", v) or "" end
  for _, v in ipairs(s.vendors) do Line("|cff33ffcc" .. T("Sold by") .. "|r " .. v.name, v.zone) end
  for _, d in ipairs(s.drops) do Line("|cffffd200" .. T("Dropped by") .. "|r " .. d.name .. Chance(d.value), d.zone) end
  for _, o in ipairs(s.objects) do Line("|cffffd200" .. T("Found in") .. "|r " .. o.name .. Chance(o.value), o.zone) end
  if total > shown then tooltip:AddLine(string.format(T("and %d more"), total - shown), .6, .6, .6) end
  return true
end

-- puts the item's sources on pfQuest's map, as pfQuest's own browser does; false without
-- pfQuest or a known place
function M.ShowItemOnMap(itemID)
  if not (pfDatabase and pfDatabase.SearchItemID and pfMap and pfMap.ShowMapID) then return false end
  if pfMap.DeleteNode then pfMap:DeleteNode("PFDB") end
  local maps = pfDatabase:SearchItemID(itemID, { ["addon"] = "PFDB" })
  local best = maps and pfDatabase:GetBestMap(maps)
  if not best then return false end
  pfMap.queue_update = GetTime()
  pfMap:ShowMapID(best)
  return true
end

-- [ Materials you can make ]
-- Adding a recipe also queues what it needs and this character can make, when there isn't enough
-- in its bags, bank, mail and alts: bars for a blade, bolts for a shirt. The recipe that makes an
-- item is looked for in the open window first, every row included, then in the recipe list for
-- the character's other professions (Smelt Copper on the Mining list for Blacksmithing), where
-- IsPlayerSpell says which it knows. Those are queued like Altoholic's, stale until their window
-- is opened, and assumed to make one each until then.

local makersFrom, makersByItem

-- every recipe in the list that makes an item, as { english profession, craft }
local function ListedMakers(item)
  if makersFrom ~= M.RecipeDB then
    makersFrom, makersByItem = M.RecipeDB, {}
    for english, crafts in pairs(M.RecipeDB or {}) do
      for _, craft in ipairs(crafts) do
        local made = craft[5]
        if made then
          makersByItem[made] = makersByItem[made] or {}
          table.insert(makersByItem[made], { english = english, craft = craft })
        end
      end
    end
  end
  return makersByItem[item] or {}
end

-- the name this character's lists use for a profession, in the client's language
local function ListName(english)
  for profession in pairs(M.MyTasks()) do
    if M.EnglishProfession(profession) == english then return profession end
  end
  return M.RecipeName(english) or english
end

local function Uses(task, item)
  for _, reagent in ipairs(task.reagents or {}) do
    if reagent.id == item then return true end
  end
end

-- Adds crafts of a recipe to a list, above the first task there that uses what it makes.
local function QueueMaker(profession, maker, crafts)
  local tasks = M.Tasks(profession)
  local task
  for _, existing in ipairs(tasks) do
    if existing.name == maker.name then task = existing end
  end
  if task then
    task.count = task.count + crafts
  else
    task = maker
    task.count = crafts
    table.insert(tasks, task)
  end

  local at = Position(tasks, task)
  for i = 1, at - 1 do
    if Uses(tasks[i], task.item) then
      table.remove(tasks, at)
      table.insert(tasks, i, task)
      break
    end
  end
end

-- The window's rows by the item each makes, as row indexes, of the rows it lists now.
local function RowsByItem(window)
  local rows = {}
  if not window.Item then return rows end
  for i = 1, window.Count() do
    local item = window.Item(i)
    local _, kind = window.Info(i)
    if item and kind ~= "header" then
      rows[item] = rows[item] or {}
      table.insert(rows[item], i)
    end
  end
  return rows
end

-- The recipe that makes an item, as a task, and the list it goes on; or nil, and true when
-- several of the character's recipes make it. rows are the window's (RowsByItem). With
-- allRows they are every row it has, so the recipe list isn't asked about its profession.
local function FindMaker(window, profession, rows, item, allRows)
  local own = rows[item]
  if own then
    if table.getn(own) > 1 then return nil, nil, true end
    return window.Read(own[1]), profession
  end

  local english = M.EnglishProfession(profession)
  local known = {}
  if IsPlayerSpell then
    for _, m in ipairs(ListedMakers(item)) do
      local spell = m.craft[1]
      local searched = allRows and m.english == english and window.Item
      if not searched and spell < PLACEHOLDER and IsPlayerSpell(spell) then
        table.insert(known, m)
      end
    end
  end
  if table.getn(known) > 1 then return nil, nil, true end
  local m = known[1]
  if not m then return nil end

  local craft = m.craft
  local maker = {
    name = M.RecipeName(craft[2]) or craft[2], spell = craft[1], item = craft[5], made = 1,
    reagents = {}, stale = true,
  }
  for _, r in ipairs(M.ParseReagents(craft[6])) do
    table.insert(maker.reagents, ReadReagent(r[1], nil, nil, r[2]))
  end
  return maker, ListName(m.english)
end

function M.AddIntermediates(ctx, profession, task)
  local window = M.windows[ctx]
  local queued, order, visited, work, names = {}, {}, {}, {}, {}

  local function Push(t)
    for _, reagent in ipairs(t.reagents or {}) do
      names[reagent.id] = names[reagent.id] or reagent.name
      table.insert(work, reagent.id)
    end
  end

  local rows
  local function Work()
    rows = RowsByItem(window)

    Push(task)
    local steps = 0
    while table.getn(work) > 0 and steps < 50 do
      steps = steps + 1
      local item = table.remove(work, 1)
      if not visited[item] then
        visited[item] = true
        local need = NetNeeds(M.MyTasks())[item]
        local short = need and need.need - M.Have(item) or 0
        if short > 0 then
          local maker, list, several = FindMaker(window, profession, rows, item, true)
          if several then
            Say("several of your recipes make " .. (names[item] or "item:" .. item) .. "; queue the one you want.")
          elseif maker then
            local crafts = math.ceil(short / math.max(maker.made or 1, 1))
            QueueMaker(list, maker, crafts)
            local key = list .. "|" .. maker.name
            if not queued[key] then
              queued[key] = { name = maker.name, profession = list, count = 0 }
              table.insert(order, queued[key])
            end
            queued[key].count = queued[key].count + crafts
            Push(maker)
          end
        end
      end
    end
  end

  if window.Item then window.WithFullList(Work) else Work() end

  if table.getn(order) > 0 then
    local parts = {}
    for _, q in ipairs(order) do
      local where = q.profession ~= profession and " (" .. q.profession .. ")" or ""
      table.insert(parts, q.count .. " x " .. q.name .. where)
    end
    Say("also queued " .. table.concat(parts, ", ") .. " for " .. task.name .. ".")
  end
end

-- [ Recipe tooltips ]
-- What hovering a recipe in the window shows: how many can be made now (the window's own count,
-- from the bags) and with everything (bags, bank, mail and alts, and what the character can
-- make from them), and for each reagent where it is, whether it can be made and whether a vendor
-- sells it. A hover never changes the window's filters: that would redraw the list under the
-- cursor. So only the rows listed now are searched, then the recipe list for every profession.

M.recipeInfo = {}
local MAX_DEPTH = 5
local MOST = 1000

-- { name, kind, now, most, queued, reagents = { { id, name, count, bags, bank, mail, alts,
-- status, makeable, vendor } } }, or nil for a header or someone else's window
function M.RecipeInfo(ctx, index)
  local window = M.windows[ctx]
  if not window or window.Linked() or not index or index < 1 then return nil end
  local key = ctx .. ":" .. index
  local cached = M.recipeInfo[key]
  if cached ~= nil then return cached or nil end

  local profession = window.Profession()
  local name, kind, available = window.Info(index)
  local task = profession and name and kind ~= "header" and window.Read(index)
  if not task then
    M.recipeInfo[key] = false
    return nil
  end

  local rows, makers = RowsByItem(window), {}
  local function Maker(item)
    if makers[item] == nil then
      makers[item] = FindMaker(window, profession, rows, item, false) or false
    end
    return makers[item] or nil
  end

  -- everything that may be needed, to read the holdings once
  local wanted = {}
  local function Gather(t, depth)
    for _, r in ipairs(t.reagents) do
      if not wanted[r.id] then
        wanted[r.id] = true
        local maker = depth < MAX_DEPTH and Maker(r.id)
        if maker then Gather(maker, depth + 1) end
      end
    end
  end
  Gather(task, 0)
  local held, parts = Holdings(wanted)

  -- Whether k crafts can be made: reagents come out of one pool, so two intermediates can't
  -- both use the same ore, and what an intermediate makes beyond what's needed stays in it.
  local function Possible(k)
    local pool = {}
    for id, n in pairs(held) do pool[id] = n end
    local function Take(id, n, depth)
      local got = math.min(pool[id] or 0, n)
      pool[id] = (pool[id] or 0) - got
      local short = n - got
      if short <= 0 then return true end
      local maker = depth < MAX_DEPTH and Maker(id)
      if not maker then return false end
      local made = math.max(maker.made or 1, 1)
      local crafts = math.ceil(short / made)
      for _, r in ipairs(maker.reagents) do
        if not Take(r.id, r.count * crafts, depth + 1) then return false end
      end
      pool[id] = (pool[id] or 0) + crafts * made - short
      return true
    end
    for _, r in ipairs(task.reagents) do
      if not Take(r.id, r.count * k, 0) then return false end
    end
    return true
  end

  local info = { name = name, kind = kind, now = available or 0, reagents = {} }
  if table.getn(task.reagents) > 0 then
    local lo, hi = 0, MOST
    while lo < hi do
      local mid = math.floor((lo + hi + 1) / 2)
      if Possible(mid) then lo = mid else hi = mid - 1 end
    end
    info.most = lo
  end

  for _, t in ipairs(M.Tasks(profession)) do
    if t.name == name then info.queued = t.count end
  end

  local sources = M.HasItemSources()
  for _, r in ipairs(task.reagents) do
    local p = parts[r.id]
    local row = { id = r.id, name = r.name, count = r.count,
      bags = p.bags, bank = p.bank, mail = p.mail, alts = p.alts,
      makeable = Maker(r.id) ~= nil }
    if p.bags >= r.count then
      row.status = "bags"
    elseif p.bags + p.bank >= r.count then
      row.status = "bank"
    elseif held[r.id] >= r.count then
      row.status = "elsewhere"
    else
      row.status = "short"
    end
    if sources then
      local src = M.ItemSources(r.id)
      row.vendor = src and src.vendors and table.getn(src.vendors) > 0 or false
    end
    table.insert(info.reagents, row)
  end

  M.recipeInfo[key] = info
  return info
end

-- [ Buying from vendors ]
-- At a merchant, what the task lists still need beyond what this character can get at (bags,
-- bank, mail and alts) and the merchant sells. Bought items take a moment to reach the bags, so
-- what was bought is remembered until they have, and a second click can't buy it twice.

M.pendingBuys = {}

local function Pending(id)
  local p = M.pendingBuys[id]
  if not p then return 0 end
  local arrived = C_Item.GetItemCount(id, true) - p.before
  local left = p.count - arrived
  if left <= 0 then
    M.pendingBuys[id] = nil
    return 0
  end
  return left
end

function M.Money(copper)
  if GetCoinTextureString then return GetCoinTextureString(copper) end
  local g = math.floor(copper / 10000)
  local s = math.floor(copper / 100) - g * 100
  local c = copper - math.floor(copper / 100) * 100
  if g > 0 then return g .. "g " .. s .. "s " .. c .. "c" end
  if s > 0 then return s .. "s " .. c .. "c" end
  return c .. "c"
end

-- Rows of slot, id, name, stack (items per purchase), buys (purchases), count (items), cost.
-- A row the money doesn't cover is marked poor and buys what it can.
function M.VendorPurchases()
  local rows = {}
  if not (C_MerchantFrame and GetMerchantNumItems) then return rows end
  local needs = NetNeeds(M.MyTasks())
  local wanted = {}
  for id in pairs(needs) do wanted[id] = true end
  if not next(wanted) then return rows end

  local have = Holdings(wanted)
  local money = GetMoney()
  for slot = 1, GetMerchantNumItems() do
    local info = C_MerchantFrame.GetItemInfo(slot)
    local need = info and needs[info.itemID]
    if need and info.price and info.price > 0 then
      local id = info.itemID
      local short = need.need - have[id] - Pending(id)
      if short > 0 then
        local stack = math.max(info.stackCount or 1, 1)
        local buys = math.ceil(short / stack)
        if info.numAvailable and info.numAvailable >= 0 then buys = math.min(buys, info.numAvailable) end
        local row = { slot = slot, id = id, name = need.name, stack = stack }
        local afford = math.floor(money / info.price)
        if afford < buys then
          buys = afford
          row.poor = true
        end
        row.buys, row.count, row.cost = buys, buys * stack, buys * info.price
        money = money - row.cost
        have[id] = have[id] + row.count -- a second slot with the same item buys only the rest
        table.insert(rows, row)
      end
    end
  end
  return rows
end

function M.BuyVendorMaterials()
  local total, any = 0, false
  for _, row in ipairs(M.VendorPurchases()) do
    if row.buys > 0 then
      -- a call buys up to a stack's worth
      local max = C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(row.id)
      local chunk = math.max(1, math.floor((max or 1) / row.stack))
      local left = row.buys
      while left > 0 do
        local n = math.min(chunk, left)
        BuyMerchantItem(row.slot, n)
        left = left - n
      end
      local before = C_Item.GetItemCount(row.id, true)
      local p = M.pendingBuys[row.id]
      if p then
        p.count = p.count + row.count
      else
        M.pendingBuys[row.id] = { count = row.count, before = before }
      end

      if not any then Say("bought for your task list:") end
      any = true
      total = total + row.cost
      DEFAULT_CHAT_FRAME:AddMessage("  " .. row.count .. " x " .. row.name .. " (" .. M.Money(row.cost) .. ")")
    end
    if row.poor then
      Say("not enough money for all the " .. row.name .. " your tasks need.")
    end
  end
  if any then DEFAULT_CHAT_FRAME:AddMessage("  " .. T("Total") .. ": " .. M.Money(total)) end
  Changed()
  return any
end

-- [ Shared with Altoholic ]
-- Altoholic carries the same recipe list, the same pfQuest reading and the same recipe name
-- helpers, and loads first (it is an OptionalDep). With it loaded, its copies run and the ones
-- above are only the fallback, so one copy of each is in use. recipes.lua already takes its
-- list and translations. M.Missing stays this addon's own: it reads the open window, where
-- Altoholic reads saved data.
function M.UseAltoholic()
  local A = Altoholic
  if not (A and A.ItemSources and A.AddItemSources and A.ShowItemOnMap and A.HasItemSources
      and A.EnglishProfession and A.RecipeKey and A.ParseReagents) then
    return false
  end
  M.HasItemSources = function() return A:HasItemSources() end
  M.ItemSources = function(itemID) return A:ItemSources(itemID) end
  M.AddItemSources = function(tooltip, itemID, max) return A:AddItemSources(tooltip, itemID, max) end
  M.ShowItemOnMap = function(itemID) return A:ShowItemOnMap(itemID) end
  M.EnglishProfession = function(profession) return A:EnglishProfession(profession) end
  M.RecipeKey = function(name) return A:RecipeKey(name) end
  M.ParseReagents = function(reagents) return A:ParseReagents(reagents) end
  M.sharedWithAltoholic = true
  return true
end
M.UseAltoholic()
