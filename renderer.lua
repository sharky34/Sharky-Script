--[[
    renderer.lua — ESP Renderer Module
    Handles: Drawing pool, all ESP components (Box, Name, Health, Skeleton),
             visibility checks, world-to-screen math, and the render loop.
    Receives Core via Renderer:Init(Core). No GUI dependencies.
]]

local RunService  = game:GetService("RunService")
local LocalPlayer = game:GetService("Players").LocalPlayer

local Renderer = {}

local function GetCamera()
    return workspace.CurrentCamera
end

------------------------------------------------------------------------
-- DRAWING POOL
-- Objects are returned here (Visible=false) instead of being destroyed,
-- then re-used on the next request. Hard-destroyed only in Shutdown().
------------------------------------------------------------------------
local Pool = {}

local function PoolGet(drawType)
    Pool[drawType] = Pool[drawType] or {}
    if #Pool[drawType] > 0 then
        local obj = table.remove(Pool[drawType])
        obj.Visible = false
        return obj
    end
    return Drawing.new(drawType)
end

local function PoolReturn(obj, drawType)
    if not obj then return end
    obj.Visible = false
    Pool[drawType] = Pool[drawType] or {}
    table.insert(Pool[drawType], obj)
end

------------------------------------------------------------------------
-- MATH / SCREEN HELPERS
------------------------------------------------------------------------
local function W2S(pos)
    local cam = GetCamera()
    if not cam then return Vector2.new(0, 0), false end
    local vec, onScreen = cam:WorldToViewportPoint(pos)
    return Vector2.new(vec.X, vec.Y), onScreen
end

local function LerpColor(a, b, t)
    return Color3.new(a.R+(b.R-a.R)*t, a.G+(b.G-a.G)*t, a.B+(b.B-a.B)*t)
end

local function HealthColor(pct)
    if pct > 0.5 then
        return LerpColor(Color3.fromRGB(255,200,0), Color3.fromRGB(0,255,0), (pct-0.5)*2)
    else
        return LerpColor(Color3.fromRGB(255,0,0), Color3.fromRGB(255,200,0), pct*2)
    end
end

local function GetBoxBounds(esp)
    local char = esp.RootPart and esp.RootPart.Parent
    if not char then return nil end
    local cf, size = char:GetBoundingBox()
    local topPos, topOn = W2S(cf.Position + Vector3.new(0, size.Y/2, 0))
    local botPos, botOn = W2S(cf.Position - Vector3.new(0, size.Y/2, 0))
    if not topOn and not botOn then return nil end
    local height = math.abs(botPos.Y - topPos.Y)
    if height < 1 then return nil end
    local width = height * 0.65
    local cx    = (topPos.X + botPos.X) / 2
    return {
        tl     = Vector2.new(cx - width/2, topPos.Y),
        tr     = Vector2.new(cx + width/2, topPos.Y),
        bl     = Vector2.new(cx - width/2, botPos.Y),
        br     = Vector2.new(cx + width/2, botPos.Y),
        topY   = topPos.Y,
        botY   = botPos.Y,
        height = height,
        width  = width,
        cx     = cx,
    }
end

local function IsVisible(Config, esp, char, dist)
    if not Config.Visibility.Enabled then return true end
    local now      = tick()
    local T        = Config.Throttle
    local interval = dist <= T.Near.Distance and 0.1
                  or dist <= T.Mid.Distance  and 0.25
                  or 0.5
    if now - esp._lastVisibleCheck < interval then return esp._visible end
    local target = esp.Head or esp.RootPart
    if not target then
        esp._visible = false; esp._lastVisibleCheck = now; return false
    end
    local cam = GetCamera()
    if not cam then return true end
    esp._rayParams.FilterDescendantsInstances = { LocalPlayer.Character, char }
    local result = workspace:Raycast(cam.CFrame.Position, target.Position - cam.CFrame.Position, esp._rayParams)
    esp._visible          = (result == nil)
    esp._lastVisibleCheck = now
    return esp._visible
end

local function GetDistanceRate(Config, dist)
    local T = Config.Throttle
    if dist <= T.Near.Distance then return T.Near.Rate
    elseif dist <= T.Mid.Distance then return T.Mid.Rate
    else return T.Far.Rate end
end

------------------------------------------------------------------------
-- COMPONENTS
-- Line objects do NOT have an Outline property in Potassium.
-- Only Text drawing objects have Outline.
------------------------------------------------------------------------
local Box = {}
function Box.Create()
    return { Top=PoolGet("Line"), Bottom=PoolGet("Line"), Left=PoolGet("Line"), Right=PoolGet("Line") }
end
function Box.Update(d, bounds, dist, color, Config)
    if not bounds then Box.Hide(d); return end
    local scale = Config.Style.ScaleWithDistance and math.clamp(100/dist, 0.5, 2) or 1
    local thick = math.max(1, Config.Style.BoxThickness * scale)
    local function AL(line, from, to)
        line.From=from; line.To=to; line.Color=color; line.Thickness=thick; line.Visible=true
    end
    AL(d.Top,bounds.tl,bounds.tr); AL(d.Bottom,bounds.bl,bounds.br)
    AL(d.Left,bounds.tl,bounds.bl); AL(d.Right,bounds.tr,bounds.br)
