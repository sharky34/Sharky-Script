--[[
    core.lua — ESP Core Module
    Handles: Config, entity tracking, rig registry, team checks, cache management.
    No Drawing dependencies whatsoever. All rendering is handled by renderer.lua.
]]

local Players     = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local Core = {}

------------------------------------------------------------------------
-- CONFIG
------------------------------------------------------------------------
Core.Config = {
    Enabled     = true,
    TeamCheck   = true,
    MaxDistance = 2000,

    Components = {
        Box      = true,
        Name     = true,
        Health   = true,
        Skeleton = true,
    },

    Health = {
        Lerp      = true,
        LerpSpeed = 0.1,
        ShowText  = true,
    },

    Visibility = {
        Enabled       = true,
        VisibleColor  = Color3.fromRGB(255, 255, 255),
        OccludedColor = Color3.fromRGB(120, 120, 120),
    },

    Style = {
        TextSize          = 13,
        BoxThickness      = 1,
        SkeletonThickness = 1,
        Outline           = true,
        ScaleWithDistance = true,
    },

    NPC = {
        Enabled   = true,
        TeamCheck = true,
    },

    --[[
        Throttle controls how often (in frames) each ESP entry is updated.
        GetDistanceRate() selects the bucket by distance:
          - dist <= Near.Distance  →  every Near.Rate frames  (most frequent)
          - dist <= Mid.Distance   →  every Mid.Rate  frames
          - dist >  Mid.Distance   →  every Far.Rate  frames  (least frequent)
        Rate 1 = every frame. Rate 6 = every 6th frame.
        Each entity gets a random _frame offset (0–5) so updates stagger
        across entities rather than all firing on the same frame.
    --]]
    Throttle = {
        Near = { Distance = 100,       Rate = 1 },
        Mid  = { Distance = 500,       Rate = 3 },
        Far  = { Distance = math.huge, Rate = 6 },
    },

    SkeletonMaxDistance = 300,
    CustomRigs          = {},
}

------------------------------------------------------------------------
-- STATE
------------------------------------------------------------------------
Core.Cache       = {}   -- [entity] = esp state table
Core.Connections = {}   -- named RBXScriptConnections, disconnected on Shutdown
Core.RigRegistry = {}

------------------------------------------------------------------------
-- RENDERER CALLBACKS
-- Renderer:Init() sets these so Core can notify Renderer when entities
-- are added, removed, or need hiding — without Core knowing about Drawing.
------------------------------------------------------------------------
Core.OnEntityAdded   = nil  -- function(entity, esp)  → Renderer attaches Drawing objects
Core.OnEntityRemoved = nil  -- function(entity, esp)  → Renderer destroys Drawing objects
Core.OnHideAll       = nil  -- function(esp)          → Renderer hides all Drawing objects

------------------------------------------------------------------------
-- RIG REGISTRY
------------------------------------------------------------------------
local function RegisterRig(entry)
    for i, existing in ipairs(Core.RigRegistry) do
        if existing.name == entry.name then Core.RigRegistry[i] = entry; return end
    end
    table.insert(Core.RigRegistry, entry)
end
Core.RegisterRig = RegisterRig

local function RebuildCustomRigDetect(data)
    local parts = data.detectParts
    return function(char)
        for _, pName in ipairs(parts) do
            if not char:FindFirstChild(pName) then return false end
        end
        return #parts > 0
    end
end

