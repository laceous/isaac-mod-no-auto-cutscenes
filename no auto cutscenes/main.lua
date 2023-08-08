local mod = RegisterMod('No Auto-Cutscenes', 1)
local json = require('json')
local game = Game()

mod.isBeastDead = false
mod.livingRoomGridIdx = 109 -- living room @ home
mod.rngShiftIdx = 35

mod.state = {}
mod.state.applyToChallenges = false
mod.state.blockCutsceneBeast = true
mod.state.blockCutsceneMegaSatan = true
mod.state.probabilityVoidBeast = 50
mod.state.probabilityVoidMegaSatan = 50

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
  mod.isBeastDead = false
  
  if game:IsGreedMode() or mod:isAnyChallenge() then
    return
  end
  
  -- MC_POST_GAME_END doesn't work here
  -- going into a chest makes the player invisible unlike restarting
  if not shouldSave and mod:hasInvisibleAlivePlayer() then -- successful ending
    local level = game:GetLevel()
    local roomDesc = level:GetCurrentRoomDesc()
    local stage = level:GetStage()
    
    if stage == LevelStage.STAGE8 and roomDesc.GridIndex == mod.livingRoomGridIdx then
      game:End(14) -- beast ending, gives +1 to win streak unlike Isaac.ExecuteCommand('cutscene 26')
    end
  end
end

function mod:save()
  mod:SaveData(json.encode(mod.state))
end

function mod:onNewLevel()
  mod.isBeastDead = false
end

function mod:onPreNewRoom(entityType, variant, subType, gridIdx, seed)
  if game:IsGreedMode() or (not mod.state.applyToChallenges and mod:isAnyChallenge()) then
    return
  end
  
  local level = game:GetLevel()
  local roomDesc = level:GetCurrentRoomDesc()
  local stage = level:GetStage()
  
  if stage == LevelStage.STAGE8 and roomDesc.GridIndex == mod.livingRoomGridIdx and mod.isBeastDead then
    if entityType == EntityType.ENTITY_DOGMA then
      return { EntityType.ENTITY_GENERIC_PROP, 3, 0 } -- couch, stop doors from being removed
    end
  end
end

function mod:onNewRoom()
  if game:IsGreedMode() or (not mod.state.applyToChallenges and mod:isAnyChallenge()) then
    return
  end
  
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local roomDesc = level:GetCurrentRoomDesc()
  local stage = level:GetStage()
  
  if stage == LevelStage.STAGE8 and roomDesc.GridIndex == mod.livingRoomGridIdx and mod.isBeastDead then
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
  
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local roomDesc = level:GetCurrentRoomDesc()
  local stage = level:GetStage()
  
  if stage == LevelStage.STAGE8 and roomDesc.GridIndex == mod.livingRoomGridIdx and mod.isBeastDead then
    mod.isBeastDead = false
    
    local centerIdx = room:GetGridIndex(room:GetCenterPos())
    mod:spawnChestOrTrophy(room:GetGridPosition(centerIdx - (1 * room:GetGridWidth()))) -- 1 space higher, don't cover dropped rewards
    
    local rng = RNG()
    rng:SetSeed(room:GetSpawnSeed(), mod.rngShiftIdx) -- GetAwardSeed, GetDecorationSeed
    if rng:RandomInt(100) < mod.state.probabilityVoidBeast then
      mod:spawnVoidPortal(room:GetGridPosition(centerIdx + (1 * room:GetGridWidth()))) -- 1 space lower
    end
  end
end

-- this happens after the previous MC_POST_NPC_DEATH implementation, and should have better support for more variability
function mod:onPreSpawnAward()
  if game:IsGreedMode() or (not mod.state.applyToChallenges and mod:isAnyChallenge()) then
    return
  end
  
  -- mega satan spawns void portal seed: K703 ACNE (hard)
  if mod:isMegaSatan() then
    mod:spawnMegaSatanDoorExit()
    
    if mod.state.blockCutsceneMegaSatan then
      mod:addActiveCharges(1)
      
      local room = game:GetRoom()
      local centerIdx = room:GetGridIndex(room:GetCenterPos())
      mod:spawnChestOrTrophy(room:GetGridPosition(centerIdx))
      
      local rng = RNG()
      rng:SetSeed(room:GetSpawnSeed(), mod.rngShiftIdx)
      if rng:RandomInt(100) < mod.state.probabilityVoidMegaSatan then
        mod:spawnVoidPortal(room:GetGridPosition(centerIdx + (2 * room:GetGridWidth()))) -- 2 spaces lower
      end
      
      return true
    end
  elseif mod:isTheBeast() and mod.state.blockCutsceneBeast then
    mod.isBeastDead = true
    mod:addActiveCharges(2)
    game:StartRoomTransition(mod.livingRoomGridIdx, Direction.NO_DIRECTION, RoomTransitionAnim.FADE, nil, -1) -- go back to the living room, removes the white screen
    
    return true
  end
end

function mod:spawnChestOrTrophy(pos)
  local chestOrTrophy = mod:isAnyChallenge() and PickupVariant.PICKUP_TROPHY or PickupVariant.PICKUP_BIGCHEST
  Isaac.Spawn(EntityType.ENTITY_PICKUP, chestOrTrophy, 0, pos, Vector.Zero, nil)
end

function mod:spawnVoidPortal(pos)
  local portal = Isaac.GridSpawn(GridEntityType.GRID_TRAPDOOR, 1, Isaac.GetFreeNearPosition(pos, 3), true)
  portal.VarData = 1
  portal:GetSprite():Load('gfx/grid/voidtrapdoor.anm2', true)
end

function mod:spawnMegaSatanDoorExit()
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  
  -- this goes to DOWN0 because it's the only available door slot
  if room:TrySpawnBlueWombDoor(false, true, true) then -- TrySpawnBossRushDoor
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
         roomDesc.Data.Variant == 666 and
         roomDesc.Data.Name == 'Beast Room' and
         (roomDesc.GridIndex == GridRooms.ROOM_SECRET_EXIT_IDX or roomDesc.GridIndex == GridRooms.ROOM_DEBUG_IDX)
end

function mod:isAnyChallenge()
  return Isaac.GetChallenge() ~= Challenge.CHALLENGE_NULL
end

-- start ModConfigMenu --
function mod:setupModConfigMenu()
  for _, v in ipairs({ 'Settings' }) do
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
        Info = { 'Default: 50%', 'Probability that a void portal spawns' }
      }
    )
  end
end
-- end ModConfigMenu --

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.onGameStart)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.onGameExit)
mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, mod.onNewLevel)
mod:AddCallback(ModCallbacks.MC_PRE_ROOM_ENTITY_SPAWN, mod.onPreNewRoom)
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.onNewRoom)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.onUpdate)
mod:AddCallback(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD, mod.onPreSpawnAward)

if ModConfigMenu then
  mod:setupModConfigMenu()
end