---------------------------------------------------------------
-- CPLight CVar Manager
---------------------------------------------------------------
-- Manages GamePad modifier CVars with original state preservation
-- Provides runtime cache for zero-overhead button checks

local ADDON_NAME, addon = ...
local CVarManager = {}

---------------------------------------------------------------
-- Constants
---------------------------------------------------------------
local CVAR_NAMES = {
    shift = "GamePadEmulateShift",
    ctrl = "GamePadEmulateCtrl",
    alt = "GamePadEmulateAlt",
}

-- Valid controller buttons that can be mapped to modifiers
CVarManager.ALLOWED_PADS = {
    "PADLTRIGGER",    -- Left Trigger
    "PADRTRIGGER",    -- Right Trigger
    "PADLSHOULDER",   -- Left Shoulder (Bumper)
    "PADRSHOULDER",   -- Right Shoulder (Bumper)
    "PADLSTICK",      -- Left Stick Click
    "PADRSTICK",      -- Right Stick Click
}

---------------------------------------------------------------
-- Runtime Cache (For Performance)
---------------------------------------------------------------
-- This cache is updated when user clicks Apply
-- Used by Hijack module for O(1) button checks (no GetCVar calls)
local Cache = {
    shift = "NONE",
    ctrl = "NONE",
    alt = "NONE",
}

---------------------------------------------------------------
-- Database Access
---------------------------------------------------------------
local function GetDB()
    local app = LibStub("AceAddon-3.0"):GetAddon("CPLight")
    return app.db
end

---------------------------------------------------------------
-- CVar Operations
---------------------------------------------------------------

--- Read a GamePad modifier CVar
---@param modifier string "shift", "ctrl", or "alt"
---@return string value The current CVar value (button name or "NONE")
local function ReadCVar(modifier)
    local cvarName = CVAR_NAMES[modifier]
    if not cvarName then return "NONE" end
    
    local value = GetCVar(cvarName)
    return value or "NONE"
end

--- Write a GamePad modifier CVar
---@param modifier string "shift", "ctrl", or "alt"
---@param value string Button name (e.g., "PADLTRIGGER") or "NONE"
local function WriteCVar(modifier, value)
    local cvarName = CVAR_NAMES[modifier]
    if not cvarName then return end
    
    SetCVar(cvarName, value or "NONE")
end

---------------------------------------------------------------
-- Initialization
---------------------------------------------------------------

--- Initialize CVarManager on addon load
--- Saves original CVars if this is the first load
function CVarManager:Initialize()
    local db = GetDB()
    
    -- Ensure database structure exists
    if not db.global.originalCVars then
        -- First time setup - capture user's current CVars
        db.global.originalCVars = {
            shift = ReadCVar("shift"),
            ctrl = ReadCVar("ctrl"),
            alt = ReadCVar("alt"),
        }
        CPAPI.DebugLog("CVarManager: Saved original CVars (first load)")
    end
    
    -- Initialize profile settings if needed
    if not db.profile.modifiers then
        db.profile.modifiers = {
            shift = "NONE",
            ctrl = "NONE",
            alt = "NONE",
        }
    end
    
    -- Load current CVars into cache for runtime performance
    self:RefreshCache()
    
    CPAPI.DebugLog("CVarManager: Initialized")
end

---------------------------------------------------------------
-- Cache Management
---------------------------------------------------------------

--- Refresh the runtime cache from current CVars
--- Called after Apply or Restore operations
function CVarManager:RefreshCache()
    Cache.shift = ReadCVar("shift")
    Cache.ctrl = ReadCVar("ctrl")
    Cache.alt = ReadCVar("alt")
    
    CPAPI.DebugLog(string.format("CVarManager: Cache refreshed - Shift=%s, Ctrl=%s, Alt=%s", 
        Cache.shift, Cache.ctrl, Cache.alt))
end

---------------------------------------------------------------
-- Public API (Runtime)
---------------------------------------------------------------

--- Check if a button is assigned as a modifier
--- This is called by Hijack module on every button press
--- Uses cached values for O(1) performance (no GetCVar calls)
---@param button string Button name (e.g., "PADLTRIGGER", "PADDUP", etc.)
---@return boolean isModifier True if button is assigned to Shift/Ctrl/Alt
function CVarManager:IsModifier(button)
    if not button then return false end
    
    return button == Cache.shift 
        or button == Cache.ctrl 
        or button == Cache.alt
end

---------------------------------------------------------------
-- Public API (User Actions)
---------------------------------------------------------------

--- Apply user's modifier bindings to CVars
--- Writes db.profile.modifiers to actual CVars and updates cache
function CVarManager:ApplyModifierBindings()
    local db = GetDB()
    
    -- Write profile settings to CVars
    WriteCVar("shift", db.profile.modifiers.shift)
    WriteCVar("ctrl", db.profile.modifiers.ctrl)
    WriteCVar("alt", db.profile.modifiers.alt)
    
    -- Update cache for runtime
    self:RefreshCache()
    
    -- Update modifier icons to reflect new assignments
    if addon.IconMapping then
        addon.IconMapping:UpdateModifierIcons()
    end
    
    CPAPI.DebugLog("CVarManager: Applied modifier bindings")
    print("|cff00ff00CPLight:|r Modifier bindings applied!")
end

--- Restore original CVars from first load
--- Reads db.global.originalCVars and writes back to game CVars
function CVarManager:RestoreOriginalCVars()
    local db = GetDB()
    
    if not db.global.originalCVars then
        print("|cffff0000CPLight:|r No original CVars saved!")
        return
    end
    
    -- Write original values back to CVars
    WriteCVar("shift", db.global.originalCVars.shift)
    WriteCVar("ctrl", db.global.originalCVars.ctrl)
    WriteCVar("alt", db.global.originalCVars.alt)
    
    -- Update profile to match
    db.profile.modifiers.shift = db.global.originalCVars.shift
    db.profile.modifiers.ctrl = db.global.originalCVars.ctrl
    db.profile.modifiers.alt = db.global.originalCVars.alt
    
    -- Update cache for runtime
    self:RefreshCache()
    
    -- Update modifier icons to reflect restored assignments
    if addon.IconMapping then
        addon.IconMapping:UpdateModifierIcons()
    end
    
    CPAPI.DebugLog("CVarManager: Restored original CVars")
    print("|cff00ff00CPLight:|r Original CVars restored!")
end

--- Get current cache values (for UI display)
---@return table cache {shift=string, ctrl=string, alt=string}
function CVarManager:GetCache()
    return {
        shift = Cache.shift,
        ctrl = Cache.ctrl,
        alt = Cache.alt,
    }
end

---------------------------------------------------------------
-- Export
---------------------------------------------------------------
_G.CPLightCVarManager = CVarManager
addon.CVarManager = CVarManager
