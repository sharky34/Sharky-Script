--[[
    gui.lua — ESP GUI Module
    Handles: Theme, all widget builders, tab layout, and the settings menu.
    Receives Core and Renderer via GUI:Init(Core, Renderer).
    Reads Core.Config for initial state, writes back to Core.Config on change.
    Calls Renderer:UpdateAllESPComponents() when component toggles change.
]]

local UserInput = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenSvc  = game:GetService("TweenService")

local GUI = {}

local function GetCamera()
    return workspace.CurrentCamera
end

------------------------------------------------------------------------
-- THEME
------------------------------------------------------------------------
local Theme = {
    BG          = Color3.fromRGB(15,  15,  20),
    Sidebar     = Color3.fromRGB(20,  20,  28),
    Surface     = Color3.fromRGB(26,  27,  36),
    SurfaceAlt  = Color3.fromRGB(32,  33,  44),
    Accent      = Color3.fromRGB(99,  102, 241),
    AccentHover = Color3.fromRGB(129, 132, 255),
    AccentDim   = Color3.fromRGB(55,  57,  140),
    Danger      = Color3.fromRGB(239, 68,  68),
    Success     = Color3.fromRGB(34,  197, 94),
    Warning     = Color3.fromRGB(234, 179, 8),
    Text        = Color3.fromRGB(235, 235, 245),
    TextSub     = Color3.fromRGB(140, 140, 165),
    TextMuted   = Color3.fromRGB(80,  80,  100),
    Border      = Color3.fromRGB(45,  46,  62),
    White       = Color3.fromRGB(255, 255, 255),
    Black       = Color3.fromRGB(0,   0,   0),
}

local ActiveSliderUpdateFn = nil

------------------------------------------------------------------------
-- HELPERS
------------------------------------------------------------------------
local function MakeCorner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 6)
    c.Parent = parent
    return c
end

local function MakePadding(parent, top, right, bottom, left)
    local p = Instance.new("UIPadding")
    p.PaddingTop    = UDim.new(0, top    or 0)
    p.PaddingRight  = UDim.new(0, right  or 0)
    p.PaddingBottom = UDim.new(0, bottom or 0)
    p.PaddingLeft   = UDim.new(0, left   or 0)
    p.Parent = parent
    return p
end

local function MakeListLayout(parent, padding, fillDir)
    local l = Instance.new("UIListLayout")
    l.SortOrder     = Enum.SortOrder.LayoutOrder
    l.FillDirection = fillDir or Enum.FillDirection.Vertical
    l.Padding       = UDim.new(0, padding or 8)
    l.Parent = parent
    return l
end

local function MakeStroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color           = color or Theme.Border
    s.Thickness       = thickness or 1
    s.Transparency    = transparency or 0
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
    return s
end

local function MakeFrame(parent, size, pos, bg, name)
    local f = Instance.new("Frame")
    f.Name             = name or "Frame"
    f.Parent           = parent
    f.Size             = size or UDim2.new(1,0,0,32)
    f.Position         = pos  or UDim2.new(0,0,0,0)
    f.BackgroundColor3 = bg   or Theme.Surface
    f.BorderSizePixel  = 0
    return f
end

local function MakeLabel(parent, text, size, pos, textColor, textSize, font)
    local l = Instance.new("TextLabel")
    l.Name                  = "Label"
    l.Parent                = parent
    l.Size                  = size or UDim2.new(1,0,0,20)
    l.Position              = pos  or UDim2.new(0,0,0,0)
    l.BackgroundTransparency = 1
    l.Text                  = text or ""
    l.TextColor3            = textColor or Theme.Text
    l.Font                  = font      or Enum.Font.GothamSemibold
    l.TextSize              = textSize  or 13
    l.TextXAlignment        = Enum.TextXAlignment.Left
    l.TextYAlignment        = Enum.TextYAlignment.Center
    return l
end