local function RegisterCustomRig(data)
    Core.Config.CustomRigs[#Core.Config.CustomRigs + 1] = data
    RegisterRig({
        name    = data.name,
        builtin = false,
        detect  = RebuildCustomRigDetect(data),
        bones   = data.bones,
    })
end
Core.RegisterCustomRig = RegisterCustomRig

local function InvalidateAllSkeletonCaches()
    for _, esp in pairs(Core.Cache) do
        if esp.Skeleton then
            esp.Skeleton._joints = nil
            esp.Skeleton._rig    = nil
        end
    end
end
Core.InvalidateAllSkeletonCaches = InvalidateAllSkeletonCaches

local function UnregisterCustomRig(rigName)
    for i = #Core.RigRegistry, 1, -1 do
        if Core.RigRegistry[i].name == rigName and not Core.RigRegistry[i].builtin then
            table.remove(Core.RigRegistry, i)
        end
    end
    for i = #Core.Config.CustomRigs, 1, -1 do
        if Core.Config.CustomRigs[i].name == rigName then
            table.remove(Core.Config.CustomRigs, i)
        end
    end
    InvalidateAllSkeletonCaches()
end
Core.UnregisterCustomRig = UnregisterCustomRig

local function GetRig(character)
    for _, entry in ipairs(Core.RigRegistry) do
        if entry.detect(character) then return entry.name end
    end
    return "AUTO"
end
Core.GetRig = GetRig

local function AutoDetectBones(character)
    local out, seen = {}, {}
    for _, desc in ipairs(character:GetDescendants()) do
        if (desc:IsA("Motor6D") or desc:IsA("Weld"))
        and desc.Part0 and desc.Part1
        and desc.Part0:IsA("BasePart") and desc.Part1:IsA("BasePart") then
            local key = desc.Part0.Name .. "|" .. desc.Part1.Name
            if not seen[key] then
                seen[key] = true
                out[#out + 1] = { desc.Part0, desc.Part1 }
            end
        end
    end
    return out
end
Core.AutoDetectBones = AutoDetectBones

-- Built-in rigs registered immediately so they are always first in the registry.
RegisterRig({
    name    = "R15",
    builtin = true,
    detect  = function(char) return char:FindFirstChild("UpperTorso") ~= nil end,
    bones   = {
        {"Head","UpperTorso"},{"UpperTorso","LowerTorso"},{"LowerTorso","HumanoidRootPart"},
        {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
        {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
        {"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
        {"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
    },
})

RegisterRig({
    name    = "R6",
    builtin = true,
    detect  = function(char) return char:FindFirstChild("Torso") ~= nil end,
    bones   = {
        {"Head","Torso"},{"Torso","Left Arm"},{"Torso","Right Arm"},
        {"Torso","Left Leg"},{"Torso","Right Leg"},{"HumanoidRootPart","Torso"},
    },
})

------------------------------------------------------------------------
-- ESP PART HELPERS
------------------------------------------------------------------------
local function RefreshESPParts(esp, char)
    if not esp or not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        esp.Head     = hum.Parent:FindFirstChild("Head", true)
        esp.RootPart = hum.RootPart
        esp.Humanoid = hum
    else
        esp.Head, esp.RootPart, esp.Humanoid = nil, nil, nil
    end
end
Core.RefreshESPParts = RefreshESPParts

local function ClearESPParts(esp)
    if not esp then return end
    esp.Head, esp.RootPart, esp.Humanoid = nil, nil, nil
end
Core.ClearESPParts = ClearESPParts

local function IsAlive(esp)
    local hum = esp and esp.Humanoid
    return hum and hum.Health > 0
end
Core.IsAlive = IsAlive

local function EnsureESPParts(esp, char)
    if not esp.Head or not esp.RootPart or not esp.Humanoid then
        RefreshESPParts(esp, char)
    end
end
Core.EnsureESPParts = EnsureESPParts

local function BuildRaycastParams()
    local p = RaycastParams.new()
    p.FilterType = Enum.RaycastFilterType.Exclude
    return p
end

------------------------------------------------------------------------
-- ENTITY HELPERS
------------------------------------------------------------------------
local function IsPlayerCharacter(model)
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character == model then return true end
    end
    return false
end
Core.IsPlayerCharacter = IsPlayerCharacter

local function IsNPCModel(model)
    if not model or not model:IsA("Model") then return false end
    if IsPlayerCharacter(model) then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    local root = hum.RootPart or model:FindFirstChild("HumanoidRootPart", true)
    return root ~= nil
end
Core.IsNPCModel = IsNPCModel

local function GetEntityCharacter(entity)
    if entity:IsA("Player") then return entity.Character end
    return entity
end
Core.GetEntityCharacter = GetEntityCharacter

-- Checks player.Team first (native Roblox teams), then falls back to
-- common game-specific patterns: attribute, leaderstats child, or any
-- direct child value whose name contains "team".
local function GetEntityTeam(entity)
    if entity:IsA("Player") then
        if entity.Team ~= nil then return entity.Team end
        local attr = entity:GetAttribute("Team")
        if attr ~= nil then return attr end
        local tv = entity:FindFirstChild("Team")
        if tv then
            if tv:IsA("StringValue") or tv:IsA("IntValue") or tv:IsA("NumberValue") then
                return tv.Value
            elseif tv:IsA("ObjectValue") then
                return tv.Value
            end
        end
        local leaderstats = entity:FindFirstChild("leaderstats")
        if leaderstats then
            local lsTeam = leaderstats:FindFirstChild("Team")
            if lsTeam then
                if lsTeam:IsA("StringValue") or lsTeam:IsA("IntValue") or lsTeam:IsA("NumberValue") then
                    return lsTeam.Value
                elseif lsTeam:IsA("ObjectValue") then
                    return lsTeam.Value
                end
            end
        end
        for _, child in ipairs(entity:GetChildren()) do
            if child.Name:lower():find("team") then
                if child:IsA("StringValue") or child:IsA("IntValue") or child:IsA("NumberValue") then
                    return child.Value
                elseif child:IsA("ObjectValue") then
                    return child.Value
                end
            end
        end
        return nil
    end
    local attr = entity:GetAttribute("Team")
    if attr ~= nil then return attr end
    local tv = entity:FindFirstChild("Team")
    if tv and tv:IsA("StringValue") then return tv.Value end
    return nil
end
Core.GetEntityTeam = GetEntityTeam

local function IsSameTeam(entity)
    local enabled = entity:IsA("Player") and Core.Config.TeamCheck or Core.Config.NPC.TeamCheck
    if not enabled then return false end
    local entityTeam = GetEntityTeam(entity)
    local localTeam  = GetEntityTeam(LocalPlayer)
    if entityTeam == nil or localTeam == nil then return false end
    return entityTeam == localTeam or tostring(entityTeam) == tostring(localTeam)
end
Core.IsSameTeam = IsSameTeam

------------------------------------------------------------------------
-- ESP CACHE MANAGEMENT
------------------------------------------------------------------------
local function CreateESP(entity)
    if Core.Cache[entity] then return end
    local esp = {
        Head=nil, RootPart=nil, Humanoid=nil,
        _frame            = math.random(0, 5),
        _visible          = true,
        _lastVisibleCheck = 0,
        _rayParams        = BuildRaycastParams(),
        _charConn         = nil,
        _charRemovalConn  = nil,
    }
    Core.Cache[entity] = esp
    if Core.OnEntityAdded then Core.OnEntityAdded(entity, esp) end
end

local function RemoveESP(entity)
    local esp = Core.Cache[entity]
    if not esp then return end
    if Core.OnEntityRemoved then Core.OnEntityRemoved(entity, esp) end
    if esp._charConn        then esp._charConn:Disconnect();        esp._charConn=nil        end
    if esp._charRemovalConn then esp._charRemovalConn:Disconnect(); esp._charRemovalConn=nil end
    Core.Cache[entity] = nil
end
Core.RemoveESP = RemoveESP

local function HideAll(esp)
    if Core.OnHideAll then Core.OnHideAll(esp) end
end
Core.HideAll = HideAll

------------------------------------------------------------------------
-- TRACKING
------------------------------------------------------------------------
local function TrackPlayer(player)
    if player == LocalPlayer then return end
    CreateESP(player)
    local esp = Core.Cache[player]
    if not esp then return end
    if player.Character then RefreshESPParts(esp, player.Character) end
    esp._charConn = player.CharacterAdded:Connect(function(c)
        RefreshESPParts(esp, c)
        if esp.Skeleton then esp.Skeleton._joints=nil; esp.Skeleton._rig=nil end
    end)
    esp._charRemovalConn = player.CharacterRemoving:Connect(function()
        ClearESPParts(esp)
    end)
end
Core.TrackPlayer = TrackPlayer

local function TrackNPC(model)
    if not Core.Config.NPC.Enabled then return end
    if not IsNPCModel(model)       then return end
    CreateESP(model)
    local esp = Core.Cache[model]
    if esp then RefreshESPParts(esp, model) end
end

local function UntrackPlayer(player) RemoveESP(player) end
Core.UntrackPlayer = UntrackPlayer

local function TryTrackNPCModel(model)
    if IsNPCModel(model) then TrackNPC(model) end
end
Core.TryTrackNPCModel = TryTrackNPCModel

------------------------------------------------------------------------
-- NPC CONTAINER GUARD
------------------------------------------------------------------------
local _workspaceTerrain = workspace:FindFirstChildOfClass("Terrain")

local function IsNonCharacterContainer(instance)
    if _workspaceTerrain and (instance == _workspaceTerrain or instance:IsDescendantOf(_workspaceTerrain)) then
        return true
    end
    local cam = workspace.CurrentCamera
    if cam and (instance == cam or instance:IsDescendantOf(cam)) then return true end
    return false
end

------------------------------------------------------------------------
-- SEED
-- Called by loader.lua after Renderer:Init() so OnEntityAdded is wired
-- up before any entities are tracked and Drawing objects are created.
------------------------------------------------------------------------
function Core:Seed()
    local _npcPending = {}

    self.Connections.PlayerAdded    = Players.PlayerAdded:Connect(TrackPlayer)
    self.Connections.PlayerRemoving = Players.PlayerRemoving:Connect(UntrackPlayer)

    self.Connections.NPCAdded = workspace.DescendantAdded:Connect(function(desc)
        if IsNonCharacterContainer(desc) then return end
        local model
        if desc:IsA("Model") then
            model = desc
        elseif desc.Parent and desc.Parent:IsA("Model") then
            model = desc.Parent
        else
            return
        end
        if _npcPending[model] then return end
        _npcPending[model] = true
        task.defer(function()
            _npcPending[model] = nil
            if model and model.Parent then TryTrackNPCModel(model) end
        end)
    end)

    self.Connections.NPCRemoving = workspace.DescendantRemoving:Connect(function(desc)
        if self.Cache[desc] then RemoveESP(desc); return end
        local parent = desc.Parent
        if parent and parent:IsA("Model") and self.Cache[parent]
        and not parent:IsDescendantOf(workspace) then
            RemoveESP(parent)
        end
    end)

    for _, p in ipairs(Players:GetPlayers()) do TrackPlayer(p) end
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("Model") then TryTrackNPCModel(d) end
    end
end

------------------------------------------------------------------------
-- SHUTDOWN
------------------------------------------------------------------------
function Core:Shutdown()
    for _, conn in pairs(self.Connections) do
        if typeof(conn) == "RBXScriptConnection" then conn:Disconnect() end
    end
    self.Connections = {}

    local toRemove = {}
    for entity in pairs(self.Cache) do toRemove[#toRemove + 1] = entity end
    for _, entity in ipairs(toRemove) do RemoveESP(entity) end
    table.clear(self.Cache)
end

return Core
