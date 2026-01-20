---------------------------------------------------------------
-- Movement (TBC Anniversary 2.5.5)
---------------------------------------------------------------
-- Handles analog stick movement with Tank Mode (combat strafing)
-- and Travel Mode (360° freedom) logic.

local _, db = ...;

---------------------------------------------------------------
-- Constants (Per STRUCTURE.md)
---------------------------------------------------------------
-- Using CPAPI constants for project-wide consistency
local ANGLE_COMBAT = CPAPI.Movement.AngleCombat   -- 180: Always strafe (tank mode)
local ANGLE_TRAVEL = CPAPI.Movement.AngleTravel   -- 45: Smooth turning interpolation
local CAMERA_LOCKED = CPAPI.Movement.CameraLocked -- 2: Lock camera during cast/vehicle

---------------------------------------------------------------
-- Module Definition
---------------------------------------------------------------
local Movement = db:Register('Movement', CPAPI.CreateEventHandler(
	{'Frame', '$parentMovementHandler', CPLight, 'SecureHandlerAttributeTemplate'}, 
	{
		'UNIT_ENTERING_VEHICLE',
		'UNIT_EXITING_VEHICLE',
		'UNIT_SPELLCAST_CHANNEL_START',
		'UNIT_SPELLCAST_CHANNEL_STOP',
		'UNIT_SPELLCAST_EMPOWER_START',
		'UNIT_SPELLCAST_EMPOWER_STOP',
		'UNIT_SPELLCAST_START',
		'UNIT_SPELLCAST_STOP',
	}, 
	{
		Proxy = {
			AnalogMovement    = db.Data.Cvar('GamePadAnalogMovement'),
			StrafeAngleTravel = db.Data.Cvar('GamePadFaceMovementMaxAngle'),
			StrafeAngleCombat = db.Data.Cvar('GamePadFaceMovementMaxAngleCombat'),
			RunWalkThreshold  = db.Data.Cvar('GamePadRunThreshold'),
			TurnWithCamera    = db.Data.Cvar('GamePadTurnWithCamera'),
		},
		Attributes = {
			Travel = 'strafetravel',
			Combat = 'strafecombat',
		},
		State = {
			castingOverride = nil,   -- Stored TurnWithCamera value during casting
			vehicleOverride = nil,   -- Stored TurnWithCamera value in vehicle
		},
	}
));

---------------------------------------------------------------
-- Initialization
---------------------------------------------------------------
function Movement:OnDataLoaded()
	self:UpdateAnalogMovement()
	self:UpdateStrafeAngleTravel()
	self:UpdateStrafeAngleCombat()
	self:UpdateRunWalkThreshold()
	self:UpdateTurnWithCamera()
	self:UpdateConditionals()
	self:UnregisterAllEvents()
	CPAPI.RegisterFrameForUnitEvents(self, self.Events, 'player')
	return CPAPI.BurnAfterReading
end

---------------------------------------------------------------
-- Cvar Proxy Updates
---------------------------------------------------------------
function Movement:UpdateAnalogMovement()
	self.Proxy.AnalogMovement:Set(db('mvmtAnalog'))
end

function Movement:UpdateStrafeAngleTravel(value)
	self.Proxy.StrafeAngleTravel:Set(value or db('mvmtStrafeAngleTravel'))
end

function Movement:UpdateStrafeAngleCombat(value)
	self.Proxy.StrafeAngleCombat:Set(value or db('mvmtStrafeAngleCombat'))
end

function Movement:UpdateRunWalkThreshold(value)
	self.Proxy.RunWalkThreshold:Set(value or db('mvmtRunThreshold'))
end

function Movement:UpdateTurnWithCamera(value)
	self.Proxy.TurnWithCamera:Set(value or db('mvmtTurnWithCamera'))
end

