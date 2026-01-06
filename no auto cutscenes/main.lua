local mod = RegisterMod('No Auto-Cutscenes', 1)
local json = require('json')
local game = Game()

mod.isBeastClear = false
mod.allowNormalClear = false
mod.rngShiftIdx = 35

mod.state = {}
mod.state.applyToChallenges = false
mod.state.blockCutsceneBeast = true
mod.state.blockCutsceneMegaSatan = true
mod.state.probabilityVoidBeast = 50
mod.state.probabilityVoidMegaSatan = 50
if REPENTANCE_PLUS then
  mod.state.blockCutsceneMegaSatan = false
  mod.state.probabilityVoidBeast = 100
  mod.state.probabilityVoidMegaSatan = 100
end

function mod:onGameStart()
  if mod:HasData() then
    local _, state = pcall(json.decode, mod:LoadData())
    
    if type(state) == 'table' then
      for _, v in ipairs({ 'applyToChallenges', 'blockCutsceneBeast', 'blockCutsceneMegaSatan' }) do
        if type(state[v]) == 'boolean' then
          mod.state[v] = state[v]
        end
      end
      for _, v in ipairs({ 'probabilityVoidBeast', 'probabilityVoidMegaSatan' }) do
        if math.type(state[v]) == 'integer' and state[v] >= 0 and state[v] <= 100 then
          mod.state[v] = state[v]
        end
      end
    end
  end
end

function mod:onGameExit(shouldSave)
  mod:save()
  mod.isBeastClear = false
  
  if game:IsGreedMode() or mod:isAnyChallenge() then
    return
  end
  
  -- MC_POST_GAME_END works for mega satan, but not the beast
  -- MC_PRE_GAME_EXIT works for both
  -- going into a chest makes the player invisible unlike restarting
  if not shouldSave and mod:hasInvisibleAlivePlayer() then -- successful ending
    local level = game:GetLevel()
    local room = level:GetCurrentRoom()
    
    if mod:isMegaSatan() then
      if not REPENTOGON then
        mod.allowNormalClear = true
        
        -- this can add +2 to the win streak
        room:TriggerClear(true)
      end
    elseif mod:isLivingRoom() then
      if not REPENTOGON then
        mod.allowNormalClear = true
        
        level.LeaveDoor = DoorSlot.NO_DOOR_SLOT
        game:ChangeRoom(GridRooms.ROOM_SECRET_EXIT_IDX, -1)
        room:TriggerClear(true)
      else
        game:End(Ending.BEAST)
      end
    end
  end
  
  mod.allowNormalClear = false
end

function mod:save()
  mod:SaveData(json.encode(mod.state))
end

function mod:onNewLevel()
  mod.isBeastClear = false
end

function mod:onPreNewRoom(entityType, variant, subType, gridIdx, seed)
  if game:IsGreedMode() or (not mod.state.applyToChallenges and mod:isAnyChallenge()) then
    return
  end
  
  if mod:isLivingRoom() and mod.isBeastClear then
    if entityType == EntityType.ENTITY_DOGMA or (entityType == EntityType.ENTITY_GENERIC_PROP and variant == 4) then -- dogma or tv
      return { EntityType.ENTITY_GENERIC_PROP, 3, 0 } -- couch, stop doors from being removed
    end
  end
end

function mod:onNewRoom()
  if game:IsGreedMode() or (not mod.state.applyToChallenges and mod:isAnyChallenge()) then
    return
  end
  
  local room = game:GetRoom()
  
  if mod:isLivingRoom() and mod.isBeastClear then
    for _, v in ipairs(Isaac.FindByType(EntityType.ENTITY_GENERIC_PROP, -1, -1, false, false)) do
      if v.Variant == 3 or v.Variant == 4 then -- couch/tv
        v:Remove()
      end
    end
  elseif mod:isMegaSatan() and room:IsClear() then
    mod:spawnMegaSatanDoorExit()
  end
end

