-- A made-up Eve for the fake game (fake.lua): her pawn, mesh, movement, HP bar and death screen, and the game's side
-- of a fall, a death and a camp rest as a scenario drives them. Only what the scripts read is made up.
local E = {}

local function vec(x, y, z) return { X = x, Y = y, Z = z } end

function E.make(F)
  local s = {
    z = 0,               -- her feet's height (cm)
    falling = false,
    mode = 1,            -- movement mode: 1 walking, 3 falling, 4 swimming, 0 none (sitting at a camp)
    sim = false,         -- her bodies simulating (the pelvis)
    simBelow = {},       -- bodies below a bone simulating (a part cut off her)
    hp = 1.0,            -- the HUD's HP bar
    dead = false,
  }
  E.s = s
  local function loc() return vec(1000, 2000, s.z) end
  -- her skeleton standing (cm over her feet, facing +X): the bones the scripts read by name, the rest on her pelvis
  local B = {
    { "Bip001", nil, 0, 0, 95 }, { "Bip001-Pelvis", "Bip001", 0, 0, 95 }, { "Bip001-Spine", "Bip001-Pelvis", 0, 0, 105 },
    { "Bip001-Spine1", "Bip001-Spine", 0, 0, 118 }, { "Bip001-Spine2", "Bip001-Spine1", 0, 0, 130 },
    { "Bip001-Neck", "Bip001-Spine2", 0, 0, 145 }, { "Bip001-Head", "Bip001-Neck", 0, 0, 155 }, { "Bip001-HeadNub", "Bip001-Head", 0, 0, 172 },
    { "Bip001-R-Clavicle", "Bip001-Neck", 0, -5, 142 }, { "Bip001-R-UpperArm", "Bip001-R-Clavicle", 0, -17, 140 },
    { "Bip001-R-Forearm", "Bip001-R-UpperArm", 0, -20, 112 }, { "Bip001-R-Hand", "Bip001-R-Forearm", 0, -21, 88 },
    { "Bip001-L-Clavicle", "Bip001-Neck", 0, 5, 142 }, { "Bip001-L-UpperArm", "Bip001-L-Clavicle", 0, 17, 140 },
    { "Bip001-L-Forearm", "Bip001-L-UpperArm", 0, 20, 112 }, { "Bip001-L-Hand", "Bip001-L-Forearm", 0, 21, 88 },
    { "Bip001-R-Thigh", "Bip001-Pelvis", 0, -9, 90 }, { "Bip001-R-Calf", "Bip001-R-Thigh", 0, -9, 50 }, { "Bip001-R-Foot", "Bip001-R-Calf", 0, -9, 8 },
    { "Bip001-L-Thigh", "Bip001-Pelvis", 0, 9, 90 }, { "Bip001-L-Calf", "Bip001-L-Thigh", 0, 9, 50 }, { "Bip001-L-Foot", "Bip001-L-Calf", 0, 9, 8 },
    -- (the middle fingers' roots: the hands' length, no body of their own)
    { "Bip001-R-Finger2", "Bip001-R-Hand", 0, -21, 80 }, { "Bip001-L-Finger2", "Bip001-L-Hand", 0, 21, 80 },
  }
  E.INDEX, E.BONE_OF, E.PARENT, E.POS = {}, {}, {}, {}
  for i, b in ipairs(B) do
    E.INDEX[b[1]], E.BONE_OF[i - 1], E.PARENT[b[1]], E.POS[b[1]] = i - 1, b[1], b[2], { b[3], b[4], b[5] }
  end
  function E.bone(n)
    local p = E.POS[n] or E.POS["Bip001-Pelvis"]
    local l = loc()
    return vec(l.X + p[1], l.Y + p[2], l.Z + p[3])
  end

  local movement = F.obj("CharMoveComp", "SBCharacterMovementComponent", {
    IsFalling = function() return s.falling end,
    -- (the player's input: s.input cm/s2 along X)
    GetCurrentAcceleration = function() return vec(s.input or 0, 0, 0) end,
  })
  -- (the properties the scripts read: answered live)
  local mvt = setmetatable({}, {
    __index = function(_, k)
      if k == "MovementMode" then return s.mode end
      if k == "Velocity" then return vec(0, 0, s.falling and -1500 or 0) end
      return movement[k]
    end,
  })

  local mesh
  mesh = F.obj("CharacterMesh0", "SkeletalMeshComponent", {
    IsSimulatingPhysics = function(_, b)
      local n = b and b:ToString() or "Bip001-Pelvis"
      if s.simBelow[n] then return true end
      return s.sim
    end,
    SetSimulatePhysics = function(_, on) s.sim = on and true or false end,
    SetAllBodiesSimulatePhysics = function(_, on) s.sim = on and true or false end,
    SetAllBodiesBelowSimulatePhysics = function(_, b, on)
      local n = b:ToString()
      if n == "Bip001" or n == "Bip001-Pelvis" then s.sim = on and true or false else s.simBelow[n] = on or nil end
    end,
    GetSocketLocation = function(_, b) return E.bone(b and b:ToString() or "") end,
    GetBoneLocation = function(_, b) return E.bone(b and b:ToString() or "") end,
    GetSocketTransform = function(_, b) return { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = E.bone(b and b:ToString() or "") } end,
    GetBoneName = function(_, i) return F.fname(E.BONE_OF[i] or "None") end,
    GetParentBone = function(_, b) return F.fname(E.PARENT[b:ToString()] or "None") end,
    GetNumBones = function() return #E.BONE_OF + 1 end,
    K2_GetComponentLocation = function() return loc() end,
    GetComponentVelocity = function() return vec(0, 0, 0) end,
    GetPhysicsLinearVelocity = function() return vec(0, 0, 0) end,
    GetBoneIndex = function(_, b) return E.INDEX[b:ToString()] or -1 end,
    GetNumMaterials = function() return 4 end,
    IsVisible = function() return true end,
    GetCollisionProfileName = function() return F.fname("CharacterMesh") end,
    GetCollisionObjectType = function() return 2 end,
    GetCollisionEnabled = function() return E.coll or 3 end,
    -- (the ponytail reset's query only: it stops a part cut off her simulating on her mesh)
    SetCollisionEnabled = function(_, v) E.coll = v; E.collLog = E.collLog or {}; E.collLog[#E.collLog + 1] = v end,
    GetCollisionResponseToChannel = function() return 2 end,
    -- (bones hidden on her: gore.hide_pieces)
    HideBoneByName = function(_, b) E.hiddenBones[b:ToString()] = true end,
    UnHideBoneByName = function(_, b) E.hiddenBones[b:ToString()] = nil end,
  })
  E.hiddenBones = {}
  local capsule = F.obj("CollisionCylinder", "CapsuleComponent", {
    K2_GetComponentLocation = function() local l = loc(); l.Z = l.Z + 90; return l end,
  })
  -- (her mesh rides her capsule, as the game attaches it)
  rawset(mesh, "GetAttachParent", function() return capsule end)
  local controller = F.obj("SBNetworkPlayerController_0", "SBNetworkPlayerController")
  local pawn = F.obj("CH_P_EVE_01_Blueprint_C_0", "CH_P_EVE_01_Blueprint_C", {
    Mesh = mesh, CapsuleComponent = capsule, Controller = controller,
    BroadcastSpawnInfo = { ActorGuid = 4242 },
    bActorIsBeingDestroyed = false, CustomTimeDilation = 1.0,
    GetGameTimeSinceCreation = function() return 100 end,
    K2_GetActorLocation = function() local l = loc(); l.Z = l.Z + 90; return l end,
    K2_GetActorRotation = function() return { Pitch = 0, Yaw = 30, Roll = 0 } end,
    GetActorForwardVector = function() return vec(1, 0, 0) end,
  })
  rawset(pawn, "CharacterMovement", mvt)
  -- components added to her (the regrow's copy of her mesh: gore.clone_of), each one's life and materials kept
  E.added = {}
  F.objects["/Script/Engine.SkeletalMeshComponent"] = F.obj("SkeletalMeshComponent", "Class")
  F.objects["/Game/Art/FX/Char/Monster/Common/Dead/MI_DeadMaterial_LurkerA_01.MI_DeadMaterial_LurkerA_01"] =
    F.obj("MI_DeadMaterial_LurkerA_01", "MaterialInstanceConstant")
  rawset(pawn, "AddComponentByClass", function(_, cls)
    local n = #E.added + 1
    local c
    c = F.obj("SkeletalMeshComponent_" .. n, "SkeletalMeshComponent", {
      hidden = true, mids = {},
      SetHiddenInGame = function(self, h) self.hidden = h; F.event(self.__name .. (h and " hidden" or " shown")) end,
      K2_DestroyComponent = function(self) self.__dead = true; F.event(self.__name .. " destroyed") end,
      GetNumMaterials = function() return 4 end,
      GetBoneIndex = function(_, b) return E.INDEX[b:ToString()] or -1 end,
      CreateDynamicMaterialInstance = function(self, i)
        local p = {}
        local mid = F.obj("MID_" .. n .. "_" .. i, "MaterialInstanceDynamic", {
          SetScalarParameterValue = function(_, k, v) p[k:ToString()] = v end,
        })
        mid.p = p
        self.mids[#self.mids + 1] = mid
        return mid
      end,
    })
    E.added[n] = c
    F.event(c.__name .. " added")
    return c
  end)

  -- her HUD: the HP bar (glass.bar_pct) and the death screen (main.lua's dead_hud), made at her death
  local bar = F.obj("ProgressBar_HP", "ProgressBar")
  local barmt = { __index = function(_, k) if k == "Percent" then return s.hp end return bar[k] end }
  local hud = F.obj("WB_MainHUD_PlayerInfo_C_0", "WB_MainHUD_PlayerInfo_C")
  rawset(hud, "ProgressBar_HP", setmetatable({}, barmt))
  F.classes.WB_MainHUD_PlayerInfo_C = { hud }
  E.pawn, E.mesh, E.hud = pawn, mesh, hud

  local function widget(name, cls)
    local w = { vis = 4 }   -- 4 SelfHitTestInvisible; 1 collapsed, 2 hidden
    local o
    -- (its animations: the intro, playing while w.intro)
    local intro = F.obj("YouDie", "WidgetAnimation")
    local wcls = F.obj(cls, "Class", { Animations = { ForEach = function(_, fn) fn(1, { get = function() return intro end }) end } })
    o = F.obj(name, cls, {
      GetClass = function() return wcls end,
      IsAnimationPlaying = function(_, a) return w.intro == true and a == intro end,
      GetVisibility = function() return w.vis end,
      SetVisibility = function(_, v) w.vis = v; w.log = (w.log or "") .. tostring(v) end,
      IsVisible = function() return w.vis ~= 1 and w.vis ~= 2 end,
      GetRenderOpacity = function() return 1 end,
      GetWidgetFromName = function() return nil end,
    })
    o.__w = w
    return o
  end
  F.objects["/Game/Art/UI/Widget/HUD/WB_MainHUD_Dead.WB_MainHUD_Dead_C"] = F.obj("WB_MainHUD_Dead_C", "Class")
  F.objects["/Script/SB.Default__SBBlueprintLibrary"] = F.obj("Default__SBBlueprintLibrary", "SBBlueprintLibrary", {
    PlaySBShowToPlayerCharacter = function(_, show) E.shows[#E.shows + 1] = show:GetFName():ToString() end,
  })
  E.shows = {}
  F.TICK_FN = "/Game/Art/Character/PC/CH_P_EVE_01/Blueprints/CH_P_EVE_01_Blueprint.CH_P_EVE_01_Blueprint_C:ReceiveTick"
  F.objects[F.TICK_FN] = F.obj("ReceiveTick", "Function")

  -- the game's side of things
  -- a drop of h cm over t s, then the landing: the fall damage (the HP bar to hp), at 0 her death show (ragdoll: its
  -- key turns her bodies on, as P_Eve_Dead_Falling's should; false: none, as the playtests saw) and her death screen
  function E.fall(h, t, hp, ragdoll)
    local z0 = s.z
    s.falling, s.mode = true, 3
    local n = math.floor(t * 60)
    for i = 1, n do s.z = z0 - h * (i / n) ^ 2; F.step(1 / 60, pawn) end
    s.falling, s.mode = false, 1
    s.hp = hp
    F.step(1 / 60, pawn)
    if hp > 0 then return end
    E.die(ragdoll)
  end
  -- (her movement stays on, walking: the game's falling death left it so, playtest)
  function E.die(ragdoll, effect)
    s.dead = true
    if ragdoll then s.sim = true end
    -- the death screen, made and put up at once (the death table's UI delay 0), its intro playing
    local w = widget("WB_MainHUD_Dead_C_0", "WB_MainHUD_Dead_C")
    w.__w.intro = true
    E.deadScreen = w
    F.classes.WB_MainHUD_Dead_C = { w }
    F.new_object(w, "/Script/UMG.UserWidget")
    F.fire("/Script/SB.SBNetworkPlayerController:ClientBroadcast_ActorDead", F.param(controller), F.param(1), F.param(4242),
      F.param(0), F.param(effect or 8000005), F.param(0), F.param(0), F.param(false), F.param(false))
  end
  -- the death screen's widget made with the level, as the game does: it reads visible all along, alive or not
  function E.dead_widget()
    local w = widget("WB_MainHUD_Dead_C_0", "WB_MainHUD_Dead_C")
    E.deadScreen = w
    F.classes.WB_MainHUD_Dead_C = { w }
    F.new_object(w, "/Script/UMG.UserWidget")
  end
  -- the game's respawn after a death (its death screen's Retry): her actor re-made in place (NotifyBP_ReInitActor),
  -- whole and standing, the death screen gone
  function E.respawn()
    s.dead, s.sim, s.simBelow, s.hp, s.z, s.falling, s.mode, s.input = false, false, {}, 1.0, 0, false, 1, nil
    if E.deadScreen then E.deadScreen.__w.vis = 1; E.deadScreen.__dead = true end
    F.classes.WB_MainHUD_Dead_C = nil
    E.deadScreen = nil
    F.fire("/Game/Art/Character/PC/CH_P_EVE_01/Blueprints/CH_P_EVE_01_Blueprint.CH_P_EVE_01_Blueprint_C:NotifyBP_ReInitActor", F.param(pawn))
  end
  return pawn
end

return E
