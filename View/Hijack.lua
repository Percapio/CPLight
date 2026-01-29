---------------------------------------------------------------
-- SECTION 1: Module Setup & Constants
---------------------------------------------------------------
-- CPLight UI Navigation System
-- Secure state-driven UI navigation for TBC Anniversary (2.5.5)
-- Architecture: Separates secure action handling from insecure visuals
-- following WoW's Protected Action System requirements.

local ADDON_NAME, addon = ...
local Hijack = LibStub("AceAddon-3.0"):GetAddon("CPLight"):NewModule("Hijack", "AceEvent-3.0")
local NODE = LibStub('ConsolePortNode')
local NavGraph = _G.CPLightNavigationGraph
local CVarManager = nil  -- Initialized after Config module loads

---------------------------------------------------------------
-- Graph State Tracking (Smart Invalidation)
---------------------------------------------------------------
-- Track the state of the last successful graph build to enable reuse
Hijack.LastGraphState = {
    frameNames = {},  -- Array of frame names from last successful build
    nodeCount = 0,    -- Node count from last successful build
    buildTime = 0,    -- Timestamp of last build (for staleness check)
}

---------------------------------------------------------------
-- OPTIONAL ENHANCEMENT #1: Cache Hit Metrics (Bug 1 Improvement)
---------------------------------------------------------------
-- Track graph reuse performance for monitoring
-- TO DISABLE: Comment out this entire section
Hijack.GraphCacheStats = {
    hits = 0,    -- Graph reused without rebuild
    misses = 0,  -- Graph rebuilt due to changes
}
---------------------------------------------------------------

---------------------------------------------------------------
-- Event-Driven Rebuild Request State
---------------------------------------------------------------
-- Debouncing state to prevent rebuild storms when multiple frames change
Hijack.RebuildState = {
    pending = false,       -- Is a rebuild currently pending?
    hooksRegistered = false,  -- Have OnShow/OnHide hooks been set up?
    timerGeneration = 0,   -- Timer generation counter for stale callback detection
}

---------------------------------------------------------------
-- Frame Registry (Single Source of Truth)
---------------------------------------------------------------
-- Consolidated list of all navigable frames
-- Hooks are registered lazily when frames first appear (eliminates race conditions)

---------------------------------------------------------------
-- Hook Generation Counter (Memory Leak Prevention)
---------------------------------------------------------------
-- Global counter incremented each time hooks are registered
-- Prevents accumulation of stale hook closures over time
local HookGeneration = 0

local FRAMES = {
    -- Player Info
    "CharacterFrame", "SpellBookFrame", "PlayerTalentFrame",
    "HonorFrame", "SkillFrame", "ReputationFrame",
    -- Social & World
    "FriendsFrame", "GuildFrame", "WhoFrame", "WorldMapFrame", "LFGParentFrame",
    -- Interaction
    "GossipFrame", "QuestFrame", "MerchantFrame", "TaxiFrame",
    "QuestLogFrame", "TradeFrame", "BankFrame", "AuctionFrame", "MailFrame",
    -- Inventory (Bags 0-12)
    "ContainerFrame1", "ContainerFrame2", "ContainerFrame3", "ContainerFrame4",
    "ContainerFrame5", "ContainerFrame6", "ContainerFrame7", "ContainerFrame8",
    "ContainerFrame9", "ContainerFrame10", "ContainerFrame11", "ContainerFrame12",
    "ContainerFrame13",
    -- Management & Settings
    "GameMenuFrame", "InterfaceOptionsFrame", "VideoOptionsFrame","SettingsPanel",
    "AudioOptionsFrame", "KeyBindingFrame", "MacroFrame", "AddonList",
    -- Popups/Dialogs
    "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4", "ItemRefTooltip",
    -- Late-Loaded Addon Frames (hooked lazily when they first appear)
    "TradeSkillFrame", "InspectFrame"
}

---------------------------------------------------------------
-- Addon Frame Registry (Event-Driven Detection)
---------------------------------------------------------------
-- Maps addon names to their navigable frame names
-- Frames are added to FRAMES table dynamically when addon is detected
local ADDON_FRAMES = {
    Bagnon = {
        "BagnonInventory1",
    },
    Baganator = {
        "Baganator_CategoryViewBackpackViewFrameblizzard",
    },
}

---------------------------------------------------------------
-- Addon Frame Registration (Shared Logic)
---------------------------------------------------------------
-- Registers addon frames to the FRAMES table
-- Used by both ADDON_LOADED (late arrivals) and PLAYER_LOGIN (early birds)
local function RegisterAddonFrames(addonName)
    if not ADDON_FRAMES[addonName] then
        return
    end
    
    CPAPI.DebugLog('Detected bag addon: %s', addonName)
    
    -- Add addon frames to FRAMES registry (avoid duplicates)
    for _, frameName in ipairs(ADDON_FRAMES[addonName]) do
        local alreadyExists = false
        for _, existingFrame in ipairs(FRAMES) do
            if existingFrame == frameName then
                alreadyExists = true
                break
            end
        end
        
        if not alreadyExists then
            table.insert(FRAMES, frameName)
            CPAPI.DebugLog('Registered %s -> %s', addonName, frameName)
        end
    end
end

---------------------------------------------------------------
-- SECTION 2: Driver Frame & State Management
---------------------------------------------------------------

---------------------------------------------------------------
-- Secure State Driver (Main Control Frame)
---------------------------------------------------------------
-- This frame manages all secure state and handles combat lockdown
local Driver = CPAPI.CreateEventHandler(
    {'Frame', 'CPLightInputDriver', UIParent, 'SecureHandlerStateTemplate'},
    {
        'PLAYER_REGEN_DISABLED',  -- Enter combat
        'PLAYER_REGEN_ENABLED',   -- Leave combat
    },
    {
        Widgets = {},  -- Secure input widgets (PAD1, PAD2, D-Pad)
        NodeCache = {},  -- Cached node references (updated out of combat)
        CurrentIndex = 1,  -- Current focused node index
        ButtonStates = {},  -- Track button down/up states to prevent double navigation
    }
)