end
function Box.Hide(d)
    d.Top.Visible=false; d.Bottom.Visible=false; d.Left.Visible=false; d.Right.Visible=false
end
function Box.Destroy(d)
    PoolReturn(d.Top,"Line"); PoolReturn(d.Bottom,"Line")
    PoolReturn(d.Left,"Line"); PoolReturn(d.Right,"Line")
end

local Name = {}
function Name.Create() return { Text=PoolGet("Text") } end
function Name.Update(d, entity, root, dist, color, Config)
    local sp, on = W2S(root.Position + Vector3.new(0, 3.5, 0))
    if not on then d.Text.Visible=false; return end
    local scale = Config.Style.ScaleWithDistance and math.clamp(100/dist, 0.6, 1.4) or 1
    d.Text.Text     = string.format("%s [%d]", entity.Name, math.floor(dist))
    d.Text.Position = sp
    d.Text.Size     = math.floor(Config.Style.TextSize * scale)
    d.Text.Color    = color
    d.Text.Center   = true
    d.Text.Outline  = Config.Style.Outline
    d.Text.Font     = Drawing.Fonts.UI
    d.Text.Visible  = true
end
function Name.Hide(d)    d.Text.Visible=false end
function Name.Destroy(d) PoolReturn(d.Text,"Text") end

local Health = {}
function Health.Create()
    return { Bar=PoolGet("Line"), BG=PoolGet("Line"), Label=nil, _hp=1.0 }
end
function Health.Update(d, esp, bounds, Config)
    if not bounds then Health.Hide(d); return end
    local hum = esp.Humanoid
    if not hum then Health.Hide(d); return end
    local target = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
    d._hp = Config.Health.Lerp and (d._hp + (target - d._hp) * Config.Health.LerpSpeed) or target

    if Config.Health.ShowText then
        if not d.Label then d.Label = PoolGet("Text") end
    else
        if d.Label then PoolReturn(d.Label,"Text"); d.Label=nil end
    end

    local barX    = bounds.tl.X - 5
    local color   = HealthColor(d._hp)
    local barTopY = bounds.botY - bounds.height * d._hp
    d.BG.From=Vector2.new(barX,bounds.topY); d.BG.To=Vector2.new(barX,bounds.botY)
    d.BG.Color=Color3.fromRGB(0,0,0); d.BG.Thickness=3; d.BG.Visible=true
    d.Bar.From=Vector2.new(barX,barTopY); d.Bar.To=Vector2.new(barX,bounds.botY)
    d.Bar.Color=color; d.Bar.Thickness=2; d.Bar.Visible=true
    if d.Label then
        d.Label.Text     = string.format("%d%%", math.floor(d._hp*100))
        d.Label.Position = Vector2.new(barX-2, (bounds.topY+bounds.botY)/2)
        d.Label.Size     = 10
        d.Label.Color    = color
        d.Label.Center   = true
        d.Label.Outline  = true
        d.Label.Font     = Drawing.Fonts.UI
        d.Label.Visible  = true
    end
end
function Health.Hide(d)
    d.Bar.Visible=false; d.BG.Visible=false
    if d.Label then d.Label.Visible=false end
end
function Health.Destroy(d)
    PoolReturn(d.Bar,"Line"); PoolReturn(d.BG,"Line")
    if d.Label then PoolReturn(d.Label,"Text") end
end

local Skeleton = {}

