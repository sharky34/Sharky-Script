--[[
    loader.lua — ESP Entry Point
    This is the only file you ever paste into your executor.

    To update the ESP:
      - Push changes to any individual file on GitHub
      - Re-run this loader — it always fetches the latest version

    Branch switching:
      - Change BRANCH to "dev" while testing new features
      - Merge to "main" when stable
]]

local REPO   = "https://raw.githubusercontent.com/sharky34/Sharky-Script"
local BRANCH = "main"
local BASE   = REPO .. "/" .. BRANCH .. "/"

------------------------------------------------------------------------
-- FETCH HELPER
------------------------------------------------------------------------
local function Fetch(filename)
    local ok, result = pcall(function()
        return game:HttpGet(BASE .. filename)
    end)
    if not ok then
        error("Loader: failed to fetch " .. filename .. ": " .. tostring(result), 2)
    end
    return result
end

local function Load(filename)
    local src = Fetch(filename)
    local fn, err = loadstring(src)
    if not fn then
        error("Loader: failed to compile " .. filename .. ": " .. tostring(err), 2)
    end
    return fn()
end

------------------------------------------------------------------------
-- LOAD ORDER
-- Core first — Renderer and GUI both depend on it.
-- Renderer before GUI so callbacks are wired before Seed() tracks entities.
------------------------------------------------------------------------
local Core     = Load("core.lua")
local Renderer = Load("renderer.lua")
local GUI      = Load("gui.lua")

------------------------------------------------------------------------
-- INIT ORDER
-- 1. Renderer:Init(Core)      — wires Drawing callbacks onto Core
-- 2. Core:Seed()              — starts tracking; entities get Drawing objects immediately
-- 3. GUI:Init(Core, Renderer) — builds the settings menu
------------------------------------------------------------------------
Renderer:Init(Core)
Core:Seed()
GUI:Init(Core, Renderer)

------------------------------------------------------------------------
-- SHUTDOWN
-- Kept local — not written to _G to avoid a detectable global name.
------------------------------------------------------------------------
local function Shutdown()
    GUI:Destroy()
    Core:Shutdown()
    Renderer:Shutdown()
end