---------------------------------------------------------------
-- State Driver Setup
---------------------------------------------------------------
-- Monitor combat state to disable UI navigation during combat
RegisterStateDriver(Driver, 'combat', '[combat] true; nil')
Driver:SetAttribute('_onstate-combat', [[
    if newstate then
        -- Combat started: disable all input widgets
        control:ChildUpdate('combat', true)
    else
        -- Combat ended: allow navigation to re-enable
        control:ChildUpdate('combat', nil)
    end
]])

---------------------------------------------------------------
-- Secure Input Widget Management (Following ConsolePort Pattern)
---------------------------------------------------------------
function Driver:GetWidget(id, owner)
    id = tostring(id):upper()
    assert(not InCombatLockdown(), 'Cannot get input widget in combat.')
    
    local widget = self.Widgets[id]
    if not widget then
        widget = CreateFrame(
            'Button',
            ('CPLight_Input_%s'):format(id),
            self,
            'SecureActionButtonTemplate, SecureHandlerBaseTemplate'
        )
        widget:Hide()
        widget:SetAttribute('id', id)
        widget:SetAttribute('owner', owner)
        
        -- Register for Anniversary client click behavior
        if CPAPI.IsAnniVersion then
            widget:RegisterForClicks('AnyUp', 'AnyDown')
            widget:SetAttribute(CPAPI.ActionPressAndHold, true)
        end
        
        -- Combat lockdown handler
        widget:SetAttribute('_childupdate-combat', [[
            if message then
                self:SetAttribute('clickbutton', nil)
                self:Hide()
            end
        ]])
        
        self.Widgets[id] = widget
    end
    
    widget:SetAttribute('owner', owner)
    return widget
end

function Driver:ReleaseWidget(id)
    local widget = self.Widgets[id]
    if widget then
        widget:SetAttribute('clickbutton', nil)
        widget:SetAttribute(CPAPI.ActionTypeRelease, nil)
        widget:Hide()
    end
end

function Driver:ReleaseAll()
    for id, widget in pairs(self.Widgets) do
        self:ReleaseWidget(id)
    end
end

---------------------------------------------------------------
-- SECTION 3: Navigation Core
---------------------------------------------------------------

---------------------------------------------------------------
-- Navigation Logic (Using Pre-Calculated Graph)
---------------------------------------------------------------

---Validate the current navigation state before attempting navigation
---@return number|nil currentIndex The current node index, or nil if invalid
---@private
function Hijack:_ValidateNavigationState()
    if InCombatLockdown() then
        return nil
    end
    
    if not self.CurrentNode then
        return nil
    end
    
    if not NavGraph then
        return nil
    end
    
    local currentIndex = NavGraph:NodeToIndex(self.CurrentNode)
    if not currentIndex then
        -- Try to recover by focusing on first node
        local firstIndex = NavGraph:GetFirstNodeIndex()
        if firstIndex then
            local firstNode = NavGraph:IndexToNode(firstIndex)
            if firstNode then
                self:SetFocus(firstNode)
            end
        end
        return nil
    end
    
    return currentIndex
end

---Get and validate the target node in the specified direction
---Uses validated edges with NODE fallback for dynamic accuracy
---@param currentIndex number The current node index
---@param direction string The direction to navigate ("UP", "DOWN", "LEFT", "RIGHT")
---@return number|nil targetIndex The target node index, or nil if not found/invalid
---@private
function Hijack:_GetTargetNodeInDirection(currentIndex, direction)
	-- Get neighbor index from pre-calculated edges with real-time validation
	local edges = NavGraph:GetValidatedNodeEdges(currentIndex)
	if not edges then
		return nil
	end
	
	local dirKey = direction:lower()
	local targetIndex = edges[dirKey]
	
	if targetIndex then
		-- Found valid pre-calculated edge
		return targetIndex
	end
	
	-- FALLBACK: Pre-calculated edge is invalid, try NODE real-time navigation
	local NODE = LibStub('ConsolePortNode')
	if NODE and NODE.NavigateToBestCandidateV3 then
		local currentNode = NavGraph:IndexToNode(currentIndex)
		local graphData = NavGraph:GetGraph()
		local currentCacheItem = graphData.nodeCacheItems[currentIndex]
		
		if currentNode and currentCacheItem then
			-- Recalculate current position for accuracy
			local x, y = NavGraph:GetNodePosition(currentIndex)
			
			if x and y then
				local currentItem = {
					node = currentNode,
					super = currentCacheItem.super,
					x = x,
					y = y
				}
				
				local targetItem = NODE.NavigateToBestCandidateV3(currentItem, direction:upper())
				if targetItem and targetItem.node then
					-- Try to find this node in our graph
					local fallbackIndex = NavGraph:NodeToIndex(targetItem.node)
					if fallbackIndex then
						-- Found via fallback, but graph may need rebuild
						return fallbackIndex
					end
				end
				
				-- Fallback found nothing or node not in graph - invalidate
				NavGraph:InvalidateGraph()
			end
		end
	end
	
	return nil
end

---Navigate to an adjacent node in the specified direction
---Uses pre-calculated graph edges with real-time validation fallback
---@param direction string The direction to navigate ("UP", "DOWN", "LEFT", "RIGHT")
---@public
function Hijack:Navigate(direction)
    -- Validate navigation state
    local currentIndex = self:_ValidateNavigationState()
    if not currentIndex then
        return
    end
    
    
    -- Get target node in direction
    local targetIndex = self:_GetTargetNodeInDirection(currentIndex, direction)
    if not targetIndex then
        return
    end
    
    -- Focus on target node
    local targetNode = NavGraph:IndexToNode(targetIndex)
    if targetNode then
        self:SetFocus(targetNode)
    end
end

