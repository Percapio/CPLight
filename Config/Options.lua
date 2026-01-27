---------------------------------------------------------------
-- CPLight Options Panel
---------------------------------------------------------------
-- AceConfig-based UI for modifier binding configuration
-- Appears in ESC → Interface → AddOns → CPLight

local ADDON_NAME, addon = ...
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

---------------------------------------------------------------
-- Helper Functions
---------------------------------------------------------------

--- Get valid pad options for a dropdown, excluding already-assigned pads
---@param currentModifier string "shift", "ctrl", or "alt" - the dropdown being edited
---@return table options Key-value pairs of button names
local function GetAvailablePads(currentModifier)
    local app = LibStub("AceAddon-3.0"):GetAddon("CPLight")
    local db = app.db
    local CVarManager = addon.CVarManager
    
    local options = {
        ["NONE"] = "None",
    }
    
    -- Get currently assigned pads from all modifiers
    local assigned = {}
    for mod, button in pairs(db.profile.modifiers) do
        if mod ~= currentModifier and button ~= "NONE" then
            assigned[button] = true
        end
    end
    
    -- Add unassigned pads to options
    for _, button in ipairs(CVarManager.ALLOWED_PADS) do
        if not assigned[button] then
            -- Format button name for display
            local displayName = button:gsub("PAD", ""):gsub("TRIGGER", " Trigger")
                                      :gsub("SHOULDER", " Shoulder"):gsub("STICK", " Stick")
                                      :gsub("L", "Left"):gsub("R", "Right")
            options[button] = displayName
        end
    end
    
    return options
end

--- Refresh all dropdowns to update available options
local function RefreshOptions()
    -- Force AceConfig to rebuild the options table
    AceConfig:RegisterOptionsTable("CPLight", CreateOptionsTable())
end

---------------------------------------------------------------
-- Options Table
---------------------------------------------------------------

--- Create the AceConfig options table
---@return table options The options table structure
function CreateOptionsTable()
    local app = LibStub("AceAddon-3.0"):GetAddon("CPLight")
    local db = app.db
    local CVarManager = addon.CVarManager
    
    return {
        type = "group",
        name = "CPLight Modifier Bindings",
        handler = CVarManager,
        args = {
            header = {
                type = "header",
                name = "Controller Modifier Mapping",
                order = 1,
            },
            description = {
                type = "description",
                name = "Map controller buttons to keyboard modifiers (Shift, Ctrl, Alt). Each button can only be assigned once.\n\n|cffff7f00Note:|r Changes take effect when you click 'Apply Changes'.",
                fontSize = "medium",
                order = 2,
            },
            spacer1 = {
                type = "description",
                name = " ",
                order = 3,
            },
            
            -- Shift Modifier
            shiftDropdown = {
                type = "select",
                name = "Shift Modifier",
                desc = "Controller button that acts as Shift key",
                order = 10,
                values = function() return GetAvailablePads("shift") end,
                get = function()
                    return db.profile.modifiers.shift
                end,
                set = function(info, val)
                    db.profile.modifiers.shift = val
                    RefreshOptions()
                end,
            },
            
            -- Ctrl Modifier
            ctrlDropdown = {
                type = "select",
                name = "Ctrl Modifier",
                desc = "Controller button that acts as Ctrl key",
                order = 20,
                values = function() return GetAvailablePads("ctrl") end,
                get = function()
                    return db.profile.modifiers.ctrl
                end,
                set = function(info, val)
                    db.profile.modifiers.ctrl = val
                    RefreshOptions()
                end,
            },
            
            -- Alt Modifier
            altDropdown = {
                type = "select",
                name = "Alt Modifier",
                desc = "Controller button that acts as Alt key",
                order = 30,
                values = function() return GetAvailablePads("alt") end,
                get = function()
                    return db.profile.modifiers.alt
                end,
                set = function(info, val)
                    db.profile.modifiers.alt = val
                    RefreshOptions()
                end,
            },
            
            spacer2 = {
                type = "description",
                name = " ",
                order = 40,
            },
            
            -- Apply Button
            applyButton = {
                type = "execute",
                name = "Apply Changes",
                desc = "Write your selections to game CVars (GamePadEmulateShift/Ctrl/Alt)",
                order = 50,
                func = function()
                    CVarManager:ApplyModifierBindings()
                end,
            },
            
            -- Restore Button
            restoreButton = {
                type = "execute",
                name = "Restore Original CVars",
                desc = "Restore CVars to their state before CPLight was installed",
                order = 60,
                func = function()
                    CVarManager:RestoreOriginalCVars()
                    RefreshOptions()
                end,
                confirm = true,
                confirmText = "This will restore your original GamePad modifier CVars. Continue?",
            },
            
            spacer3 = {
                type = "description",
                name = " ",
                order = 70,
            },
            
            -- Debug Mode
            debugModeToggle = {
                type = "toggle",
                name = "Debug Mode (restart required)",
                desc = "Enable detailed debug messages in chat. Useful for troubleshooting issues.\n\n|cffff7f00Note:|r A /reload or restart is required for this setting to take full effect.",
                order = 75,
                get = function()
                    return CPAPI.GetDebugMode()
                end,
                set = function(info, val)
                    CPAPI.SetDebugMode(val)
                end,
                width = "full",
            },
            
            spacer4 = {
                type = "description",
                name = " ",
                order = 77,
            },
            
            -- Current Status
            statusHeader = {
                type = "header",
                name = "Current Active Bindings",
                order = 80,
            },
            currentStatus = {
                type = "description",
                name = function()
                    local cache = CVarManager:GetCache()
                    local formatButton = function(btn)
                        if btn == "NONE" then return "|cff888888None|r" end
                        local name = btn:gsub("PAD", ""):gsub("TRIGGER", " Trigger")
                                        :gsub("SHOULDER", " Shoulder"):gsub("STICK", " Stick")
                                        :gsub("L", "Left"):gsub("R", "Right")
                        return "|cff00ff00" .. name .. "|r"
                    end
                    
                    return string.format(
                        "|cffffffffShift:|r %s\n|cffffffffCtrl:|r %s\n|cffffffffAlt:|r %s",
                        formatButton(cache.shift),
                        formatButton(cache.ctrl),
                        formatButton(cache.alt)
                    )
                end,
                fontSize = "medium",
                order = 90,
            },
        },
    }
end

---------------------------------------------------------------
-- Initialization
---------------------------------------------------------------

--- Register options panel with AceConfig
local function RegisterOptions()
    -- Register options table
    AceConfig:RegisterOptionsTable("CPLight", CreateOptionsTable())
    
    -- Add to Blizzard Interface Options
    AceConfigDialog:AddToBlizOptions("CPLight", "CPLight")
    
    CPAPI.DebugLog("Options panel registered")
end

---------------------------------------------------------------
-- Addon Lifecycle Hook
---------------------------------------------------------------

-- Register when addon fully loaded
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event)
    -- Initialize CVarManager first
    addon.CVarManager:Initialize()
    
    -- Then register options UI
    RegisterOptions()
end)