-- Setting callbacks
db:RegisterCallback('Settings/mvmtAnalog',            Movement.UpdateAnalogMovement,    Movement)
db:RegisterCallback('Settings/mvmtStrafeAngleTravel', Movement.UpdateStrafeAngleTravel, Movement)
db:RegisterCallback('Settings/mvmtStrafeAngleCombat', Movement.UpdateStrafeAngleCombat, Movement)
db:RegisterCallback('Settings/mvmtRunThreshold',      Movement.UpdateRunWalkThreshold,  Movement)
db:RegisterCallback('Settings/mvmtTurnWithCamera',    Movement.UpdateTurnWithCamera,    Movement)

---------------------------------------------------------------
-- Attribute Drivers (Tank Mode / Travel Mode)
---------------------------------------------------------------
-- Uses secure RegisterAttributeDriver to switch between combat
-- strafing (angle=180) and travel freedom (angle=45) with zero taint.
-- [combat] = in combat use ANGLE_COMBAT (180), else use ANGLE_TRAVEL (45)
-- Lower angle = character faces movement direction (freedom)
-- Higher angle = character strafes without turning (tank mode)
---------------------------------------------------------------
function Movement:UpdateConditionals()
	-- Unified macro: [combat] 180; 45 (combat = strafe/tank, out of combat = smooth turning)
	local unifiedMacro = ('[combat] %d; %d'):format(ANGLE_COMBAT, ANGLE_TRAVEL)
	
	-- Allow database override for advanced users
	local customMacro = db('mvmtStrafeAngleMacro')
	local finalMacro = customMacro or unifiedMacro
	
	if self and self.Attributes then
		-- Drive both combat and travel cvars with same logic
		RegisterAttributeDriver(self, self.Attributes.Combat, finalMacro)
		RegisterAttributeDriver(self, self.Attributes.Travel, finalMacro)
	end
end

db:RegisterSafeCallback('Settings/mvmtStrafeAngleMacro', Movement.UpdateConditionals, Movement)

function Movement:OnAttributeChanged(attribute, value)
	local angleValue = tonumber(value)
	if attribute == self.Attributes.Travel then
		return self:UpdateStrafeAngleTravel(angleValue)
	elseif attribute == self.Attributes.Combat then
		return self:UpdateStrafeAngleCombat(angleValue)
	end
end

Movement:HookScript('OnAttributeChanged', Movement.OnAttributeChanged)

---------------------------------------------------------------
-- Casting & Vehicle State Management
---------------------------------------------------------------
-- Locks camera during casting/vehicles for precise targeting.
-- Uses Movement.State table for clean state tracking.
---------------------------------------------------------------
function Movement:UNIT_SPELLCAST_START()
	if self.State.vehicleOverride then return end
	if self.State.castingOverride == nil then
		self.State.castingOverride = db('mvmtTurnWithCamera')
		self:UpdateTurnWithCamera(CAMERA_LOCKED)
	end
end

function Movement:UNIT_SPELLCAST_STOP()
	if self.State.vehicleOverride then return end
	if self.State.castingOverride ~= nil then
		self:UpdateTurnWithCamera(self.State.castingOverride)
		self.State.castingOverride = nil
	end
end

function Movement:UNIT_ENTERING_VEHICLE()
	if self.State.vehicleOverride == nil then
		self:UNIT_SPELLCAST_STOP()  -- Clear casting override first
		self.State.vehicleOverride = db('mvmtTurnWithCamera')
		self:UpdateTurnWithCamera(CAMERA_LOCKED)
	end
end

function Movement:UNIT_EXITING_VEHICLE()
	if self.State.vehicleOverride ~= nil then
		self:UpdateTurnWithCamera(self.State.vehicleOverride)
		self.State.vehicleOverride = nil
	end
end

-- Event aliases (channeling/empowering use same logic as casting)
Movement.UNIT_SPELLCAST_CHANNEL_START = Movement.UNIT_SPELLCAST_START
Movement.UNIT_SPELLCAST_CHANNEL_STOP  = Movement.UNIT_SPELLCAST_STOP
Movement.UNIT_SPELLCAST_EMPOWER_START = Movement.UNIT_SPELLCAST_START
Movement.UNIT_SPELLCAST_EMPOWER_STOP  = Movement.UNIT_SPELLCAST_STOP