---------------------------------------------------------------
-- Focus Management (Insecure - Updates visuals and prepares secure click)
---------------------------------------------------------------

---Validate that a node can be focused
---@param node Frame The node to validate
---@return boolean valid True if the node can be focused
---@private
function Hijack:_ValidateNodeFocus(node)
    if not node then
        return false
    end
    
    if InCombatLockdown() then
        return false
    end
    
    if not node.IsVisible then
        return false
    end
    
    if not node:IsVisible() then
        return false
    end
    
    return true
end

---Configure secure input widgets to target the specified node
---@param node Frame The node to configure widgets for
---@return boolean success True if widgets were configured successfully
---@private
function Hijack:_ConfigureWidgetsForNode(node)
    assert(not InCombatLockdown(), 'Cannot configure widgets during combat')

    local widgetsConfigured = 0
    
    -- Update PAD1 (primary action) widget
    local clickWidget = Driver:GetWidget('PAD1', 'Hijack')
    if clickWidget then
        clickWidget:SetAttribute(CPAPI.ActionTypeRelease, 'click')
        clickWidget:SetAttribute('clickbutton', node)
        clickWidget:Show()
        widgetsConfigured = widgetsConfigured + 1
    else
    end
    
    -- Update PAD2 (right-click) widget
    local rightWidget = Driver:GetWidget('PAD2', 'Hijack')
    if rightWidget then
        rightWidget:SetAttribute(CPAPI.ActionTypeRelease, 'click')
        rightWidget:SetAttribute('clickbutton', node)
        rightWidget:Show()
        widgetsConfigured = widgetsConfigured + 1
    else
    end
    
    if widgetsConfigured == 0 then
        return false
    end
    
    return true
end

---Update visual feedback (gauntlet cursor and tooltip) for the focused node
---@param node Frame The focused node
---@private
function Hijack:_UpdateVisualFeedback(node)
    -- Update gauntlet visual
    self:UpdateGauntletPosition(node)
    
    -- Hide previous tooltip with ownership validation
    self:HideTooltip()
    
    -- Show tooltip
    self:ShowTooltipForNode(node)
end

---Set focus to a specific node, configuring widgets and visual feedback
---Updates CurrentNode, configures secure widgets, and updates gauntlet/tooltip
---@param node Frame The node to focus on
---@public
function Hijack:SetFocus(node)
    -- Validate node can be focused
    if not self:_ValidateNodeFocus(node) then
        return
    end
    
    -- Get node index for logging
    local nodeIndex = NavGraph and NavGraph:NodeToIndex(node)
    if nodeIndex then
    else
    end
    
    -- Update current node reference
    self.CurrentNode = node
    
    -- Configure secure widgets to target this node
    if not self:_ConfigureWidgetsForNode(node) then
    end
    
    -- Update visual feedback
    self:_UpdateVisualFeedback(node)
end

---------------------------------------------------------------
-- SECTION 5: Visual Feedback (Gauntlet & Tooltips)
---------------------------------------------------------------

---Hide the tooltip only if we own it, it's orphaned, or the owner is no longer visible
---Prevents hiding tooltips from other addons or active user interactions
---@public
function Hijack:HideTooltip()
    if not GameTooltip:IsShown() then
        return
    end
    
    local owner = GameTooltip:GetOwner()
    
    -- Hide if we own it
    if owner == self.CurrentNode then
        GameTooltip:Hide()
        return
    end
    
    -- Hide if owner is no longer visible (ghost tooltip detection)
    if owner and not owner:IsVisible() then
        GameTooltip:Hide()
        return
    end
    
    -- Hide if tooltip is orphaned (no owner)
    if not owner then
        GameTooltip:Hide()
        return
    end
end

---Show tooltip for the specified node by triggering its OnEnter script
---@param node Frame The node to show tooltip for
---@public
function Hijack:ShowTooltipForNode(node)
    if not node then return end
    
    if node:HasScript("OnEnter") then
        local onEnterScript = node:GetScript("OnEnter")
        if onEnterScript then
            pcall(onEnterScript, node)
        end
    elseif node:GetName() then
        GameTooltip:SetOwner(node, "ANCHOR_RIGHT")
        GameTooltip:SetText(node:GetName())
        GameTooltip:Show()
    end
end

---------------------------------------------------------------
-- Visual Gauntlet (Insecure - Cosmetic Only)
---------------------------------------------------------------

-- Gauntlet State Machine Constants
local GAUNTLET_STATE = {
    HIDDEN = 'hidden',
    POINTING = 'pointing',
    PRESSING = 'pressing',
}

-- Valid State Transitions
local VALID_TRANSITIONS = {
    [GAUNTLET_STATE.HIDDEN] = {
        [GAUNTLET_STATE.POINTING] = true,
    },
    [GAUNTLET_STATE.POINTING] = {
        [GAUNTLET_STATE.PRESSING] = true,
        [GAUNTLET_STATE.HIDDEN] = true,
    },
    [GAUNTLET_STATE.PRESSING] = {
        [GAUNTLET_STATE.POINTING] = true,
        [GAUNTLET_STATE.HIDDEN] = true,
    },
}

function Hijack:CreateGauntlet()
    local gauntlet = CreateFrame("Frame", "CPLightGauntlet", UIParent)
    gauntlet:SetFrameStrata("TOOLTIP")
    gauntlet:SetFrameLevel(200)
    gauntlet:SetSize(32, 32)
    gauntlet:Hide()
    
    local tex = gauntlet:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\CURSOR\\Point")
    gauntlet.tex = tex
    
    self.Gauntlet = gauntlet
end

function Hijack:UpdateGauntletPosition(node)
    if not self.Gauntlet or not node then return end
    
    -- Ensure gauntlet is in valid visible state (recovery from hidden state)
    if self.GauntletState == GAUNTLET_STATE.HIDDEN then
        self:SetGauntletState(GAUNTLET_STATE.POINTING)
    end
    
    local x, y = NODE.GetCenterScaled(node)
    if not x or not y then return end
    
    self.Gauntlet:ClearAllPoints()
    -- Position using scaled coordinates from NODE library
    -- Offset to center the pointer finger (top-left of texture) on the node center
    self.Gauntlet:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x - 4, y - 28)
    self.Gauntlet:Show()
