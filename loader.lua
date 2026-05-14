--[[
    loader.lua — ESP Entry Point
    This is the only file you ever paste into your executor.

    Setup:
      1. Create a public GitHub repo
      2. Upload core.lua, renderer.lua, gui.lua alongside this file
      3. Set REPO below to your raw GitHub base URL
      4. Paste this file into your executor and run it

    To update the ESP:
      - Push changes to any individual file on GitHub
      - Re-run this loader — it always fetches the latest version

    Branch switching:
      - Change BRANCH to "dev" while testing new features
      - Merge to "main" when stable; users on "main" are never affected
]]

local REPO   = "https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO"
local BRANCH = "main"
local BASE   = REPO .. "/" .. BRANCH .. "/"

------------------------------------------------------------------------
-- FETCH HELPER
-- Wraps HttpGet with a clear error so you know immediately if a file
-- fails to load rather than getting a cryptic nil-index error later.
------------------------------------------------------------------------
local function Fetch(filename)
    local ok, result = pcall(function()
        return game:HttpGet(BASE .. filename)
    end)
    if not ok then
        error("[ESP Loader] Failed to fetch " .. filename .. ": " .. tostring(result), 2)
    end
    return result
end

local function Load(filename)
    local src = Fetch(filename)
    local fn, err = loadstring(src)
    if not fn then
        error("[ESP Loader] Failed to compile " .. filename .. ": " .. tostring(err), 2)
    end
    return fn()
end

------------------------------------------------------------------------
-- LOAD ORDER
-- Core must load first — Renderer and GUI depend on it.
-- Renderer loads before GUI so Renderer:Init() wires up Core callbacks
-- before Core:Seed() starts tracking entities.
------------------------------------------------------------------------
print("[ESP] Loading core...")
local Core = Load("core.lua")

print("[ESP] Loading renderer...")
local Renderer = Load("renderer.lua")

print("[ESP] Loading gui...")
local GUI = Load("gui.lua")

------------------------------------------------------------------------
-- INIT ORDER
-- 1. Renderer:Init(Core)  — wires up Drawing callbacks on Core
-- 2. Core:Seed()          — starts entity tracking (entities now get
--                           Drawing objects immediately via OnEntityAdded)
-- 3. GUI:Init(Core, Renderer) — builds the settings menu
------------------------------------------------------------------------
Renderer:Init(Core)
Core:Seed()
GUI:Init(Core, Renderer)

print("[ESP] Ready. Press RightShift to open settings.")

------------------------------------------------------------------------
-- EXPOSE for external scripts / debugging
-- e.g. _G.ESP.Core.Config.Enabled = false
------------------------------------------------------------------------
_G.ESP = {
    Core     = Core,
    Renderer = Renderer,
    GUI      = GUI,

    Shutdown = function()
        GUI:Destroy()
        Core:Shutdown()
        Renderer:Shutdown()
        _G.ESP = nil
        print("[ESP] Shutdown complete.")
    end,
}
