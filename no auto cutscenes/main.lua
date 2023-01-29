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
mod.state.spawnFoolCardMegaSatan = false

function mod:onGameStart()
  if mod:HasData() then
    local _, state = pcall(json.decode, mod:LoadData())
    
    if type(state) == 'table' then
      if type(state.applyToChallenges) == 'boolean' then
        mod.state.applyToChallenges = state.applyToChallenges
      end
      if type(state.blockCutsceneBeast) == 'boolean' then
        mod.state.blockCutsceneBeast = state.blockCutsceneBeast
      end
      if type(state.blockCutsceneMegaSatan) == 'boolean' then
        mod.state.blockCutsceneMegaSatan = state.blockCutsceneMegaSatan
      end
      if math.type(state.probabilityVoidBeast) == 'integer' and state.probabilityVoidBeast >= 0 and state.probabilityVoidBeast <= 100 then
        mod.state.probabilityVoidBeast = state.probabilityVoidBeast
      end
      if math.type(state.probabilityVoidMegaSatan) == 'integer' and state.probabilityVoidMegaSatan >= 0 and state.probabilityVoidMegaSatan <= 100 then
        mod.state.probabilityVoidMegaSatan = state.probabilityVoidMegaSatan
      end
      if type(state.spawnFoolCardMegaSatan) == 'boolean' then
        mod.state.spawnFoolCardMegaSatan = state.spawnFoolCardMegaSatan
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
  if not shouldSave and mod:hasAlivePlayer() then -- successful ending
    local level = game:GetLevel()
    local roomDesc = level:GetCurrentRoomDesc()
    local stage = level:GetStage()
    
    if stage == LevelStage.STAGE8 and roomDesc.GridIndex == mod.livingRoomGridIdx then
      Isaac.ExecuteCommand('cutscene 26') -- beast ending
    end
  end
end

function mod:save()
  mod:SaveData(json.encode(mod.state))
end

function mod:onNewLevel()
  mod.isBeastDead = false
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
    mod:spawnChestOrTrophy(room:GetGridPosition(centerIdx - 15)) -- 1 space higher, don't cover dropped rewards
    
    local rng = RNG()
    rng:SetSeed(room:GetSpawnSeed(), mod.rngShiftIdx) -- GetAwardSeed, GetDecorationSeed
    if rng:RandomInt(100) < mod.state.probabilityVoidBeast then
      mod:spawnVoidPortal(room:GetGridPosition(centerIdx + 15)) -- 1 space lower
    end
  end
end

-- filtered to ENTITY_MEGA_SATAN_2 and ENTITY_BEAST
function mod:onNpcDeath(entityNpc)
  if game:IsGreedMode() or (not mod.state.applyToChallenges and mod:isAnyChallenge()) then
    return
  end
  
  -- mega satan spawns void portal seed: K703 ACNE (hard)
  if mod.state.blockCutsceneMegaSatan and entityNpc.Type == EntityType.ENTITY_MEGA_SATAN_2 and mod:isMegaSatan() then
    local room = game:GetRoom()
    room:SetClear(true) -- this stops the cutscene from triggering, it also stops the game from spawning its own chest+void portal
    mod:addActiveCharges(1)
    
    local centerIdx = room:GetGridIndex(room:GetCenterPos())
    mod:spawnChestOrTrophy(room:GetGridPosition(centerIdx))
    
    local rng = RNG()
    rng:SetSeed(room:GetSpawnSeed(), mod.rngShiftIdx)
    if rng:RandomInt(100) < mod.state.probabilityVoidMegaSatan then
      mod:spawnVoidPortal(room:GetGridPosition(centerIdx + (2 * 15))) -- 2 spaces lower
    end
    
    if mod.state.spawnFoolCardMegaSatan then
      Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, Card.CARD_FOOL, Isaac.GetFreeNearPosition(Isaac.GetRandomPosition(), 3), Vector.Zero, nil)
    end
  elseif mod.state.blockCutsceneBeast and entityNpc.Type == EntityType.ENTITY_BEAST and entityNpc.Variant == 0 and entityNpc.SubType == 0 and mod:isTheBeast() then -- 951.0.0 is the beast, filter out other 951.x.x
    -- room:SetClear from here leaves the screen completely white, you also can't remove the beast w/o triggering the cutscene
    mod.isBeastDead = true
    mod:addActiveCharges(2)
    game:StartRoomTransition(mod.livingRoomGridIdx, Direction.NO_DIRECTION, RoomTransitionAnim.FADE, nil, -1) -- go back to the living room, removes the white screen
  end
end

function mod:spawnChestOrTrophy(pos)
  local chestOrTrophy = mod:isAnyChallenge() and PickupVariant.PICKUP_TROPHY or PickupVariant.PICKUP_BIGCHEST
  Isaac.Spawn(EntityType.ENTITY_PICKUP, chestOrTrophy, 0, pos, Vector.Zero, nil)
end

function mod:spawnVoidPortal(pos)
  local portal = Isaac.GridSpawn(GridEntityType.GRID_TRAPDOOR, 1, pos, true)
  portal.VarData = 1
  portal:GetSprite():Load('gfx/grid/voidtrapdoor.anm2', true)
end

function mod:addActiveCharges(num)
  for i = 0, game:GetNumPlayers() - 1 do
    local player = game:GetPlayer(i)
    
    for _, slot in ipairs({ ActiveSlot.SLOT_PRIMARY, ActiveSlot.SLOT_SECONDARY, ActiveSlot.SLOT_POCKET }) do -- SLOT_POCKET2
      for j = num, 1, -1 do
        if player:NeedsCharge(slot) then
          player:SetActiveCharge(player:GetActiveCharge(slot) + player:GetBatteryCharge(slot) + 1, slot)
        end
      end
    end
  end
end

function mod:hasAlivePlayer()
  for i = 0, game:GetNumPlayers() - 1 do
    local player = game:GetPlayer(i)
    local isBaby = player:GetBabySkin() ~= BabySubType.BABY_UNASSIGNED
    local isCoopGhost = player:IsCoopGhost()
    local isChild = player.Parent ~= nil
    local isDead = player:IsDead()
    if not isBaby and not isCoopGhost and not isChild and not isDead then
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
         roomDesc.GridIndex == GridRooms.ROOM_SECRET_EXIT_IDX
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
                        { title = 'Mega Satan', block = 'blockCutsceneMegaSatan', fool = 'spawnFoolCardMegaSatan', probability = 'probabilityVoidMegaSatan' },
                        { title = 'The Beast' , block = 'blockCutsceneBeast'    , fool = nil                     , probability = 'probabilityVoidBeast' }
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
    if v.fool then
      ModConfigMenu.AddSetting(
        mod.Name,
        'Settings',
        {
          Type = ModConfigMenu.OptionType.BOOLEAN,
          CurrentSetting = function()
            return mod.state[v.fool]
          end,
          Display = function()
            return (mod.state[v.fool] and 'Spawn' or 'Do not spawn') .. ' fool card'
          end,
          OnChange = function(b)
            mod.state[v.fool] = b
            mod:save()
          end,
          Info = { 'Do you want to spawn 0 - The Fool', 'after defeating Mega Satan?' }
        }
      )
    end
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
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.onUpdate)
mod:AddCallback(ModCallbacks.MC_POST_NPC_DEATH, mod.onNpcDeath, EntityType.ENTITY_MEGA_SATAN_2)
mod:AddCallback(ModCallbacks.MC_POST_NPC_DEATH, mod.onNpcDeath, EntityType.ENTITY_BEAST)

if ModConfigMenu then
  mod:setupModConfigMenu()
end