end

---Set the gauntlet visual state with transition validation and state tracking
---@param newState string The target state ('hidden', 'pointing', or 'pressing')
function Hijack:SetGauntletState(newState)
    if not self.Gauntlet then return end
    
    local currentState = self.GauntletState or GAUNTLET_STATE.HIDDEN
    
    -- Validate transition (log warning but allow for recovery)
    if currentState ~= newState then
        if not VALID_TRANSITIONS[currentState] or not VALID_TRANSITIONS[currentState][newState] then
            CPAPI.DebugLog('WARNING: Invalid gauntlet transition: %s → %s', currentState, newState)
            -- Allow transition anyway (fail-open for recovery)
        end
    end
    
    -- Apply state
    if newState == GAUNTLET_STATE.HIDDEN then
        self.Gauntlet:Hide()
    elseif newState == GAUNTLET_STATE.POINTING then
        self.Gauntlet.tex:SetTexture("Interface\\CURSOR\\Point")
        self.Gauntlet:SetSize(32, 32)
        self.Gauntlet:Show()
    elseif newState == GAUNTLET_STATE.PRESSING then
        self.Gauntlet.tex:SetTexture("Interface\\CURSOR\\Interact")
        self.Gauntlet:SetSize(38, 38)
        self.Gauntlet:Show()
    end
    
    -- Track current state
    self.GauntletState = newState
end

---Show gauntlet in pointing state (convenience helper)
---@public
function Hijack:ShowGauntlet()
    self:SetGauntletState(GAUNTLET_STATE.POINTING)
end

---Hide gauntlet (convenience helper)
---@public
function Hijack:HideGauntlet()
    self:SetGauntletState(GAUNTLET_STATE.HIDDEN)
end

---Set gauntlet pressed/unpressed state (backward-compatible helper for button handlers)
---@param pressed boolean True for pressing state, false for pointing state
function Hijack:SetGauntletPressed(pressed)
    if pressed then
        self:SetGauntletState(GAUNTLET_STATE.PRESSING)
    else
        self:SetGauntletState(GAUNTLET_STATE.POINTING)
    end
end

---------------------------------------------------------------
-- SECTION 6: UI Frame Detection
---------------------------------------------------------------

---------------------------------------------------------------
-- Event-Driven Visibility Detection
---------------------------------------------------------------
-- Primary mechanism: OnShow/OnHide hooks + BAG_UPDATE events
-- Fallback: Slow polling for frames that don't fire events properly