local function EnsureSkeletonLines(d, count)
    while #d.Lines < count do
        local line = PoolGet("Line"); line.Visible=false; d.Lines[#d.Lines+1]=line
    end
end

function Skeleton.Create()
    local lines = {}
    for i=1,16 do lines[i]=PoolGet("Line"); lines[i].Visible=false end
    return { Lines=lines, _joints=nil, _rig=nil }
end

function Skeleton.InvalidateCache(d) d._joints=nil; d._rig=nil end

function Skeleton.Update(d, char, color, Config, Core)
    local rig = Core.GetRig(char)
    if d._rig ~= rig then d._rig=rig; d._joints=nil end

    if not d._joints then
        if rig == "AUTO" then
            d._joints = Core.AutoDetectBones(char)
        else
            local entry
            for _, e in ipairs(Core.RigRegistry) do
                if e.name == rig then entry=e; break end
            end
            if not entry then Skeleton.Hide(d); return end
            local joints = {}
            for _, pair in ipairs(entry.bones) do
                local a=char:FindFirstChild(pair[1]); local b=char:FindFirstChild(pair[2])
                if a and b then joints[#joints+1]={a,b} end
            end
            d._joints = joints
        end
    end

    local count = #d._joints
    EnsureSkeletonLines(d, count)
    local thick = Config.Style.SkeletonThickness

    for i=1,#d.Lines do
        local line=d.Lines[i]; local pair=d._joints[i]
        if pair and i<=count then
            local ok, av, ao, bv, bo = pcall(function()
                local sa, oa = W2S(pair[1].Position)
                local sb, ob = W2S(pair[2].Position)
                return sa, oa, sb, ob
            end)
            if ok and (ao or bo) then
                line.From=av; line.To=bv; line.Color=color; line.Thickness=thick; line.Visible=true
            else
                line.Visible=false
                if not ok then d._joints=nil; Skeleton.Hide(d); return end
            end
        else
            line.Visible=false
        end
    end
end

function Skeleton.Hide(d)
    for i=1,#d.Lines do d.Lines[i].Visible=false end
end
function Skeleton.Destroy(d)
    for i=1,#d.Lines do PoolReturn(d.Lines[i],"Line") end
end

------------------------------------------------------------------------
-- COMPONENT MANAGEMENT
------------------------------------------------------------------------
local ComponentFactory = {
    Box=Box.Create, Name=Name.Create, Health=Health.Create, Skeleton=Skeleton.Create,
}
local ComponentDestructor = {
    Box=Box.Destroy, Name=Name.Destroy, Health=Health.Destroy, Skeleton=Skeleton.Destroy,
}

local function SetESPComponent(esp, name, enabled)
    if enabled then
        if not esp[name] and ComponentFactory[name] then esp[name]=ComponentFactory[name]() end
    else
        if esp[name] and ComponentDestructor[name] then ComponentDestructor[name](esp[name]); esp[name]=nil end
    end
end

function Renderer:UpdateAllESPComponents(name, enabled)
    for _, esp in pairs(self.Core.Cache) do SetESPComponent(esp, name, enabled) end
end

------------------------------------------------------------------------
-- INIT
------------------------------------------------------------------------
function Renderer:Init(Core)
    self.Core = Core

    -- Wire up Core's lifecycle callbacks so Renderer owns all Drawing state
    Core.OnEntityAdded = function(entity, esp)
        local C = Core.Config.Components
        esp.Box      = C.Box      and Box.Create()      or nil
        esp.Name     = C.Name     and Name.Create()     or nil
        esp.Health   = C.Health   and Health.Create()   or nil
        esp.Skeleton = C.Skeleton and Skeleton.Create() or nil
    end

    Core.OnEntityRemoved = function(entity, esp)
        if esp.Box      then Box.Destroy(esp.Box)           end
        if esp.Name     then Name.Destroy(esp.Name)         end
        if esp.Health   then Health.Destroy(esp.Health)     end
        if esp.Skeleton then Skeleton.Destroy(esp.Skeleton) end
    end

    Core.OnHideAll = function(esp)
        if esp.Box      then Box.Hide(esp.Box)           end
        if esp.Name     then Name.Hide(esp.Name)         end
        if esp.Health   then Health.Hide(esp.Health)     end
        if esp.Skeleton then Skeleton.Hide(esp.Skeleton) end
    end

    -- Render loop
    local FrameCount = 0
    Core.Connections.Render = RunService.RenderStepped:Connect(function()
        FrameCount = FrameCount + 1
        local cam  = GetCamera()
        if not cam then return end

        for entity, esp in pairs(Core.Cache) do
            local ok = pcall(function()
                if not Core.Config.Enabled then Core.HideAll(esp); return end
                local char = Core.GetEntityCharacter(entity)
                if not char then Core.HideAll(esp); return end
                Core.EnsureESPParts(esp, char)
                if not Core.IsAlive(esp)   then Core.HideAll(esp); return end
                if Core.IsSameTeam(entity) then Core.HideAll(esp); return end
                local root = esp.RootPart
                if not root then Core.HideAll(esp); return end
                local dist = (root.Position - cam.CFrame.Position).Magnitude
                if dist > Core.Config.MaxDistance then Core.HideAll(esp); return end
                local rate = GetDistanceRate(Core.Config, dist)
                if (FrameCount + esp._frame) % rate ~= 0 then return end
                local visible = IsVisible(Core.Config, esp, char, dist)
                local color   = visible and Core.Config.Visibility.VisibleColor or Core.Config.Visibility.OccludedColor
                local bounds  = (esp.Box or esp.Health) and GetBoxBounds(esp) or nil
                if esp.Box    then Box.Update(esp.Box, bounds, dist, color, Core.Config)         end
                if esp.Name   then Name.Update(esp.Name, entity, root, dist, color, Core.Config) end
                if esp.Health then Health.Update(esp.Health, esp, bounds, Core.Config)           end
                if esp.Skeleton then
                    if dist <= Core.Config.SkeletonMaxDistance then
                        Skeleton.Update(esp.Skeleton, char, color, Core.Config, Core)
                    else
                        Skeleton.Hide(esp.Skeleton)
                    end
                end
            end)
            if not ok then
                warn("[ESP] render error for", tostring(entity))
                pcall(function() Core.RemoveESP(entity) end)
            end
        end
    end)
end

------------------------------------------------------------------------
-- SHUTDOWN
------------------------------------------------------------------------
function Renderer:Shutdown()
    for _, bucket in pairs(Pool) do
        for _, obj in ipairs(bucket) do pcall(function() obj:Destroy() end) end
    end
    table.clear(Pool)
end

return Renderer