-- drop chest after MC_POST_NEW_ROOM
function mod:onUpdate()
  if game:IsGreedMode() or (not mod.state.applyToChallenges and mod:isAnyChallenge()) then
    return
  end
  
  local room = game:GetRoom()
  
  if mod:isLivingRoom() and mod.isBeastClear then
    mod.isBeastClear = false
    
    local centerIdx = room:GetGridIndex(room:GetCenterPos())
    mod:spawnChestOrTrophy(room:GetGridPosition(centerIdx - (1 * room:GetGridWidth()))) -- 1 space higher, don't cover dropped rewards
    
    local rng = RNG()
    rng:SetSeed(room:GetSpawnSeed(), mod.rngShiftIdx) -- GetAwardSeed, GetDecorationSeed
    if rng:RandomInt(100) < mod.state.probabilityVoidBeast then
      mod:spawnVoidPortal(room:GetGridPosition(centerIdx + (1 * room:GetGridWidth()))) -- 1 space lower
    end
    
    if not mod:isAnyChallenge() and game:GetVictoryLap() == 0 then
      mod:doRepentogonPostBeastLogic()
    end
  end
end

-- this happens after the previous MC_POST_NPC_DEATH implementation, and should have better support for more variability
function mod:onPreSpawnAward()
  if game:IsGreedMode() or (not mod.state.applyToChallenges and mod:isAnyChallenge()) then
    return
  end
  
  if mod.allowNormalClear then
    return
  end
  
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  
  -- mega satan spawns void portal seed: K703 ACNE (hard)
  if mod:isMegaSatan() then
    mod:spawnMegaSatanDoorExit()
    
    if mod.state.blockCutsceneMegaSatan then
      --[[
      if REPENTOGON and REPENTANCE_PLUS then
        local gameData = Isaac.GetPersistentGameData()
        if gameData:Unlocked(Achievement.THE_VOID) then
          return
        end
      end
      --]]
      
      local centerIdx = room:GetGridIndex(room:GetCenterPos())
      mod:spawnChestOrTrophy(REPENTANCE_PLUS and room:GetCenterPos() or room:GetGridPosition(centerIdx))
      
      local rng = RNG()
      rng:SetSeed(room:GetSpawnSeed(), mod.rngShiftIdx)
      if rng:RandomInt(100) < mod.state.probabilityVoidMegaSatan then
        mod:spawnVoidPortal(room:GetGridPosition(centerIdx + (2 * room:GetGridWidth()))) -- 2 spaces lower
      end
      
      -- alt: MC_PRE_MEGA_SATAN_ENDING
      if not mod:isAnyChallenge() and game:GetVictoryLap() == 0 then
        mod:doRepentogonPostMegaSatanLogic()
      end
      
      return true
    end
  elseif mod:isTheBeast() and mod.state.blockCutsceneBeast then
    mod.isBeastClear = true
    mod:addActiveCharges(1) -- 1 + 1 = 2
    
    local lastBossRoom = level:GetRooms():Get(level:GetLastBossRoomListIndex())
    game:StartRoomTransition(lastBossRoom.SafeGridIndex, Direction.NO_DIRECTION, RoomTransitionAnim.FADE, nil, mod:getDimension(lastBossRoom)) -- go back to the living room, removes the white screen
    
    return true
  end
end

function mod:doRepentogonPostMegaSatanLogic()
  if REPENTOGON then
    local gameData = Isaac.GetPersistentGameData()
    gameData:IncreaseEventCounter(EventCounter.MEGA_SATAN_KILLS, 1)
    game:RecordPlayerCompletion(CompletionType.MEGA_SATAN)
  end
end

function mod:doRepentogonPostBeastLogic()
  if REPENTOGON then
    local gameData = Isaac.GetPersistentGameData()
    gameData:IncreaseEventCounter(EventCounter.BEAST_KILLS, 1)
    game:RecordPlayerCompletion(CompletionType.BEAST)
  end
end