---Request a graph rebuild with debouncing to prevent rebuild storms
---@private
local function RequestGraphRebuild()
    -- Early exit if rebuild already pending
    if Hijack.RebuildState.pending then
        return
    end
    
    -- Early exit if in combat (can't rebuild during lockdown)
    if InCombatLockdown() then
        return
    end
    
    -- Mark rebuild as pending and increment timer generation
    Hijack.RebuildState.pending = true
    Hijack.RebuildState.timerGeneration = Hijack.RebuildState.timerGeneration + 1
    local generation = Hijack.RebuildState.timerGeneration
    
    -- Debounce: wait 100ms to let multiple frame changes settle
    C_Timer.After(0.1, function()
        -- Check if this is a stale timer callback
        if generation ~= Hijack.RebuildState.timerGeneration then
            return
        end
        
        -- Re-check combat status (might have entered combat during delay)
        if InCombatLockdown() then
            Hijack.RebuildState.pending = false
            return
        end

        -- Clear pending flag
        Hijack.RebuildState.pending = false
        
        -- Check if any frames are visible
        local activeFrames, frameNames = Hijack:_CollectVisibleFrames()
        
        if #activeFrames > 0 then
            -- Frames visible: enable/refresh navigation
            if not Hijack.IsActive then
                Hijack:EnableNavigation()
            else
                -- Already active: check if frame set changed
                local frameSetChanged = not Hijack:_CanReuseGraph(frameNames)
                if frameSetChanged then
                    -- Save current focus to restore after refresh
                    Hijack.RestoreFocusNode = Hijack.CurrentNode
                    
                    NavGraph:InvalidateGraph()
                    Hijack:DisableNavigation()
                    Hijack:EnableNavigation()
                else
                end
            end
        else
            -- No frames visible: disable navigation
            if Hijack.IsActive then
                Hijack:DisableNavigation()
            end
        end
    end)
end

---Register OnShow/OnHide hooks for frames that exist at startup
---Late-loaded and on-demand frames are hooked lazily in _CollectVisibleFrames()
---@private
function Hijack:_RegisterVisibilityHooks()
    if self.RebuildState.hooksRegistered then
        return
    end
    
    local hooksRegistered = 0
    for _, frameName in ipairs(FRAMES) do
        local frame = _G[frameName]
        if frame and not frame.CPLight_HooksRegistered then
            -- Increment generation counter for new hook registration batch
            HookGeneration = HookGeneration + 1
            local currentGeneration = HookGeneration
            
            -- Use HookScript to avoid overwriting existing handlers
            frame:HookScript('OnShow', function()
                -- Only execute if this is the current generation (prevents stale hooks)
                if frame.CPLight_HookGeneration == currentGeneration and not InCombatLockdown() then
                    RequestGraphRebuild()
                end
            end)
            
            frame:HookScript('OnHide', function()
                -- Only execute if this is the current generation (prevents stale hooks)
                if frame.CPLight_HookGeneration == currentGeneration and not InCombatLockdown() then
                    RequestGraphRebuild()
                end
            end)
            
            frame.CPLight_HooksRegistered = true
            frame.CPLight_HookGeneration = currentGeneration
            hooksRegistered = hooksRegistered + 1
        end
    end
    
    self.RebuildState.hooksRegistered = true
end

---Update frame registry to hook newly-loaded frames from late-loaded addons
---Called when Blizzard addons load to catch frames that didn't exist at startup
---@private
function Hijack:_UpdateFrameRegistry()
    for _, frameName in ipairs(FRAMES) do
        local frame = _G[frameName]
        if frame and not frame.CPLight_HooksRegistered then
            -- Increment generation counter for new hook registration batch
            HookGeneration = HookGeneration + 1
            local currentGeneration = HookGeneration
            
            -- Hook newly-available frame
            frame:HookScript('OnShow', function()
                -- Only execute if this is the current generation (prevents stale hooks)
                if frame.CPLight_HookGeneration == currentGeneration and not InCombatLockdown() then
                    RequestGraphRebuild()
                end
            end)
            
            frame:HookScript('OnHide', function()
                -- Only execute if this is the current generation (prevents stale hooks)
                if frame.CPLight_HookGeneration == currentGeneration and not InCombatLockdown() then
                    RequestGraphRebuild()
                end
            end)
            
            frame.CPLight_HooksRegistered = true
            frame.CPLight_HookGeneration = currentGeneration
        end
    end
end



---Register game events for dynamic content changes
---@private
function Hijack:_RegisterGameEvents()
    -- BAG_UPDATE fires when bag contents change (items added/removed)
    self:RegisterEvent('BAG_UPDATE', function()
        if not InCombatLockdown() and Hijack.IsActive and NavGraph then
            RequestGraphRebuild()
        end
    end)
    
    -- ADDON_LOADED fires when Blizzard addons load (catches late-loaded frames)
    self:RegisterEvent('ADDON_LOADED', function(event, addonName)
        -- OPTIMIZATION: Instant exit if it's not a Blizzard UI module
        -- We don't care if "DBM" or "Details" loads late
        if not addonName:find("^Blizzard_") then
            return
        end
        
        -- If we are here, it's a Blizzard frame (Talents, Crafting, etc.)
        -- Check if it's one we care about, then rebuild
        if not InCombatLockdown() then
            Hijack:_UpdateFrameRegistry() -- Hook the new frame
            RequestGraphRebuild() -- Rebuild the graph
        end
    end)
    
end

---Check initial frame visibility state on startup
---@private
function Hijack:_CheckInitialVisibility()
    
    -- Wait 0.5s after hooks are registered to check initial state
    -- This ensures all frames are loaded and visible state is stable
    C_Timer.After(0.5, function()
        if InCombatLockdown() then
            return
        end
        
        local activeFrames = self:_CollectVisibleFrames()
        if #activeFrames > 0 then
            RequestGraphRebuild()
        else
        end
    end)
end

---------------------------------------------------------------
-- Fallback Polling (Safety Net)
---------------------------------------------------------------
-- Slow polling at 1-second intervals to catch edge cases where events don't fire
-- local VisibilityChecker = CreateFrame("Frame")
-- VisibilityChecker.timer = 0
-- VisibilityChecker:SetScript("OnUpdate", function(self, elapsed)
--     -- Skip checks during combat
--     if InCombatLockdown() then return end
    
--     -- Only check every 1 second (fallback, not primary mechanism)
--     self.timer = self.timer + elapsed
--     if self.timer < 1.0 then return end
--     self.timer = 0
    
--     -- Check for stale node (current node became invisible)
--     if Hijack.IsActive and Hijack.CurrentNode then
--         if not Hijack.CurrentNode:IsVisible() then
--             NavGraph:InvalidateGraph()
--             RequestGraphRebuild()
--         end
--     end
-- end)

---------------------------------------------------------------
-- SECTION 4: Widget & Binding Management
---------------------------------------------------------------

---Check if existing graph can be reused for current frame set
---@param currentFrameNames table Array of frame names currently visible
---@return boolean canReuse True if graph can be reused without rebuilding
---@private
function Hijack:_CanReuseGraph(currentFrameNames)
    -- Validate inputs
    if not currentFrameNames or #currentFrameNames == 0 then
        return false
    end
    
    -- Check if NavGraph is valid
    if not NavGraph or not NavGraph:IsValid() then
        return false
    end
    
    -- Check if we have previous state to compare against
    if not self.LastGraphState or not self.LastGraphState.frameNames or #self.LastGraphState.frameNames == 0 then
        return false
    end
    
    -- Compare frame counts first (fast check)
    if #currentFrameNames ~= #self.LastGraphState.frameNames then
        return false
    end
    
    -- Build lookup set from last build for O(n) comparison
    local lastFrameSet = {}
    for _, frameName in ipairs(self.LastGraphState.frameNames) do
        lastFrameSet[frameName] = true
    end
    
    -- Check if all current frames were in last build
    for _, frameName in ipairs(currentFrameNames) do
        if not lastFrameSet[frameName] then
            return false
        end
    end
    
    -- Verify node count hasn't changed (detects dynamic content changes)
    local currentNodeCount = NavGraph:GetNodeCount()
    if currentNodeCount ~= self.LastGraphState.nodeCount then
        return false
    end
    
    ---------------------------------------------------------------
    -- OPTIONAL ENHANCEMENT #2: Timestamp Validation (Bug 1 Improvement)
    ---------------------------------------------------------------
    -- Force rebuild if graph is too old (prevents stale graphs)
    -- TO DISABLE: Comment out this block
    local GRAPH_STALE_THRESHOLD = 30  -- seconds
    if self.LastGraphState.buildTime and GetTime then
        local graphAge = GetTime() - self.LastGraphState.buildTime
        if graphAge > GRAPH_STALE_THRESHOLD then
            CPAPI.DebugLog('ERROR: Navigation enable failed: Graph is stale (age=%d seconds)', graphAge)
            return false  -- Force rebuild for stale graphs
        end
    end
    ---------------------------------------------------------------
    
    -- All checks passed: graph can be reused
    return true
end

---Collect all visible frames from the FRAMES list
---Lazily registers OnShow/OnHide hooks for frames that weren't hooked at startup
---@return table frameObjects List of visible frame objects
---@return table frameNames List of visible frame names
---@private
function Hijack:_CollectVisibleFrames()
    local activeFrames = {}
    local frameNames = {}
    
    for _, frameName in ipairs(FRAMES) do
        local frame = _G[frameName]
        if frame then
            -- Lazy hook registration: hook frames that weren't available at startup
            -- Fixes race conditions with late-loaded addons and on-demand frames
            if not frame.CPLight_HooksRegistered then
                -- Increment generation counter for new hook registration batch
                HookGeneration = HookGeneration + 1
                local currentGeneration = HookGeneration
                
                frame:HookScript('OnShow', function()
                    -- Only execute if this is the current generation (prevents stale hooks)
                    if frame.CPLight_HookGeneration == currentGeneration and not InCombatLockdown() then
                        RequestGraphRebuild()
                    end
                end)
                
                frame:HookScript('OnHide', function()
                    -- Only execute if this is the current generation (prevents stale hooks)
                    if frame.CPLight_HookGeneration == currentGeneration and not InCombatLockdown() then
                        RequestGraphRebuild()
                    end
                end)
                
                frame.CPLight_HooksRegistered = true
                frame.CPLight_HookGeneration = currentGeneration
            end
            
            if frame:IsVisible() and frame:GetAlpha() > 0 then
                table.insert(activeFrames, frame)
                table.insert(frameNames, frameName)
            end
        end
    end
    
    return activeFrames, frameNames
end

---Build navigation graph and export it to the secure Driver frame
---@param frames table List of frame objects to build graph from
---@param frameNames table List of frame names corresponding to frame objects
---@return boolean success True if graph was built and exported successfully
---@private
function Hijack:_BuildAndExportGraph(frames, frameNames)
    if not NavGraph then
        return false
    end
    
    -- Build graph using NavigationGraph module
    local success = NavGraph:BuildGraph(frames)
    if not success then
        return false
    end
    
    local nodeCount = NavGraph:GetNodeCount()
    if not nodeCount or nodeCount == 0 then
        return false
    end
    
    
    -- Export graph to secure Driver frame
    if not NavGraph:ExportToSecureFrame(Driver) then
        return false
    end
    
    
    -- Save state for future reuse checks
    if frameNames and #frameNames > 0 then
        self.LastGraphState.frameNames = frameNames
        self.LastGraphState.nodeCount = nodeCount
        
        -- OPTIONAL: Save build timestamp (Bug 1 Enhancement #2)
        if GetTime then
            self.LastGraphState.buildTime = GetTime()
        end
    end
    
    return true
end

---------------------------------------------------------------
-- BUG 2 FIX: Rollback Helpers (Transaction-Style Error Handling)
---------------------------------------------------------------

---Clear bindings for a specific list of widgets
---@param widgetList table Array of widgets to clear bindings for
---@private
function Hijack:_ClearBindings(widgetList)
    if not widgetList then return end
    
    for _, widget in ipairs(widgetList) do
        if widget then
            ClearOverrideBindings(widget)
        end
    end
end

---Rollback partial enable state on failure
---Cleans up any widgets, bindings, and visual elements that may have been set up
---@private
function Hijack:_RollbackEnableState()
    -- Clear all bindings
    if Driver and Driver.Widgets then
        for id, widget in pairs(Driver.Widgets) do
            if widget then
                ClearOverrideBindings(widget)
            end
        end
    end
    
    -- Release all widgets
    if Driver and Driver.ReleaseAll then
        Driver:ReleaseAll()
    end
    
    -- Ensure IsActive is false
    self.IsActive = false
    
    -- Clear current node
    self.CurrentNode = nil
    
    -- Hide visual elements with proper state management
    self:HideGauntlet()
    
    -- Hide tooltip
    self:HideTooltip()
end

---------------------------------------------------------------

---Set up secure input widgets and bindings for navigation (with rollback on failure)
---@return table|nil widgets Table of configured widgets, or nil on failure
---@private
function Hijack:_SetupSecureWidgets()
    assert(not InCombatLockdown(), 'Cannot setup widgets during combat')

    local widgets = {}
    local successfulBindings = {}  -- Track for rollback
    
    -- Helper: Try to set up a widget, track success, cleanup on failure
    local function trySetupWidget(id, binding, mouseButton)
        -- Skip if this button is assigned as a modifier (Shift/Ctrl/Alt)
        if CVarManager and CVarManager:IsModifier(binding) then
            return nil  -- Not an error - just skip this button
        end
        
        local widget = Driver:GetWidget(id, 'Hijack')
        if not widget then
            -- Cleanup successful bindings on failure
            self:_ClearBindings(successfulBindings)
            return nil
        end
        
        SetOverrideBindingClick(widget, true, binding, widget:GetName(), mouseButton or 'LeftButton')
        table.insert(successfulBindings, widget)
        return widget
    end
    
    -- Set up PAD1 (primary action)
    widgets.pad1 = trySetupWidget('PAD1', 'PAD1', 'LeftButton')
    if not widgets.pad1 then
        return nil
    end
    
    -- Set up PAD2 (right-click action)
    widgets.pad2 = trySetupWidget('PAD2', 'PAD2', 'RightButton')
    if not widgets.pad2 then
        return nil
    end
    
    -- Set up D-Pad navigation widgets
    widgets.up = trySetupWidget('PADDUP', 'PADDUP')
    if not widgets.up then
        return nil
    end
    
    widgets.down = trySetupWidget('PADDDOWN', 'PADDDOWN')
    if not widgets.down then
        return nil
    end
    
    widgets.left = trySetupWidget('PADDLEFT', 'PADDLEFT')
    if not widgets.left then
        return nil
    end
    
    widgets.right = trySetupWidget('PADDRIGHT', 'PADDRIGHT')
    if not widgets.right then
        return nil
    end
    
    return widgets
end

---Set up PreClick handlers for D-pad navigation with visual feedback
---Configures insecure navigation callbacks for direction buttons
---@param widgets table Table of widgets to configure handlers for
---@private
function Hijack:_SetupNavigationHandlers(widgets)
    if not widgets then
        return
    end
    
    -- Set up D-Pad navigation handlers (temporary insecure solution)
    -- PreClick only fires on button DOWN, preventing double navigation on press+release
    if widgets.up then
        widgets.up:SetScript('PreClick', function(self, button, down)
            if down then Hijack:Navigate('UP') end
        end)
    end
    
    if widgets.down then
        widgets.down:SetScript('PreClick', function(self, button, down)
            if down then Hijack:Navigate('DOWN') end
        end)
    end
    
    if widgets.left then
        widgets.left:SetScript('PreClick', function(self, button, down)
            if down then Hijack:Navigate('LEFT') end
        end)
    end
    
    if widgets.right then
        widgets.right:SetScript('PreClick', function(self, button, down)
            if down then Hijack:Navigate('RIGHT') end
        end)
    end
    
    -- Set up visual feedback handlers for PAD1/PAD2 (only on down press)
    if widgets.pad1 then
        widgets.pad1:SetScript('PreClick', function(self, button, down)
            if down then Hijack:SetGauntletPressed(true) end
        end)
        widgets.pad1:SetScript('PostClick', function(self, button, down)
            Hijack:SetGauntletPressed(false)
        end)
    end
    
    if widgets.pad2 then
        widgets.pad2:SetScript('PreClick', function(self, button, down)
            if down then Hijack:SetGauntletPressed(true) end
        end)
        widgets.pad2:SetScript('PostClick', function(self, button, down)
            Hijack:SetGauntletPressed(false)
        end)
    end
    
end

---Enable UI navigation by building graph and setting up input handlers
---Uses transaction-style error handling with automatic rollback on failure
---Collects visible frames, builds/reuses graph, sets up widgets, and initializes focus
---@return boolean success True if navigation was enabled successfully
---@public
function Hijack:EnableNavigation()
    -- Pre-checks (no state mutation)
    if InCombatLockdown() then
        return false
    end
    
    if self.IsActive then
        return false
    end
    
    -- Collect visible frames
    local activeFrames, frameNames = self:_CollectVisibleFrames()
    if #activeFrames == 0 then
        return false
    end
    
    -- BUG 2 FIX: Transaction-style setup with automatic rollback on failure
    local success, errorMsg = pcall(function()
        -- Step 1: Build/export graph if needed
        local canReuseGraph = self:_CanReuseGraph(frameNames)
        
        if not canReuseGraph then
            local graphBuilt = self:_BuildAndExportGraph(activeFrames, frameNames)
            if not graphBuilt then
                error("Failed to build navigation graph")
            end
            
            -- OPTIONAL: Track cache miss (Bug 1 Enhancement #1)
            if self.GraphCacheStats then
                self.GraphCacheStats.misses = self.GraphCacheStats.misses + 1
            end
        else
            -- OPTIONAL: Track cache hit (Bug 1 Enhancement #1)
            if self.GraphCacheStats then
                self.GraphCacheStats.hits = self.GraphCacheStats.hits + 1
            end
        end
        
        -- Step 2: Validate first node exists
        local firstIndex = NavGraph:GetFirstNodeIndex()
        if not firstIndex then
            error("Graph has no nodes")
        end
        
        local firstNode = NavGraph:IndexToNode(firstIndex)
        if not firstNode then
            error("First node index has no node reference")
        end
        
        -- Step 3: Set up secure input widgets and bindings (with rollback)
        local widgets = self:_SetupSecureWidgets()
        if not widgets then
            error("Widget setup failed")
        end
        
        -- Step 4: Set up navigation handlers
        self:_SetupNavigationHandlers(widgets)
        
        -- Step 5: Mark as active (commit point)
        self.IsActive = true
        
        -- Step 6: Initial focus (or restore previous focus if refreshing)
        local focusNode = firstNode
        
        -- Check if we're restoring focus from a navigation refresh
        if self.RestoreFocusNode then
            -- Verify the saved node is still in the new graph
            local restoreIndex = NavGraph:NodeToIndex(self.RestoreFocusNode)
            if restoreIndex then
                focusNode = self.RestoreFocusNode
            end
            -- Clear restore state
            self.RestoreFocusNode = nil
        end
        
        self:SetFocus(focusNode)
        
        -- Step 7: Ensure gauntlet starts in correct state
        self:SetGauntletState(GAUNTLET_STATE.POINTING)
        
        return true
    end)
    
    if not success then
        -- Rollback on failure
        self:_RollbackEnableState()
        
        -- Log error (colored red for visibility)
        -- print("|cFFFF0000CPLight EnableNavigation failed:|r", errorMsg)
        
        return false
    end
    
    return true
end

---Disable UI navigation and clean up all widgets and state
---Releases widgets, clears bindings, hides visuals, and clears focus
---Graph is preserved for potential reuse on next enable
---@public
function Hijack:DisableNavigation()
    if InCombatLockdown() then
        return
    end
    
    if not self.IsActive then
        return
    end
    
    -- Get node count before invalidating graph
    local nodeCount = NavGraph and NavGraph:GetNodeCount() or 0
    
    self.IsActive = false
    
    -- Release all input widgets
    if Driver and Driver.ReleaseAll then
        Driver:ReleaseAll()
    end
    
    -- Clear bindings with validation
    local bindingsCleared = 0
    if Driver and Driver.Widgets then
        for id in pairs(Driver.Widgets) do
            local widget = Driver.Widgets[id]
            if widget then
                ClearOverrideBindings(widget)
                bindingsCleared = bindingsCleared + 1
            end
        end
    end
    
    -- Hide gauntlet with proper state transition
    self:HideGauntlet()
    
    -- Hide tooltip using centralized method with ownership validation
    self:HideTooltip()
    
    -- Extra ghost tooltip clear (ensures cleanup even if owner checks fail)
    if GameTooltip:IsShown() and GameTooltip:GetOwner() == self.CurrentNode then
        GameTooltip:Hide()
    end
    
    -- Clear state
    self.CurrentNode = nil
    
    -- Note: Graph is NOT invalidated here to enable reuse on next enable
    -- Graph will be invalidated only if:
    --   1. Frame set changes (detected in _CanReuseGraph)
    --   2. Node becomes invalid during navigation (_GetTargetNodeInDirection)
    --   3. Current node becomes invisible (VisibilityChecker)
    
end

---------------------------------------------------------------
-- SECTION 7: Combat Safety
---------------------------------------------------------------

---Handle combat start - disable navigation immediately
function Driver:PLAYER_REGEN_DISABLED()
    -- Entering combat: disable navigation immediately
    if Hijack.IsActive then
        Hijack:DisableNavigation()
    end
end

---Handle combat end - allow navigation to re-enable if UI open
function Driver:PLAYER_REGEN_ENABLED()
    -- Leaving combat: navigation will re-enable via visibility checker if UI is open
end

---------------------------------------------------------------
-- SECTION 8: Module Lifecycle
---------------------------------------------------------------

---Set up ghost tooltip clearing hooks for major UI close events
---Prevents tooltips from persisting after frames close (especially late-loaded UIs)
---@private
function Hijack:_SetupGhostTooltipClearing()
    local function ClearGhostTooltip()
        if not GameTooltip:IsShown() then
            return
        end
        
        local owner = GameTooltip:GetOwner()
        
        -- Clear if owner is invisible (ghost tooltip)
        if owner and not owner:IsVisible() then
            GameTooltip:Hide()
            return
        end
        
        -- Clear if tooltip is orphaned
        if not owner then
            GameTooltip:Hide()
            return
        end
    end
    
    -- Hook major panel close events
    hooksecurefunc("HideUIPanel", ClearGhostTooltip)
    hooksecurefunc("CloseAllWindows", ClearGhostTooltip)
    
    -- Specifically hook late-loaded frames that cause ghost tooltips
    if WorldMapFrame then
        WorldMapFrame:HookScript("OnHide", ClearGhostTooltip)
    end
    
    if TradeFrame then
        TradeFrame:HookScript("OnHide", ClearGhostTooltip)
    end
    
    -- Hook TradeSkillFrame if it exists (late-loaded)
    if TradeSkillFrame then
        TradeSkillFrame:HookScript("OnHide", ClearGhostTooltip)
    end
    
    CPAPI.DebugLog('Ghost tooltip clearing hooks registered')
end

---Handle addon loaded events to detect bag addons (Late Arrivals)
---Dynamically adds addon frames to the FRAMES registry
---@param event string Event name (ADDON_LOADED)
---@param addonName string Name of the addon that was loaded
---@private
function Hijack:ADDON_LOADED(event, addonName)
    RegisterAddonFrames(addonName)
end

---Handle player login to detect already-loaded bag addons (Early Birds)
---Checks for addons that loaded before CPLight (via OptionalDeps)
---@param event string Event name (PLAYER_LOGIN)
---@private
function Hijack:PLAYER_LOGIN(event)
    -- Check all supported addons to see if they're already loaded
    for supportedAddon, _ in pairs(ADDON_FRAMES) do
        if C_AddOns.IsAddOnLoaded(supportedAddon) then
            RegisterAddonFrames(supportedAddon)
        end
    end
end

---Initialize the Hijack module on addon enable
---Sets up gauntlet, registers visibility hooks and events, starts polling
---@public
function Hijack:OnEnable()
    -- Initialize CVarManager reference after Config module loads
    CVarManager = addon.CVarManager or _G.CPLightCVarManager
    
    self:CreateGauntlet()
    
    -- Register addon detection for bag addons
    self:RegisterEvent('ADDON_LOADED')  -- Late arrivals (load after us)
    self:RegisterEvent('PLAYER_LOGIN')   -- Early birds (loaded before us via OptionalDeps)
    
    -- Set up ghost tooltip clearing hooks
    self:_SetupGhostTooltipClearing()
    
    -- Register event-driven visibility detection
    self:_RegisterVisibilityHooks()
    self:_RegisterGameEvents()
    
    -- Check if any frames are already open
    self:_CheckInitialVisibility()
    
    -- Start fallback polling (safety net)
    -- VisibilityChecker:Show()
    
end

---Clean up the Hijack module on addon disable
---Disables navigation, stops polling, and resets hook state
---@public
function Hijack:OnDisable()
    self:DisableNavigation()
    -- VisibilityChecker:Hide()
    self.RebuildState.hooksRegistered = false
end

---------------------------------------------------------------
-- OPTIONAL ENHANCEMENT #1: Cache Statistics API (Bug 1 Improvement)
---------------------------------------------------------------
-- Get graph cache performance metrics
-- TO DISABLE: Comment out this entire function
-- function Hijack:GetGraphCacheStats()
--     if not self.GraphCacheStats then
--         return nil
--     end
    
--     local total = self.GraphCacheStats.hits + self.GraphCacheStats.misses
--     local hitRate = total > 0 and (self.GraphCacheStats.hits / total * 100) or 0
--     CPAPI.Log('Cache Stats: Hits=%d, Misses=%d, HitRate=%.1f%%', self.GraphCacheStats.hits, self.GraphCacheStats.misses, hitRate)

--     return {
--         hits = self.GraphCacheStats.hits,
--         misses = self.GraphCacheStats.misses,
--         total = total,
--         hitRate = string.format("%.1f%%", hitRate),
--     }
-- end
---------------------------------------------------------------
