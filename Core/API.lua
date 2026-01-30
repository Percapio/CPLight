---------------------------------------------------------------
-- CPLight Core API Utilities
---------------------------------------------------------------
-- Core API functions needed by CPLight components

local ADDON_NAME, ns = ...;

_G.CPAPI = _G.CPAPI or {};
local CPAPI = _G.CPAPI;

---------------------------------------------------------------
-- Polyfills
---------------------------------------------------------------
-- 2.5.5/10.0+ Compatibility for GetMouseFocus
if not _G.GetMouseFocus and _G.GetMouseFoci then
    _G.GetMouseFocus = function()
        local foci = _G.GetMouseFoci()
        return foci and foci[1]
    end
end

if not Mixin then
	function Mixin(t, ...)
		for i = 1, select('#', ...) do
			local mixin = select(i, ...);
			for k, v in pairs(mixin) do
				t[k] = v;
			end
		end
		return t;
	end
end

if not GenerateClosure then
	function GenerateClosure(f, ...)
		local args = { ... };
		local n = select('#', ...);
		return function(...)
			local newArgs = {};
			for i = 1, n do
				newArgs[i] = args[i];
			end
			for i = 1, select('#', ...) do
				newArgs[n + i] = select(i, ...);
			end
			return f(unpack(newArgs));
		end;
	end
end

---------------------------------------------------------------
-- Event Handler Creation
---------------------------------------------------------------
function CPAPI.CreateEventHandler(frameInfo, events, optionalStorage)
	local handler = CreateFrame(frameInfo[1], frameInfo[2], frameInfo[3], frameInfo[4] or '');
	local storage = optionalStorage or {};
	
	Mixin(handler, storage);
	
	if events then
		for _, event in ipairs(events) do
			handler:RegisterEvent(event);
		end
		handler:SetScript('OnEvent', function(self, event, ...)
			if self[event] then
				return self[event](self, ...);
			end
		end);
	end
	
	handler.Events = events;
	return handler;
end

---------------------------------------------------------------
-- Debug Mode
---------------------------------------------------------------
local DebugMode = false

--- Enable or disable debug logging
--- Saves setting to SavedVariables
---@param enabled boolean True to enable debug output
function CPAPI.SetDebugMode(enabled)
	DebugMode = enabled
	
	-- Save to database if available
	local app = LibStub("AceAddon-3.0"):GetAddon("CPLight", true)
	if app and app.db then
		app.db.profile.debugMode = enabled
	end
	
	if enabled then
		print('|cff0099ffCPLight:|r Debug mode ENABLED. Debug messages will be shown.')
	else
		print('|cff0099ffCPLight:|r Debug mode DISABLED.')
	end
end

--- Get current debug mode state
---@return boolean enabled True if debug mode is enabled
function CPAPI.GetDebugMode()
	return DebugMode
end

---------------------------------------------------------------
-- Log function (Production messages only)
---------------------------------------------------------------
function CPAPI.Log(msg, ...)
	if msg then
		print('|cff0099ffCPLight:|r ' .. msg:format(...));
	end
end

---------------------------------------------------------------
-- Debug Log function (Development/Debug messages)
---------------------------------------------------------------
function CPAPI.DebugLog(msg, ...)
	if DebugMode and msg then
		print('|cff888888CPLight [DEBUG]:|r ' .. msg:format(...));
	end
end

---------------------------------------------------------------
-- Register frame for unit events
---------------------------------------------------------------
function CPAPI.RegisterFrameForUnitEvents(frame, events, unit)
	if not events then return; end
	for _, event in ipairs(events) do
		frame:RegisterUnitEvent(event, unit);
	end
end
