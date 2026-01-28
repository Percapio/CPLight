---------------------------------------------------------------
-- Controller Icon Mapping
---------------------------------------------------------------
-- Replaces default keybind text (e.g., "PAD1") with controller icons
-- Only runs once per installation on WoW TBC Anniversary (2.5.5)

local ADDON_NAME, addon = ...

local IconMapping = {}
addon.IconMapping = IconMapping

---------------------------------------------------------------
-- Original Key Storage
---------------------------------------------------------------
local OriginalKeys = {}

---------------------------------------------------------------
-- Texture Base Path
---------------------------------------------------------------
local TEXTURE_PATH = "Interface\\AddOns\\CPLight\\Media\\XboxSeries\\"

---------------------------------------------------------------
-- Icon Mapping Table
---------------------------------------------------------------
local ICON_MAPPING = {
    -- Main Buttons
    ["PAD1"] = "XboxSeriesX_A",      -- A Button
    ["PAD2"] = "XboxSeriesX_B",      -- B Button
    ["PAD3"] = "XboxSeriesX_X",      -- X Button
    ["PAD4"] = "XboxSeriesX_Y",      -- Y Button
    
    -- Shoulders & Triggers
    ["PADLSHOULDER"] = "XboxSeriesX_LB",  -- Left Bumper
    ["PADRSHOULDER"] = "XboxSeriesX_RB",  -- Right Bumper
    ["PADLTRIGGER"]  = "XboxSeriesX_LT",  -- Left Trigger
    ["PADRTRIGGER"]  = "XboxSeriesX_RT",  -- Right Trigger
    
    -- D-Pad
    ["PADDUP"]    = "XboxSeriesX_Dpad_Up",
    ["PADDDOWN"]  = "XboxSeriesX_Dpad_Down",
    ["PADDLEFT"]  = "XboxSeriesX_Dpad_Left",
    ["PADDRIGHT"] = "XboxSeriesX_Dpad_Right",
    
    -- Sticks
    ["PADLSTICK"] = "XboxSeriesX_Left_Stick_Click",
    ["PADRSTICK"] = "XboxSeriesX_Right_Stick_Click",
}

---------------------------------------------------------------
-- Apply Controller Icons
---------------------------------------------------------------
--- Apply controller icons to global KEY_* strings
--- Only runs once per installation (tracked in SavedVariables)
function IconMapping:Apply()
    local app = LibStub("AceAddon-3.0"):GetAddon("CPLight")
    
    -- Check if icons are already applied by inspecting KEY_PAD3
    -- If it contains our XboxSeriesX_X texture, icons are already loaded
    if _G["KEY_PAD3"] and string.find(_G["KEY_PAD3"], "XboxSeriesX_X") then
        CPAPI.DebugLog("Controller icons already applied (detected in KEY_PAD3), skipping")
        return
    end
    
    -- Save originals before overwriting
    for key, textureName in pairs(ICON_MAPPING) do
        local globalName = "KEY_"..key
        OriginalKeys[key] = _G[globalName]
        
        -- Apply icon: |Tpath:width:height|t
        local texturePath = TEXTURE_PATH .. textureName
        _G[globalName] = "|T"..texturePath..":16:16|t"
    end
    
    -- Apply modifier icons (reuse controller button icons from CVarManager)
    self:UpdateModifierIcons()
    
    CPAPI.DebugLog("Controller icons applied successfully")
end

---------------------------------------------------------------
-- Update Modifier Icons
---------------------------------------------------------------
--- Dynamically sets modifier abbreviations based on CVarManager assignments
--- If user assigns PADLSHOULDER as Shift, Shift abbreviation shows shoulder icon
function IconMapping:UpdateModifierIcons()
    local CVarManager = addon.CVarManager
    if not CVarManager then
        CPAPI.DebugLog("CVarManager not available, using default modifier icons")
        return
    end
    
    local cache = CVarManager:GetCache()
    
    -- Map modifier type to its assigned button
    local modifiers = {
        shift = cache.shift,
        ctrl = cache.ctrl,
        alt = cache.alt,
    }
    
    for modType, button in pairs(modifiers) do
        local globalName = "KEY_ABBREVIATED_"..modType:upper()
        
        if button and button ~= "NONE" and ICON_MAPPING[button] then
            -- Use controller icon for modifier
            local textureName = ICON_MAPPING[button]
            local texturePath = TEXTURE_PATH .. textureName
            _G[globalName] = "|T"..texturePath..":14:14|t"
            CPAPI.DebugLog("Modifier %s icon set to %s (%s)", modType, button, textureName)
        else
            -- Fallback: Compact text abbreviation with color
            local abbreviations = {
                shift = "|cFFFFFF00Sh|r-",
                ctrl = "|cFF00CCFFCt|r-",
                alt = "|cFFFF8800Al|r-",
            }
            _G[globalName] = abbreviations[modType]
        end
    end
end

---------------------------------------------------------------
-- Restore Original Keys
---------------------------------------------------------------
--- Restore original KEY_* values and reset SavedVariables flag
function IconMapping:Restore()
    for key, original in pairs(OriginalKeys) do
        _G["KEY_"..key] = original
    end
    
    -- Restore modifier abbreviations to default
    _G["KEY_ABBREVIATED_SHIFT"] = "Sh"
    _G["KEY_ABBREVIATED_CTRL"] = "Ct"
    _G["KEY_ABBREVIATED_ALT"] = "Al"
    
    local app = LibStub("AceAddon-3.0"):GetAddon("CPLight")
    
    CPAPI.Log("Controller icons restored to original values")
end

---------------------------------------------------------------
-- Initialization
---------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event)
    -- Only run on TBC Anniversary (2.5.5)
    if not CPAPI.IsAnniVersion then
        CPAPI.DebugLog("Controller icons skipped: Not TBC Anniversary client")
        return
    end
    
    -- Apply icons (one-time check handled internally)
    IconMapping:Apply()
end)
