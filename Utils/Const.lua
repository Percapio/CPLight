---------------------------------------------------------------
-- General
---------------------------------------------------------------
-- return true or nil (nil for dynamic table insertions)
CPAPI.IsAnniVersion       = WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC or nil;

---------------------------------------------------------------
-- Movement (Per STRUCTURE.md)
---------------------------------------------------------------
CPAPI.Movement = {
	AngleCombat    = 180,  -- Tank Mode: Always strafe, never turn (high angle)
	AngleTravel    = 45,   -- Travel Mode: Smooth interpolation, immediate turning
	CameraLocked   = 2,    -- TurnWithCamera: Lock during cast/vehicle
};

---------------------------------------------------------------
-- Button Actions
---------------------------------------------------------------
CPAPI.ActionTypeRelease   = 'typerelease';
CPAPI.ActionPressAndHold  = 'pressAndHoldAction';

---------------------------------------------------------------
-- Scrolling
---------------------------------------------------------------
CPAPI.ScrollStep          = 20;   -- Pixels per scroll tick
CPAPI.ScrollRepeatDelay   = 0.05; -- Seconds between scroll ticks when holding

---------------------------------------------------------------
-- For use with OnDataLoaded.
---------------------------------------------------------------
CPAPI.BurnAfterReading    = random(0001, 1337); -- Mark as garbage.
CPAPI.KeepMeForLater      = random(1338, 1992); -- Will be used again.