-- usage: no-auto-cutscenes unlock mega satan
-- usage: no-auto-cutscenes unlock the beast
function mod:onExecuteCmd(cmd, parameters)
  if not mod:isInGame() then
    return
  end
  
  local seeds = game:GetSeeds()
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  cmd = string.lower(cmd)
  parameters = string.lower(parameters)
  
  if cmd == 'no-auto-cutscenes' then
    if not game:IsGreedMode() and not seeds:IsCustomRun() and game:GetVictoryLap() == 0 then -- not greed mode, challenge, seeded run, or victory lap
      if parameters == 'unlock mega satan' then
        Isaac.ExecuteCommand('stage 11') -- 11a
        level.LeaveDoor = DoorSlot.NO_DOOR_SLOT
        game:ChangeRoom(GridRooms.ROOM_MEGA_SATAN_IDX, -1)
        mod.allowNormalClear = true
        room:TriggerClear(true) -- may or may not end the game
        game:End(8) -- Ending.MEGA_SATAN
        
        print('Unlocked Mega Satan completion mark')
        return
      elseif parameters == 'unlock the beast' then
        Isaac.ExecuteCommand('stage 13') -- 13a
        level.LeaveDoor = DoorSlot.NO_DOOR_SLOT
        game:ChangeRoom(GridRooms.ROOM_SECRET_EXIT_IDX, -1)
        mod.allowNormalClear = true
        room:TriggerClear(true) -- ends the game unless overridden
        
        print('Unlocked The Beast completion mark')
        return 
      end
      
      print('Usage: unlock mega satan, unlock the beast')
      return
    end
    
    print('Not available in greed mode, challenges, seeded runs, or victory laps')
  end
end

function mod:isInGame()
  if REPENTOGON then
    return Isaac.IsInGame()
  end
  
  return true
end

function mod:spawnChestOrTrophy(pos)
  local chestOrTrophy = mod:isAnyChallenge() and PickupVariant.PICKUP_TROPHY or PickupVariant.PICKUP_BIGCHEST
  Isaac.Spawn(EntityType.ENTITY_PICKUP, chestOrTrophy, 0, pos, Vector.Zero, nil)
end

function mod:spawnVoidPortal(pos)
  local room = game:GetRoom()
  
  local portal = Isaac.GridSpawn(GridEntityType.GRID_TRAPDOOR, 1, pos, true)
  if portal:GetType() ~= GridEntityType.GRID_TRAPDOOR then
    mod:removeGridEntity(room:GetGridIndex(pos), 0, false, true)
    portal = Isaac.GridSpawn(GridEntityType.GRID_TRAPDOOR, 1, pos, true)
  end
  
  portal.VarData = 1
  portal:GetSprite():Load('gfx/grid/voidtrapdoor.anm2', true)
end

function mod:removeGridEntity(gridIdx, pathTrail, keepDecoration, update)
  local room = game:GetRoom()
  
  if REPENTOGON then
    room:RemoveGridEntityImmediate(gridIdx, pathTrail, keepDecoration)
  else
    room:RemoveGridEntity(gridIdx, pathTrail, keepDecoration)
    if update then
      room:Update()
    end
  end
end

function mod:spawnMegaSatanDoorExit()
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  
  -- this goes to DOWN0 because it's the only available door slot
  -- DOWN0 can sometimes be taken in challenges
  if room:GetDoor(DoorSlot.DOWN0) == nil and room:TrySpawnBlueWombDoor(false, true, true) then -- TrySpawnBossRushDoor
    local door = room:GetDoor(DoorSlot.DOWN0)
    if door then
      local sprite = door:GetSprite()
      door.TargetRoomType = RoomType.ROOM_DEFAULT
      door.TargetRoomIndex = level:GetPreviousRoomIndex() -- GetStartingRoomIndex
      sprite:Load('gfx/grid/door_24_megasatandoor.anm2', true)
      sprite:Play('Opened', true)
    end
  end
end

function mod:addActiveCharges(num)
  for i = 0, game:GetNumPlayers() - 1 do
    local player = game:GetPlayer(i)
    
    for _, slot in ipairs({ ActiveSlot.SLOT_PRIMARY, ActiveSlot.SLOT_SECONDARY, ActiveSlot.SLOT_POCKET }) do -- SLOT_POCKET2
      for j = 1, num do
        if player:NeedsCharge(slot) then
          player:SetActiveCharge(player:GetActiveCharge(slot) + player:GetBatteryCharge(slot) + 1, slot)
        end
      end
    end
  end
end

