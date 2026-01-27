---------------------------------------------------------------
-- CPLight Core
---------------------------------------------------------------
-- Solid foundation for TBC Anniversary
-- Handles: Global Object, DB Init, Key Bindings, State Drivers

local ADDON_NAME, ns = ...

-- 1. Global Frame Object (For XML parenting / CreateFrame)
if not _G.CPLight or type(_G.CPLight) ~= "table" or not _G.CPLight.GetStartPoint then
    _G.CPLight = CreateFrame("Frame", "CPLight", UIParent)
end

-- 2. AceAddon Logic Object
-- We use a separate name "CPLight_Core" or just manage the object reference manually
-- to avoid overwriting the Global CPLight frame with a table.
local App = LibStub("AceAddon-3.0"):NewAddon("CPLight", "AceEvent-3.0")

-- 3. Data Initialization (Fix for Movement.lua db.Data nil error)
-- Movement.lua uses 'local _, db = ...' so it sees 'ns'. We must attach Data to 'ns'.
ns.Data = ns.Data or {}

local db = ns

---------------------------------------------------------------
-- CVar Helper (Legacy/Retail Compatibility)
---------------------------------------------------------------
if not db.Data.Cvar then
    db.Data.Cvar = function(name)
        return {
            Get = function() 
                if C_CVar and C_CVar.GetCVar then
                    return C_CVar.GetCVar(name) or 0
                elseif GetCVar then
                    return GetCVar(name) or 0
                end
                return 0
            end,
            Set = function(self, val)
                if val == nil then return end
                if type(val) == 'boolean' then val = val and '1' or '0' end
                
                if C_CVar and C_CVar.SetCVar then
                    C_CVar.SetCVar(name, val)
                elseif SetCVar then
                    SetCVar(name, val)
                end
            end
        }
    end
end

---------------------------------------------------------------
-- Database Defaults
---------------------------------------------------------------
local defaults = {
    global = {
        originalCVars = nil,  -- Saved on first load: {shift="NONE", ctrl="NONE", alt="NONE"}
    },
    profile = {
        modifiers = {
            shift = "NONE",
            ctrl = "NONE",
            alt = "NONE",
        },
        debugMode = false,  -- Debug logging toggle
    },
}

---------------------------------------------------------------
-- Lifecycle Methods
---------------------------------------------------------------
function App:OnInitialize()
    -- Initialize AceDB with SavedVariables
    self.db = LibStub("AceDB-3.0"):New("CPLightDB", defaults, true)
    
    CPAPI.DebugLog('System Initialized (Ace3 + AceDB).')
end

function App:OnEnable()
    -- Triggers when player logs in
    
    -- Initialize debug mode from SavedVariables
    if self.db.profile.debugMode then
        CPAPI.SetDebugMode(true)
    end
    
    CPAPI.Log('System Enabled.')
    
    -- Legacy Module Loader Notification
    if ns.db and ns.db.Registry then
        for name, module in pairs(ns.db.Registry) do
            if type(module) == 'table' and module.OnDataLoaded then
                pcall(module.OnDataLoaded, module)
            end
        end
    end
end
