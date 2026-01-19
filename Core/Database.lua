---------------------------------------------------------------
-- CPLight Core Database System
---------------------------------------------------------------
-- Minimal database system for CPLight addon
-- Provides db:Register() and basic data access

local CPLight = _G.CPLight or CreateFrame('Frame', 'CPLight', UIParent);
_G.CPLight = CPLight;

local ADDON_NAME, ns = ...;
_G.CPAPI = _G.CPAPI or {};
local db = ns;

---------------------------------------------------------------
-- Core database object
---------------------------------------------------------------
local Database = {};
Database.__index = Database;

function Database:Register(id, obj)
	if not self.Registry then self.Registry = {}; end
	self.Registry[id] = obj;
	-- Expose directly on the DB object for dot-notation access (db.Pager)
	self[id] = obj;
	return obj;
end

function Database:Get(id)
	return self.Registry and self.Registry[id];
end

function Database:TriggerEvent(event, ...)
	if not self.EventCallbacks then self.EventCallbacks = {}; end
	local callbacks = self.EventCallbacks[event];
	if callbacks then
		for callback in pairs(callbacks) do
			callback(self, ...);
		end
	end
end

function Database:RegisterCallback(event, callback, owner)
	if not self.EventCallbacks then self.EventCallbacks = {}; end
	if not self.EventCallbacks[event] then self.EventCallbacks[event] = {}; end
	self.EventCallbacks[event][GenerateClosure(callback, owner)] = true;
end

function Database:RegisterSafeCallback(event, callback, owner)
	-- Safe callbacks are just normal callbacks for now
	self:RegisterCallback(event, callback, owner);
end

function Database:RegisterCallbacks(callback, owner, ...)
	for i = 1, select('#', ...) do
		self:RegisterCallback(select(i, ...), callback, owner);
	end
end

function Database:RegisterSafeCallbacks(callback, owner, ...)
	for i = 1, select('#', ...) do
		self:RegisterSafeCallback(select(i, ...), callback, owner);
	end
end

function Database:__call(key, value)
	-- Simple variable lookup/setter
	if not self.Variables then self.Variables = {}; end
	if value ~= nil then
		self.Variables[key] = value;
	end
	return self.Variables[key];
end

---------------------------------------------------------------
-- Configuration defaults
---------------------------------------------------------------
function Database:InitDefaults()
	if not self.Variables then self.Variables = {}; end
	
	-- Tank Movement: Use MoveForwardStart for forward strafe (true = tank mode)
	if self.Variables.tankMovement == nil then
		self.Variables.tankMovement = false;
	end
end

---------------------------------------------------------------
-- Initialize database
---------------------------------------------------------------
-- Treat the namespace itself as the database object
local DBInstance = ns;
for k, v in pairs(Database) do
	DBInstance[k] = v;
end

-- Allow calling the namespace table directly
setmetatable(DBInstance, {
	__call = Database.__call,
});

-- Backward compatibility for files expecting ns.db
ns.db = DBInstance;

-- Ensure Registry exists
if not DBInstance.Registry then DBInstance.Registry = {}; end

-- Initialize defaults
DBInstance:InitDefaults();

return DBInstance;