local function MakeScrollFrame(parent, size, pos)
    local sf = Instance.new("ScrollingFrame")
    sf.Name                 = "Scroll"
    sf.Parent               = parent
    sf.Size                 = size or UDim2.new(1,0,1,0)
    sf.Position             = pos  or UDim2.new(0,0,0,0)
    sf.BackgroundTransparency = 1
    sf.BorderSizePixel      = 0
    sf.ScrollBarThickness   = 3
    sf.ScrollBarImageColor3 = Theme.Accent
    sf.CanvasSize           = UDim2.new(0,0,0,0)
    sf.AutomaticCanvasSize  = Enum.AutomaticSize.Y
    sf.ClipsDescendants     = true
    sf.ScrollingDirection   = Enum.ScrollingDirection.Y
    return sf
end

local function MakeTextInput(parent, placeholder, size, pos)
    local box = Instance.new("TextBox")
    box.Parent               = parent
    box.Size                 = size or UDim2.new(1,0,1,0)
    box.Position             = pos  or UDim2.new(0,0,0,0)
    box.BackgroundTransparency = 1
    box.Text                 = ""
    box.PlaceholderText      = placeholder or ""
    box.TextColor3           = Theme.Text
    box.PlaceholderColor3    = Theme.TextMuted
    box.Font                 = Enum.Font.Gotham
    box.TextSize             = 13
    box.TextXAlignment       = Enum.TextXAlignment.Left
    box.ClearTextOnFocus     = false
    return box
end

local function CreateSectionHeader(parent, text)
    local row = MakeFrame(parent, UDim2.new(1,0,0,28), nil, Color3.fromRGB(0,0,0,0))
    row.BackgroundTransparency = 1
    MakeLabel(row, string.upper(text), UDim2.new(1,0,0,20), UDim2.new(0,0,0,4), Theme.TextSub, 11, Enum.Font.GothamBold)
    local line = MakeFrame(row, UDim2.new(1,0,0,1), UDim2.new(0,0,0,24), Theme.Border)
    line.BackgroundTransparency = 0.5
    return row
end

local function CreatePage(parent, title)
    local page = MakeFrame(parent, UDim2.new(1,0,1,0), nil, Color3.fromRGB(0,0,0,0))
    page.Name    = title .. "Page"
    page.Visible = false
    local scroll = MakeScrollFrame(page)
    local inner  = MakeFrame(scroll, UDim2.new(1,0,0,0), nil, Color3.fromRGB(0,0,0,0))
    inner.Name                  = "Inner"
    inner.AutomaticSize         = Enum.AutomaticSize.Y
    inner.BackgroundTransparency = 1
    MakePadding(inner, 4, 4, 12, 4)
    MakeListLayout(inner, 6)
    return page, inner
end

------------------------------------------------------------------------
-- WIDGETS
------------------------------------------------------------------------
local function CreateToggle(parent, labelText, initial, callback)
    local row = MakeFrame(parent, UDim2.new(1,0,0,36), nil, Theme.Surface)
    MakeCorner(row, 6)
    MakePadding(row, 0, 12, 0, 12)
    MakeLabel(row, labelText, UDim2.new(1,-68,1,0), nil, Theme.Text, 13)

    local pill = MakeFrame(row, UDim2.new(0,44,0,22), UDim2.new(1,-44,0.5,-11), Theme.SurfaceAlt)
    MakeCorner(pill, 11)
    MakeStroke(pill, Theme.Border, 1)
    local knob = MakeFrame(pill, UDim2.new(0,16,0,16), UDim2.new(0,3,0.5,-8), Theme.TextMuted)
    MakeCorner(knob, 8)

    local state = initial
    local function Refresh(v, animate)
        state = v
        local kx = v and 0.5  or 0
        local pc = v and Theme.Accent    or Theme.SurfaceAlt
        local kc = v and Theme.White     or Theme.TextMuted
        if animate then
            TweenSvc:Create(knob, TweenInfo.new(0.15), {Position=UDim2.new(kx,3,0.5,-8), BackgroundColor3=kc}):Play()
            TweenSvc:Create(pill, TweenInfo.new(0.15), {BackgroundColor3=pc}):Play()
        else
            knob.Position         = UDim2.new(kx,3,0.5,-8)
            knob.BackgroundColor3 = kc
            pill.BackgroundColor3 = pc
        end
    end

    Refresh(initial, false)
    pill.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            Refresh(not state, true)
            callback(state)
        end
    end)
    row.MouseEnter:Connect(function() TweenSvc:Create(row, TweenInfo.new(0.1), {BackgroundColor3=Theme.SurfaceAlt}):Play() end)
    row.MouseLeave:Connect(function() TweenSvc:Create(row, TweenInfo.new(0.1), {BackgroundColor3=Theme.Surface}):Play() end)
    return row
