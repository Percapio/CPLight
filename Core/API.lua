---------------------------------------------------------------
-- CPLight Core API Utilities
---------------------------------------------------------------
-- Core API functions needed by CPLight components

local ADDON_NAME, ns = ...;

_G.CPAPI = _G.CPAPI or {};
local CPAPI = _G.CPAPI;

-- Constants
CPAPI.ActionTypeRelease = 'type'; -- Default to standard action type
CPAPI.RaidCursorUnit    = 'raidcursorunit';
CPAPI.KeepMeForLater    = true;

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
-- Math Helpers
---------------------------------------------------------------
function CPAPI.Clamp(v, min, max)
    if v < min then return min; end
    if v > max then return max; end
    return v;
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

function CPAPI.EventHandler(frame, events)
	local mixin = {};
	if events then
		for _, event in ipairs(events) do
			frame:RegisterEvent(event);
		end
		frame:SetScript('OnEvent', function(self, event, ...)
			if self[event] then
				return self[event](self, ...);
			end
		end);
	end
	return mixin;
end

---------------------------------------------------------------
-- Log function
---------------------------------------------------------------
function CPAPI.Log(msg, ...)
	if msg then
		print('|cff0099ffCPLight:|r ' .. msg:format(...));
	end
end

---------------------------------------------------------------
-- Scrub function (sanitize values)
---------------------------------------------------------------
function CPAPI.Scrub(value, default)
	return value or default;
end

---------------------------------------------------------------
-- Debounce function
---------------------------------------------------------------
function CPAPI.Debounce(func, owner, collector, delay)
	delay = delay or 0.25;
	local timer = nil;
	
	local debounced = setmetatable({
		Cancel = function()
			if timer then timer:Cancel(); timer = nil; end
		end
	}, {
		__call = function(self, ...)
			local args = { ... };
			local n = select('#', ...);
			if timer then timer:Cancel(); end
			timer = C_Timer.After(delay, function()
				func(owner, collector, unpack(args, 1, n));
				timer = nil;
			end);
		end
	});
	return debounced;
end

---------------------------------------------------------------
-- Spline/Animation helpers (stubs for UI)
---------------------------------------------------------------
function CPAPI.Start(obj)
	-- Initialize UI object
	return obj;
end

---------------------------------------------------------------
-- Secure script wrapper
---------------------------------------------------------------
function CPAPI.ConvertSecureBody(body)
	return body;
end

---------------------------------------------------------------
-- Navigation helper
---------------------------------------------------------------
function CPAPI.Nav(frameName)
	return _G[frameName] or CreateFrame('Frame', frameName, UIParent, 'SecureHandlerStateTemplate');
end

---------------------------------------------------------------
-- Table utilities
---------------------------------------------------------------
if not CPAPI.table then
	CPAPI.table = {
		merge = function(a, b)
			if b then
				for k, v in pairs(b) do a[k] = v; end
			end
			return a;
		end,
		copy = function(tbl)
			if not tbl then return {}; end
			local new = {};
			for k, v in pairs(tbl) do
				new[k] = (type(v) == 'table') and CPAPI.table.copy(v) or v;
			end
			return new;
		end,
		compare = function(a, b)
			if type(a) ~= type(b) then return false; end
			if type(a) ~= 'table' then return a == b; end
			for k in pairs(a) do
				if not CPAPI.table.compare(a[k], b[k]) then return false; end
			end
			for k in pairs(b) do
				if not CPAPI.table.compare(a[k], b[k]) then return false; end
			end
			return true;
		end,
		spairs = function(tbl)
			local keys = {};
			for k in pairs(tbl) do table.insert(keys, k); end
			table.sort(keys);
			local i = 0;
			return function()
				i = i + 1;
				if keys[i] then return keys[i], tbl[keys[i]]; end
			end;
		end,
	};
end

---------------------------------------------------------------
-- Spell info caching
---------------------------------------------------------------
function CPAPI.GetSpellInfo(spellID)
	if not spellID then return {}; end
	
	-- Modern API
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(spellID);
		if info then
			return {
				name = info.name,
				iconID = info.iconID,
			};
		end
	-- Legacy API
	elseif _G.GetSpellInfo then
		local name, _, icon = _G.GetSpellInfo(spellID);
		if name then
			return {
				name = name,
				iconID = icon,
			};
		end
	end
	return {};
end

---------------------------------------------------------------
-- Spell damage type check
---------------------------------------------------------------
function CPAPI.IsSpellHarmful(spellName)
	if not spellName then return false; end
	if C_Spell and C_Spell.IsSpellHarmful then
		return C_Spell.IsSpellHarmful(spellName);
	elseif _G.IsHarmfulSpell then
		return _G.IsHarmfulSpell(spellName);
	end
	return false;
end

function CPAPI.IsSpellHelpful(spellName)
	if not spellName then return false; end
	if C_Spell and C_Spell.IsSpellHelpful then
		return C_Spell.IsSpellHelpful(spellName);
	elseif _G.IsHelpfulSpell then
		return _G.IsHelpfulSpell(spellName);
	end
	return false;
end

---------------------------------------------------------------
-- Unit info helpers
---------------------------------------------------------------
function CPAPI.GetCharacterMetadata()
	local specIndex = GetSpecialization and GetSpecialization() or 1;
	if specIndex then
		local specID, specName, _, icon = 0, 'Unknown', 1, 136031;
		if GetSpecializationInfo then
			specID, specName, _, icon = GetSpecializationInfo(specIndex);
		end
		return specID, specName, specIndex, icon;
	end
	return 0, 'Unknown', 1, 136031;
end

---------------------------------------------------------------
-- Flags helper
---------------------------------------------------------------
function CPAPI.CreateFlags(...)
	local flags = {};
	for i = 1, select('#', ...) do
		flags[select(i, ...)] = true;
	end
	return flags;
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

---------------------------------------------------------------
-- Proxy object helper
---------------------------------------------------------------
function CPAPI.Proxy(tbl, env)
	return setmetatable({}, {
		__index = function(_, key)
			return tbl[key] or env[key];
		end,
		__newindex = function(_, key, value)
			tbl[key] = value;
		end,
	});
end

---------------------------------------------------------------
-- Variant support (CVars, etc)
---------------------------------------------------------------
function CPAPI.GetVariant(name)
	-- Stub for variant system
	return {
		Set = function() end,
		Get = function() return 0; end,
	};
end
