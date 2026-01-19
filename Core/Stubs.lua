---------------------------------------------------------------
-- CPLight Stubs for Unsupported Features
---------------------------------------------------------------
-- Provides minimal stubs for features CPLight doesn't fully support

local _, db = ...;
-- Ensure we are working with the correct DB object
if not db.Register and db.db then db = db.db; end

---------------------------------------------------------------
-- Pager stub (minimal action bar paging support)
---------------------------------------------------------------
local Pager = {
	RegisterHeader = function(self, frame)
		return frame;
	end,
};
db:Register('Pager', Pager);

---------------------------------------------------------------
-- Nav helper for creating secure frames
---------------------------------------------------------------
if not CPAPI.Nav then
	function CPAPI.Nav(frameName)
		return _G[frameName] or CreateFrame('Frame', frameName, UIParent, 'SecureHandlerStateTemplate');
	end
end
-- Alias for database usage (Raid.lua uses db.Nav)
db.Nav = CPAPI.Nav;

---------------------------------------------------------------
-- Frame creation for Raid cursor display
---------------------------------------------------------------
-- These stubs prevent errors when Raid.lua tries to access frame components
-- CAUTION: Requires Templates\Cursor.xml to be loaded first!

if not Mouse then
	local function CreateStub(name, parent, template)
		return CreateFrame('Button', name, parent, template); 
	end

	-- Main Cursor (Secure Base)
	_G.CPLightRaidCursor = CreateFrame('Button', 'CPLightRaidCursor', UIParent, 'SecureHandlerStateTemplate, SecureActionButtonTemplate');
	_G.CPLightRaidCursor:RegisterForClicks('AnyDown', 'AnyUp');

	-- Visual/Functional Components
	local cursor = _G.CPLightRaidCursor;
	
	cursor.Toggle = CreateStub('CPLightRaidCursorToggle', cursor, 'SecureActionButtonTemplate');
	cursor.SetTarget = CreateStub('CPLightRaidCursorSetTarget', cursor, 'SecureActionButtonTemplate');
	cursor.SetFocus = CreateStub('CPLightRaidCursorSetFocus', cursor, 'SecureActionButtonTemplate');
	
	cursor.Display = CreateFrame('Frame', 'CPLightRaidCursorDisplay', cursor);
	
	-- Note: template must match XML definition
	cursor.Display.UnitInformation = CreateFrame('Frame', 'CPLightRaidCursorUnitInfo', cursor.Display, 'CPLightRaidCursorUnitInfoTemplate');
	
	-- Group frame (for Animations/Scaling)
	cursor.Group = CreateFrame('Frame', 'CPLightRaidCursorGroup', cursor.Display);
end

---------------------------------------------------------------
-- Animation stubs
---------------------------------------------------------------
if not CPAPI.Alpha then
	CPAPI.Alpha = {
		Fader = {
			In = function(widget, duration, from, to)
				local alpha = widget:GetAlpha() or from or 0;
				widget:SetAlpha(to or 1);
			end,
			Out = function(widget, duration, from, to)
				local alpha = widget:GetAlpha() or from or 1;
				widget:SetAlpha(to or 0);
			end,
		},
		Flash = function(widget, duration, flashDuration, flashAlpha, keepFlashing, delay, startAlpha)
			widget:SetAlpha(startAlpha or 1);
		end,
	};
end