end

local function CreateSlider(parent, labelText, minVal, maxVal, step, initVal, callback)
    local row = MakeFrame(parent, UDim2.new(1,0,0,58), nil, Theme.Surface)
    MakeCorner(row, 6)
    MakePadding(row, 8, 12, 8, 12)

    local header = MakeFrame(row, UDim2.new(1,0,0,18), nil, Color3.fromRGB(0,0,0,0))
    header.BackgroundTransparency = 1
    MakeLabel(header, labelText, UDim2.new(0.7,0,1,0), nil, Theme.Text, 13)
    local valLabel = MakeLabel(header, tostring(initVal), UDim2.new(0.3,0,1,0), UDim2.new(0.7,0,0,0), Theme.Accent, 13, Enum.Font.GothamBold)
    valLabel.TextXAlignment = Enum.TextXAlignment.Right

    local track = MakeFrame(row, UDim2.new(1,0,0,6), UDim2.new(0,0,0,28), Theme.SurfaceAlt)
    MakeCorner(track, 3)
    local fill = MakeFrame(track, UDim2.new(0,0,1,0), nil, Theme.Accent)
    MakeCorner(fill, 3)
    local handle = MakeFrame(track, UDim2.new(0,12,0,12), UDim2.new(0,0,0.5,-6), Theme.White)
    MakeCorner(handle, 6)
    MakeStroke(handle, Theme.AccentDim, 2)

    local function SetValue(v)
        v = math.clamp(v, minVal, maxVal)
        v = math.floor(v/step + 0.5) * step
        local frac = (v - minVal) / math.max(maxVal - minVal, 1)
        fill.Size          = UDim2.new(frac, 0, 1, 0)
        handle.Position    = UDim2.new(frac, -6, 0.5, -6)
        valLabel.Text      = tostring(v)
        callback(v)
    end

    local function UpdateFromX(x)
        local rel  = x - track.AbsolutePosition.X
        local frac = math.clamp(rel / math.max(track.AbsoluteSize.X, 1), 0, 1)
        SetValue(minVal + frac * (maxVal - minVal))
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            ActiveSliderUpdateFn = UpdateFromX
            UpdateFromX(input.Position.X)
        end
    end)
    track.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            if ActiveSliderUpdateFn == UpdateFromX then ActiveSliderUpdateFn = nil end
        end
    end)
    row.MouseEnter:Connect(function() TweenSvc:Create(row, TweenInfo.new(0.1), {BackgroundColor3=Theme.SurfaceAlt}):Play() end)
    row.MouseLeave:Connect(function() TweenSvc:Create(row, TweenInfo.new(0.1), {BackgroundColor3=Theme.Surface}):Play() end)
    SetValue(initVal)
    return row
end