function mod:hasInvisibleAlivePlayer()
  for i = 0, game:GetNumPlayers() - 1 do
    local player = game:GetPlayer(i)
    local isBaby = player:GetBabySkin() ~= BabySubType.BABY_UNASSIGNED
    local isCoopGhost = player:IsCoopGhost()
    local isChild = player.Parent ~= nil
    local isDead = player:IsDead()
    local isVisible = player.Visible
    if not isBaby and not isCoopGhost and not isChild and not isDead and not isVisible then
      return true
    end
  end
  
  return false
end

function mod:getDimension(roomDesc)
  local level = game:GetLevel()
  local ptrHash = GetPtrHash(roomDesc)
  
  -- 0: main dimension
  -- 1: secondary dimension, used by downpour mirror dimension and mines escape sequence
  -- 2: death certificate dimension
  for i = 0, 2 do
    if ptrHash == GetPtrHash(level:GetRoomByIdx(roomDesc.SafeGridIndex, i)) then
      return i
    end
  end
  
  return -1
end

function mod:isMegaSatan()
  local level = game:GetLevel()
  local roomDesc = level:GetCurrentRoomDesc()
  
  return level:GetStage() == LevelStage.STAGE6 and
         roomDesc.Data.Type == RoomType.ROOM_BOSS and
         roomDesc.GridIndex == GridRooms.ROOM_MEGA_SATAN_IDX
end

function mod:isTheBeast()
  local level = game:GetLevel()
  local roomDesc = level:GetCurrentRoomDesc()
  
  return level:GetStage() == LevelStage.STAGE8 and
         roomDesc.Data.Type == RoomType.ROOM_DUNGEON and
         roomDesc.Data.StageID == 35 and  -- home
         roomDesc.Data.Variant == 666 and -- Beast Room, subtype=4
         (roomDesc.GridIndex == GridRooms.ROOM_SECRET_EXIT_IDX or roomDesc.GridIndex == GridRooms.ROOM_DEBUG_IDX)
end

function mod:isLivingRoom()
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  
  return level:GetStage() == LevelStage.STAGE8 and
         room:IsCurrentRoomLastBoss()
end

function mod:isAnyChallenge()
  return Isaac.GetChallenge() ~= Challenge.CHALLENGE_NULL
end