local function CreateDropdown(parent, labelText, options, selected, callback)
    local ITEM_H = 30
    local open   = false

    local wrapper = MakeFrame(parent, UDim2.new(1,0,0,36), nil, Color3.fromRGB(0,0,0,0))
    wrapper.BackgroundTransparency = 1
    wrapper.ClipsDescendants       = false

    local row = MakeFrame(wrapper, UDim2.new(1,0,0,36), nil, Theme.Surface)
    MakeCorner(row, 6)
    MakePadding(row, 0, 12, 0, 12)
    MakeStroke(row, Theme.Border, 1)
    MakeLabel(row, labelText, UDim2.new(0.55,0,1,0), nil, Theme.Text, 13)

    local selLabel = MakeLabel(row, selected, UDim2.new(0.35,0,1,0), UDim2.new(0.55,0,0,0), Theme.Accent, 13, Enum.Font.GothamBold)
    selLabel.TextXAlignment = Enum.TextXAlignment.Right
    local arrow = MakeLabel(row, "▾", UDim2.new(0,16,1,0), UDim2.new(1,-16,0,0), Theme.TextSub, 14)
    arrow.TextXAlignment = Enum.TextXAlignment.Center

    local panel = MakeFrame(wrapper, UDim2.new(1,0,0,#options*ITEM_H+8), UDim2.new(0,0,0,40), Theme.SurfaceAlt)
    panel.ZIndex  = 10
    panel.Visible = false
    MakeCorner(panel, 6)
    MakeStroke(panel, Theme.Accent, 1, 0.5)
    MakePadding(panel, 4, 4, 4, 4)

    local function Close()
        open = false; panel.Visible = false; arrow.Text = "▾"
    end

    for i, opt in ipairs(options) do
        local item = Instance.new("TextButton")
        item.Name                  = opt
        item.Parent                = panel
        item.Size                  = UDim2.new(1,0,0,ITEM_H)
        item.Position              = UDim2.new(0,0,0,(i-1)*ITEM_H)
        item.BackgroundTransparency = 1
        item.Text                  = opt
        item.TextColor3            = (opt == selected) and Theme.Accent or Theme.Text
        item.Font                  = Enum.Font.GothamSemibold
        item.TextSize              = 13
        item.ZIndex                = 11
        MakeCorner(item, 4)
        item.MouseEnter:Connect(function()
            item.BackgroundTransparency = 0
            TweenSvc:Create(item, TweenInfo.new(0.1), {BackgroundColor3=Theme.Border}):Play()
        end)
        item.MouseLeave:Connect(function() item.BackgroundTransparency = 1 end)
        item.MouseButton1Click:Connect(function()
            selected = opt; selLabel.Text = opt
            for _, c in ipairs(panel:GetChildren()) do
                if c:IsA("TextButton") then
                    c.TextColor3 = (c.Name == opt) and Theme.Accent or Theme.Text
                end
            end
            callback(opt); Close()
        end)
    end

    row.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            open = not open; panel.Visible = open; arrow.Text = open and "▴" or "▾"
        end
    end)
    return wrapper
end

------------------------------------------------------------------------
-- SHARED: component toggles — used by Players and Visuals tabs
------------------------------------------------------------------------
local function BuildComponentToggles(parent, startOrder, Config, Renderer)
    CreateToggle(parent, "Box", Config.Components.Box, function(v)
        Config.Components.Box = v; Renderer:UpdateAllESPComponents("Box", v)
    end).LayoutOrder = startOrder
    CreateToggle(parent, "Name Tag", Config.Components.Name, function(v)
        Config.Components.Name = v; Renderer:UpdateAllESPComponents("Name", v)
    end).LayoutOrder = startOrder + 1
    CreateToggle(parent, "Health Bar", Config.Components.Health, function(v)
        Config.Components.Health = v; Renderer:UpdateAllESPComponents("Health", v)
    end).LayoutOrder = startOrder + 2
    CreateToggle(parent, "Skeleton", Config.Components.Skeleton, function(v)
        Config.Components.Skeleton = v; Renderer:UpdateAllESPComponents("Skeleton", v)
    end).LayoutOrder = startOrder + 3
end

------------------------------------------------------------------------
-- INIT
------------------------------------------------------------------------
function GUI:Init(Core, Renderer)
    self.Core     = Core
    self.Renderer = Renderer
    self.ScreenGui    = nil
    self.Pages        = {}
    self.TabButtons   = {}
    self.CurrentTab   = "General"
    self.Connections  = {}
    self.ActiveIndicator = nil

    self:Build()
end

local MOUSE_BIND = "ESPMouseOverride"

function GUI:TrackConn(conn)
    table.insert(self.Connections, conn); return conn
end

function GUI:Build()
    if self.ScreenGui then return end

    local Config   = self.Core.Config
    local Renderer = self.Renderer

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name           = "ESPMenu"
    screenGui.ResetOnSpawn   = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent         = gethui()
    self.ScreenGui = screenGui

    -- Shared slider drag listener
    if not self.Core.Connections.SliderDrag then
        self.Core.Connections.SliderDrag = UserInput.InputChanged:Connect(function(input)
            if ActiveSliderUpdateFn and input.UserInputType == Enum.UserInputType.MouseMovement then
                ActiveSliderUpdateFn(input.Position.X)
            end
        end)
    end

    local WIN_W, WIN_H = 520, 500
    local root = MakeFrame(screenGui,
        UDim2.new(0,WIN_W,0,WIN_H),
        UDim2.new(0.5,-WIN_W/2,0.5,-WIN_H/2),
        Theme.BG, "Root")
    MakeCorner(root, 10)
    MakeStroke(root, Theme.Border, 1)
    root.ClipsDescendants = false
    root.Active           = true
    root.Visible          = false

    --------------------------------------------------------------------
    -- Title bar
    --------------------------------------------------------------------
    local titleBar = MakeFrame(root, UDim2.new(1,0,0,44), nil, Theme.Sidebar, "TitleBar")
    MakeCorner(titleBar, 10)
    MakeFrame(root, UDim2.new(1,0,0,10), UDim2.new(0,0,0,34), Theme.Sidebar)
    local dot = MakeFrame(titleBar, UDim2.new(0,8,0,8), UDim2.new(0,14,0.5,-4), Theme.Accent)
    MakeCorner(dot, 4)
    MakeLabel(titleBar, "ESP  Settings", UDim2.new(1,-90,1,0), UDim2.new(0,30,0,0), Theme.Text, 15, Enum.Font.GothamBlack)

    local closeBtn = Instance.new("TextButton")
    closeBtn.Name             = "Close"
    closeBtn.Parent           = titleBar
    closeBtn.Size             = UDim2.new(0,28,0,28)
    closeBtn.Position         = UDim2.new(1,-38,0.5,-14)
    closeBtn.BackgroundColor3 = Color3.fromRGB(60,30,30)
    closeBtn.BorderSizePixel  = 0
    closeBtn.Text             = "✕"
    closeBtn.TextColor3       = Theme.Danger
    closeBtn.Font             = Enum.Font.GothamBold
    closeBtn.TextSize         = 14
    MakeCorner(closeBtn, 6)
    closeBtn.MouseEnter:Connect(function()
        TweenSvc:Create(closeBtn, TweenInfo.new(0.1), {BackgroundColor3=Theme.Danger, TextColor3=Theme.White}):Play()
    end)
    closeBtn.MouseLeave:Connect(function()
        TweenSvc:Create(closeBtn, TweenInfo.new(0.1), {BackgroundColor3=Color3.fromRGB(60,30,30), TextColor3=Theme.Danger}):Play()
    end)

    --------------------------------------------------------------------
    -- Mouse unlock
    -- BindToRenderStep at Camera+1 ensures the override runs after the
    -- game camera re-locks the cursor, keeping the GUI usable regardless
    -- of the game's MouseBehavior setting.
    --------------------------------------------------------------------
    local savedMouseBehavior, savedMouseIconEnabled

    local function OpenGui()
        if root.Visible then return end
        savedMouseBehavior    = UserInput.MouseBehavior
        savedMouseIconEnabled = UserInput.MouseIconEnabled
        root.Visible = true
        RunService:BindToRenderStep(MOUSE_BIND, Enum.RenderPriority.Camera.Value + 1, function()
            UserInput.MouseBehavior    = Enum.MouseBehavior.Default
            UserInput.MouseIconEnabled = true
        end)
    end

    local function CloseGui()
        if not root.Visible then return end
        root.Visible = false
        pcall(function() RunService:UnbindFromRenderStep(MOUSE_BIND) end)
        if savedMouseBehavior    ~= nil then UserInput.MouseBehavior    = savedMouseBehavior    end
        if savedMouseIconEnabled ~= nil then UserInput.MouseIconEnabled = savedMouseIconEnabled end
    end

    closeBtn.MouseButton1Click:Connect(CloseGui)

    --------------------------------------------------------------------
    -- Drag
    --------------------------------------------------------------------
    local dragging, dragStart, dragStartPos = false, Vector2.new(), Vector2.new()
    local function ClampPos(pos)
        local cam = GetCamera()
        local vp  = cam and cam.ViewportSize or Vector2.new(1280, 720)
        return UDim2.new(0,
            math.clamp(pos.X.Offset, 0, math.max(vp.X - WIN_W, 0)),
            0,
            math.clamp(pos.Y.Offset, 0, math.max(vp.Y - WIN_H, 0)))
    end
    self:TrackConn(titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging=true; dragStart=input.Position
            dragStartPos=Vector2.new(root.AbsolutePosition.X, root.AbsolutePosition.Y)
        end
    end))
    self:TrackConn(titleBar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging=false end
    end))
    self:TrackConn(UserInput.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - dragStart
            root.Position = ClampPos(UDim2.new(0, dragStartPos.X+d.X, 0, dragStartPos.Y+d.Y))
        end
    end))

    -- RightShift toggle
    self:TrackConn(UserInput.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == Enum.KeyCode.RightShift then
            if root.Visible then CloseGui() else OpenGui() end
        end
    end))

    --------------------------------------------------------------------
    -- Body layout
    --------------------------------------------------------------------
    local body = MakeFrame(root, UDim2.new(1,0,1,-44), UDim2.new(0,0,0,44), Theme.BG, "Body")
    local SIDE_W  = 128
    local sidebar = MakeFrame(body, UDim2.new(0,SIDE_W,1,0), nil, Theme.Sidebar, "Sidebar")
    local edge    = MakeFrame(body, UDim2.new(0,1,1,0), UDim2.new(0,SIDE_W,0,0), Theme.Border)
    edge.BackgroundTransparency = 0.5

    local indicator = MakeFrame(sidebar, UDim2.new(0,3,0,28), UDim2.new(0,0,0,0), Theme.Accent, "Indicator")
    MakeCorner(indicator, 2)
    self.ActiveIndicator = indicator
    MakePadding(sidebar, 8, 6, 8, 6)
    MakeListLayout(sidebar, 4)

    local contentArea = MakeFrame(body, UDim2.new(1,-SIDE_W-1,1,0), UDim2.new(0,SIDE_W+1,0,0), Theme.BG, "Content")
    MakePadding(contentArea, 8, 8, 8, 8)

    --------------------------------------------------------------------
    -- Tabs
    --------------------------------------------------------------------
    local tabDefs = {
        {name="General",     icon="⚙"},
        {name="Players",     icon="👤"},
        {name="NPCs",        icon="🤖"},
        {name="Visuals",     icon="🎨"},
        {name="Style",       icon="✏"},
        {name="Performance", icon="⚡"},
    }

    local pages = {}
    local function SelectTab(tabName)
        self.CurrentTab = tabName
        for name, pf in pairs(pages) do pf.Visible = (name == tabName) end
        for name, btn in pairs(self.TabButtons) do
            local active = (name == tabName)
            TweenSvc:Create(btn, TweenInfo.new(0.12), {
                BackgroundColor3       = active and Theme.AccentDim or Color3.fromRGB(0,0,0,0),
                BackgroundTransparency = active and 0 or 1,
            }):Play()
            local lbl = btn:FindFirstChild("Label")
            if lbl then
                TweenSvc:Create(lbl, TweenInfo.new(0.12), {
                    TextColor3 = active and Theme.White or Theme.TextSub,
                }):Play()
            end
            if active then
                local targetY = btn.AbsolutePosition.Y - sidebar.AbsolutePosition.Y
                TweenSvc:Create(indicator, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
                    Position = UDim2.new(0,0,0, targetY+2),
                    Size     = UDim2.new(0,3,0, btn.AbsoluteSize.Y-4),
                }):Play()
            end
        end
    end

    for i, def in ipairs(tabDefs) do
        local btn = Instance.new("TextButton")
        btn.Name                   = def.name.."Tab"
        btn.Parent                 = sidebar
        btn.Size                   = UDim2.new(1,0,0,34)
        btn.BackgroundColor3       = Theme.AccentDim
        btn.BackgroundTransparency = 1
        btn.BorderSizePixel        = 0
        btn.Text                   = ""
        btn.LayoutOrder            = i
        MakeCorner(btn, 6)
        local icon = MakeLabel(btn, def.icon, UDim2.new(0,24,1,0), UDim2.new(0,6,0,0), Theme.TextSub, 14)
        icon.Name = "Icon"
        local lbl = MakeLabel(btn, def.name, UDim2.new(1,-34,1,0), UDim2.new(0,30,0,0), Theme.TextSub, 12)
        lbl.Name = "Label"
        btn.MouseEnter:Connect(function()
            if self.CurrentTab ~= def.name then
                TweenSvc:Create(btn, TweenInfo.new(0.1), {BackgroundTransparency=0.6, BackgroundColor3=Theme.SurfaceAlt}):Play()
            end
        end)
        btn.MouseLeave:Connect(function()
            if self.CurrentTab ~= def.name then
                TweenSvc:Create(btn, TweenInfo.new(0.1), {BackgroundTransparency=1}):Play()
            end
        end)
        btn.MouseButton1Click:Connect(function() SelectTab(def.name) end)
        self.TabButtons[def.name] = btn
        local pf, inner = CreatePage(contentArea, def.name)
        pages[def.name]       = pf
        self.Pages[def.name]  = {frame=pf, inner=inner}
    end

    local function Tab(name) return self.Pages[name].inner end

    --------------------------------------------------------------------
    -- GENERAL
    --------------------------------------------------------------------
    local g = Tab("General")
    CreateSectionHeader(g, "Core").LayoutOrder = 1
    CreateToggle(g, "ESP Enabled", Config.Enabled, function(v)
        Config.Enabled = v
    end).LayoutOrder = 2
    CreateToggle(g, "Team Check (Players)", Config.TeamCheck, function(v)
        Config.TeamCheck = v
    end).LayoutOrder = 3
    CreateToggle(g, "Visibility Check", Config.Visibility.Enabled, function(v)
        Config.Visibility.Enabled = v
    end).LayoutOrder = 4
    CreateSectionHeader(g, "Distance").LayoutOrder = 5
    CreateSlider(g, "Max Distance", 200, 5000, 100, Config.MaxDistance, function(v)
        Config.MaxDistance = v
    end).LayoutOrder = 6
    CreateSlider(g, "Skeleton Max Distance", 50, 1000, 25, Config.SkeletonMaxDistance, function(v)
        Config.SkeletonMaxDistance = v
    end).LayoutOrder = 7

    --------------------------------------------------------------------
    -- PLAYERS
    --------------------------------------------------------------------
    local pl = Tab("Players")
    CreateSectionHeader(pl, "Team").LayoutOrder = 1
    CreateToggle(pl, "Team Check", Config.TeamCheck, function(v)
        Config.TeamCheck = v
    end).LayoutOrder = 2
    CreateSectionHeader(pl, "Components").LayoutOrder = 3
    BuildComponentToggles(pl, 4, Config, Renderer)

    --------------------------------------------------------------------
    -- NPCs
    --------------------------------------------------------------------
    local np = Tab("NPCs")
    CreateSectionHeader(np, "NPC Settings").LayoutOrder = 1
    CreateToggle(np, "NPC ESP Enabled", Config.NPC.Enabled, function(v)
        Config.NPC.Enabled = v
    end).LayoutOrder = 2
    CreateToggle(np, "NPC Team Check", Config.NPC.TeamCheck, function(v)
        Config.NPC.TeamCheck = v
    end).LayoutOrder = 3

    --------------------------------------------------------------------
    -- VISUALS
    --------------------------------------------------------------------
    local vi = Tab("Visuals")
    CreateSectionHeader(vi, "Components").LayoutOrder = 1
    BuildComponentToggles(vi, 2, Config, Renderer)
    CreateSectionHeader(vi, "Health Bar").LayoutOrder = 6
    CreateToggle(vi, "Health Lerp", Config.Health.Lerp, function(v)
        Config.Health.Lerp = v
    end).LayoutOrder = 7
    CreateToggle(vi, "Health Text", Config.Health.ShowText, function(v)
        Config.Health.ShowText = v
    end).LayoutOrder = 8
    CreateSlider(vi, "Lerp Speed", 1, 20, 1, math.floor(Config.Health.LerpSpeed*100), function(v)
        Config.Health.LerpSpeed = v / 100
    end).LayoutOrder = 9

    --------------------------------------------------------------------
    -- STYLE
    --------------------------------------------------------------------
    local st = Tab("Style")
    CreateSectionHeader(st, "Rendering").LayoutOrder = 1
    CreateToggle(st, "Outline", Config.Style.Outline, function(v)
        Config.Style.Outline = v
    end).LayoutOrder = 2
    CreateToggle(st, "Scale With Distance", Config.Style.ScaleWithDistance, function(v)
        Config.Style.ScaleWithDistance = v
    end).LayoutOrder = 3
    CreateSectionHeader(st, "Thickness").LayoutOrder = 4
    CreateSlider(st, "Box Thickness", 1, 5, 1, Config.Style.BoxThickness, function(v)
        Config.Style.BoxThickness = v
    end).LayoutOrder = 5
    CreateSlider(st, "Skeleton Thickness", 1, 5, 1, Config.Style.SkeletonThickness, function(v)
        Config.Style.SkeletonThickness = v
    end).LayoutOrder = 6
    CreateSectionHeader(st, "Text").LayoutOrder = 7
    CreateSlider(st, "Name Tag Size", 8, 24, 1, Config.Style.TextSize, function(v)
        Config.Style.TextSize = v
    end).LayoutOrder = 8

    --------------------------------------------------------------------
    -- PERFORMANCE
    --------------------------------------------------------------------
    local pf = Tab("Performance")
    CreateSectionHeader(pf, "Frame Throttle").LayoutOrder = 1
    CreateSlider(pf, "Near Rate (≤"..Config.Throttle.Near.Distance.."u)", 1, 10, 1, Config.Throttle.Near.Rate, function(v)
        Config.Throttle.Near.Rate = v
    end).LayoutOrder = 2
    CreateSlider(pf, "Mid Rate (≤"..Config.Throttle.Mid.Distance.."u)", 1, 10, 1, Config.Throttle.Mid.Rate, function(v)
        Config.Throttle.Mid.Rate = v
    end).LayoutOrder = 3
    CreateSlider(pf, "Far Rate (beyond mid)", 1, 15, 1, Config.Throttle.Far.Rate, function(v)
        Config.Throttle.Far.Rate = v
    end).LayoutOrder = 4
    CreateSectionHeader(pf, "Visibility Raycast").LayoutOrder = 5
    CreateToggle(pf, "Visibility Check", Config.Visibility.Enabled, function(v)
        Config.Visibility.Enabled = v
    end).LayoutOrder = 6

    SelectTab("General")
end

------------------------------------------------------------------------
-- DESTROY
------------------------------------------------------------------------
function GUI:Destroy()
    if not self.ScreenGui then return end
    ActiveSliderUpdateFn = nil
    pcall(function() RunService:UnbindFromRenderStep(MOUSE_BIND) end)
    if self.Core.Connections.SliderDrag then
        self.Core.Connections.SliderDrag:Disconnect()
        self.Core.Connections.SliderDrag = nil
    end
    for _, conn in ipairs(self.Connections) do
        if conn and conn.Connected then conn:Disconnect() end
    end
    self.Connections = {}
    self.ScreenGui:Destroy()
    self.ScreenGui  = nil
    self.Pages      = {}
    self.TabButtons = {}
end

return GUI