-- start ModConfigMenu --
function mod:setupModConfigMenu()
  for _, v in ipairs({ 'Settings', 'Mom', 'Void' }) do
    ModConfigMenu.RemoveSubcategory(mod.Name, v)
  end
  ModConfigMenu.AddSetting(
    mod.Name,
    'Settings',
    {
      Type = ModConfigMenu.OptionType.BOOLEAN,
      CurrentSetting = function()
        return mod.state.applyToChallenges
      end,
      Display = function()
        return (mod.state.applyToChallenges and 'Apply' or 'Do not apply') .. ' to challenges'
      end,
      OnChange = function(b)
        mod.state.applyToChallenges = b
        mod:save()
      end,
      Info = { 'Should the settings below', 'be applied to challenges?' }
    }
  )
  for _, v in ipairs({
                        { title = 'Mega Satan', block = 'blockCutsceneMegaSatan', probability = 'probabilityVoidMegaSatan' },
                        { title = 'The Beast' , block = 'blockCutsceneBeast'    , probability = 'probabilityVoidBeast' }
                    })
  do
    ModConfigMenu.AddSpace(mod.Name, 'Settings')
    ModConfigMenu.AddTitle(mod.Name, 'Settings', v.title)
    ModConfigMenu.AddSetting(
      mod.Name,
      'Settings',
      {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function()
          return mod.state[v.block]
        end,
        Display = function()
          return (mod.state[v.block] and 'Block' or 'Allow') .. ' cutscene'
        end,
        OnChange = function(b)
          mod.state[v.block] = b
          mod:save()
        end,
        Info = { 'Block or allow the specified cutscene' }
      }
    )
    ModConfigMenu.AddSetting(
      mod.Name,
      'Settings',
      {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function()
          return mod.state[v.probability]
        end,
        Minimum = 0,
        Maximum = 100,
        Display = function()
          return 'Void probability: ' .. mod.state[v.probability] .. '%'
        end,
        OnChange = function(n)
          mod.state[v.probability] = n
          mod:save()
        end,
        Info = { 'Default: ' .. (REPENTANCE_PLUS and '100' or '50') .. '% ', 'Probability that a void portal spawns' }
      }
    )
  end
  ModConfigMenu.AddText(mod.Name, 'Mom', 'There\'s an auto-cutscene after fighting')
  ModConfigMenu.AddText(mod.Name, 'Mom', 'mom the first time. You can bypass this')
  ModConfigMenu.AddText(mod.Name, 'Mom', 'by unlocking the achievement below.')
  ModConfigMenu.AddSpace(mod.Name, 'Mom')
  ModConfigMenu.AddSetting(
    mod.Name,
    'Mom',
    {
      Type = ModConfigMenu.OptionType.BOOLEAN,
      CurrentSetting = function()
        return false
      end,
      Display = function()
        if REPENTOGON then
          local gameData = Isaac.GetPersistentGameData()
          return 'The Womb: ' .. (gameData:Unlocked(Achievement.WOMB) and 'unlocked' or 'locked')
        end
        return 'The Womb: unknown'
      end,
      OnChange = function(b)
        if REPENTOGON then
          local gameData = Isaac.GetPersistentGameData()
          if not gameData:Unlocked(Achievement.WOMB) then
            gameData:TryUnlock(Achievement.WOMB, false)
          end
        end
      end,
      Info = { 'Unlock the achievement', '(requires repentogon)' }
    }
  )
  ModConfigMenu.AddSpace(mod.Name, 'Mom')
  ModConfigMenu.AddText(mod.Name, 'Mom', 'Or... run the following in the')
  ModConfigMenu.AddText(mod.Name, 'Mom', 'debug console: achievement 4')
  ModConfigMenu.AddText(mod.Name, 'Void', 'In rep+, once you\'ve unlocked the void')
  ModConfigMenu.AddText(mod.Name, 'Void', 'then mega satan won\'t have an')
  ModConfigMenu.AddText(mod.Name, 'Void', 'auto-cutscene anymore.')
  ModConfigMenu.AddSpace(mod.Name, 'Void')
  ModConfigMenu.AddSetting(
    mod.Name,
    'Void',
    {
      Type = ModConfigMenu.OptionType.BOOLEAN,
      CurrentSetting = function()
        return false
      end,
      Display = function()
        if REPENTOGON then
          local gameData = Isaac.GetPersistentGameData()
          return 'The Void: ' .. (gameData:Unlocked(Achievement.THE_VOID) and 'unlocked' or 'locked')
        end
        return 'The Void: unknown'
      end,
      OnChange = function(b)
        if REPENTOGON then
          local gameData = Isaac.GetPersistentGameData()
          if not gameData:Unlocked(Achievement.THE_VOID) then
            gameData:TryUnlock(Achievement.THE_VOID, false)
          end
        end
      end,
      Info = { 'Unlock the achievement', '(requires repentogon)' }
    }
  )
  ModConfigMenu.AddSpace(mod.Name, 'Void')
  ModConfigMenu.AddText(mod.Name, 'Void', 'Or... run the following in the')
  ModConfigMenu.AddText(mod.Name, 'Void', 'debug console: achievement 320')
end
-- end ModConfigMenu --

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.onGameStart)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.onGameExit)
mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, mod.onNewLevel)
mod:AddCallback(ModCallbacks.MC_PRE_ROOM_ENTITY_SPAWN, mod.onPreNewRoom)
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.onNewRoom)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.onUpdate)
mod:AddCallback(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD, mod.onPreSpawnAward)
mod:AddCallback(ModCallbacks.MC_EXECUTE_CMD, mod.onExecuteCmd)

if ModConfigMenu then
  mod:setupModConfigMenu()
end

if REPENTOGON then
  function mod:onConsoleAutocomplete(cmd, parameters)
    cmd = string.lower(cmd)
    
    if cmd == 'no-auto-cutscenes' then
      return { 'unlock mega satan', 'unlock the beast' }
    end
  end
  
  function mod:registerCommands()
    Console.RegisterCommand('no-auto-cutscenes', 'Give Mega Satan or The Beast unlocks', 'Give Mega Satan or The Beast unlocks', false, AutocompleteType.CUSTOM)
  end
  
  mod:registerCommands()
  mod:AddCallback(ModCallbacks.MC_CONSOLE_AUTOCOMPLETE, mod.onConsoleAutocomplete)
end