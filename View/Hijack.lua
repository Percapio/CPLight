---------------------------------------------------------------
-- CPLight UI Navigation System
---------------------------------------------------------------
-- Secure state-driven UI navigation for TBC Anniversary (2.5.5)
-- Architecture: Separates secure action handling from insecure visuals
-- following WoW's Protected Action System requirements.

local ADDON_NAME, addon = ...
local Hijack = LibStub("AceAddon-3.0"):GetAddon("CPLight"):NewModule("Hijack", "AceEvent-3.0")
local NODE = LibStub('ConsolePortNode')
local NavGraph = _G.CPLightNavigationGraph

---------------------------------------------------------------
-- Graph State Tracking (Smart Invalidation)
---------------------------------------------------------------
-- Track the state of the last successful graph build to enable reuse
Hijack.LastGraphState = {
    frameNames = {},  -- Array of frame names from last successful build
    nodeCount = 0,    -- Node count from last successful build
}

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
-- Constants
---------------------------------------------------------------
local ALLOWED_FRAMES = {
    -- Player Info
    "CharacterFrame", "SpellBookFrame", "PlayerTalentFrame",
    "HonorFrame", "SkillFrame", "ReputationFrame",
    -- Social & World
    "FriendsFrame", "GuildFrame", "WhoFrame", "WorldMapFrame", "LFGParentFrame",
    -- Interaction
    "GossipFrame", "QuestFrame", "MerchantFrame", "TaxiFrame",
    "QuestLogFrame", "TradeFrame", "BankFrame", "AuctionFrame",
    -- Inventory (Bags 0-12)
    "ContainerFrame1", "ContainerFrame2", "ContainerFrame3", "ContainerFrame4",
    "ContainerFrame5", "ContainerFrame6", "ContainerFrame7", "ContainerFrame8",
    "ContainerFrame9", "ContainerFrame10", "ContainerFrame11", "ContainerFrame12",
    "ContainerFrame13",
    -- Management & Settings
    "GameMenuFrame", "InterfaceOptionsFrame", "VideoOptionsFrame",
    "AudioOptionsFrame", "KeyBindingFrame", "MacroFrame", "AddonList",
    -- Popups/Dialogs
    "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4", "ItemRefTooltip",
}

---------------------------------------------------------------
-- Late-Loaded Blizzard Addon Frames
---------------------------------------------------------------
-- These frames don't exist until their parent addon loads
local LATE_LOADED_FRAMES = {
    ["Blizzard_TalentUI"] = {"PlayerTalentFrame"},
    ["Blizzard_MacroUI"] = {"MacroFrame"},
    ["Blizzard_AuctionUI"] = {"AuctionFrame"},
    ["Blizzard_InspectUI"] = {"InspectFrame"},
}

local lateLoadedAddons = {}

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
---@param currentIndex number The current node index
---@param direction string The direction to navigate ("UP", "DOWN", "LEFT", "RIGHT")
---@return number|nil targetIndex The target node index, or nil if not found/invalid
---@private
function Hijack:_GetTargetNodeInDirection(currentIndex, direction)
    -- Get neighbor index from pre-calculated edges
    local edges = NavGraph:GetNodeEdges(currentIndex)
    if not edges then
        return nil
    end
    
    local dirKey = direction:lower()
    local targetIndex = edges[dirKey]
    
    if not targetIndex then
        return nil
    end
    
    -- Get target node and validate it's still visible
    local targetNode = NavGraph:IndexToNode(targetIndex)
    if not targetNode then
        NavGraph:InvalidateGraph()
        return nil
    end
    
    if not targetNode:IsVisible() then
        NavGraph:InvalidateGraph()
        return nil
    end
    
    return targetIndex
end

---Navigate to an adjacent node in the specified direction
---@param direction string The direction to navigate ("UP", "DOWN", "LEFT", "RIGHT")
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
    
    -- Hide previous tooltip before showing new one (memory leak fix)
    if GameTooltip:IsShown() then
        GameTooltip:Hide()
    end
    
    -- Show tooltip
    self:ShowNodeTooltip(node)
end

---Set focus to a specific node, configuring widgets and visual feedback
---@param node Frame The node to focus on
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

function Hijack:ShowNodeTooltip(node)
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
    
    local x, y = NODE.GetCenterScaled(node)
    if not x or not y then return end
    
    self.Gauntlet:ClearAllPoints()
    -- Position using scaled coordinates from NODE library
    -- Offset to center the pointer finger (top-left of texture) on the node center
    self.Gauntlet:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x - 8, y + 8)
    self.Gauntlet:Show()
end

function Hijack:SetGauntletPressed(pressed)
    if not self.Gauntlet then return end
    
    if pressed then
        self.Gauntlet.tex:SetTexture("Interface\\CURSOR\\Interact")
        self.Gauntlet:SetSize(38, 38)
    else
        self.Gauntlet.tex:SetTexture("Interface\\CURSOR\\Point")
        self.Gauntlet:SetSize(32, 32)
    end
end

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

---Register OnShow/OnHide hooks for all allowed frames
---@private
function Hijack:_RegisterVisibilityHooks()
    if self.RebuildState.hooksRegistered then
        return
    end
    
    
    local hooksRegistered = 0
    for _, frameName in ipairs(ALLOWED_FRAMES) do
        local frame = _G[frameName]
        if frame then
            -- Use HookScript to avoid overwriting existing handlers
            frame:HookScript('OnShow', function()
                if not InCombatLockdown() then
                    RequestGraphRebuild()
                end
            end)
            
            frame:HookScript('OnHide', function()
                if not InCombatLockdown() then
                    RequestGraphRebuild()
                end
            end)
            
            hooksRegistered = hooksRegistered + 1
        end
    end
    
    self.RebuildState.hooksRegistered = true
end

---Register hooks for frames from late-loaded Blizzard addons
---@private
function Hijack:_RegisterLateLoadedFrameHooks()
    
    self:RegisterEvent('ADDON_LOADED', function(event, addonName)
        local frames = LATE_LOADED_FRAMES[addonName]
        if not frames then return end
        
        
        for _, frameName in ipairs(frames) do
            local frame = _G[frameName]
            if frame then
                frame:HookScript('OnShow', function()
                    if not InCombatLockdown() then
                        RequestGraphRebuild()
                    end
                end)
                
                frame:HookScript('OnHide', function()
                    if not InCombatLockdown() then
                        RequestGraphRebuild()
                    end
                end)
                
            else
            end
        end
        
        lateLoadedAddons[addonName] = true
        
        -- Performance optimization: unregister event once all frames hooked
        if lateLoadedAddons["Blizzard_TalentUI"] and 
           lateLoadedAddons["Blizzard_MacroUI"] and 
           lateLoadedAddons["Blizzard_AuctionUI"] and 
           lateLoadedAddons["Blizzard_InspectUI"] then
            self:UnregisterEvent('ADDON_LOADED')
        end
    end)
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
local VisibilityChecker = CreateFrame("Frame")
VisibilityChecker.timer = 0
VisibilityChecker:SetScript("OnUpdate", function(self, elapsed)
    -- Skip checks during combat
    if InCombatLockdown() then return end
    
    -- Only check every 1 second (fallback, not primary mechanism)
    self.timer = self.timer + elapsed
    if self.timer < 1.0 then return end
    self.timer = 0
    
    -- Check for stale node (current node became invisible)
    if Hijack.IsActive and Hijack.CurrentNode then
        if not Hijack.CurrentNode:IsVisible() then
            NavGraph:InvalidateGraph()
            RequestGraphRebuild()
        end
    end
end)

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
    
    -- All checks passed: graph can be reused
    return true
end

---Collect all visible frames from the ALLOWED_FRAMES list
---@return table frameObjects List of visible frame objects
---@return table frameNames List of visible frame names
---@private
function Hijack:_CollectVisibleFrames()
    local activeFrames = {}
    local frameNames = {}
    
    for _, frameName in ipairs(ALLOWED_FRAMES) do
        local frame = _G[frameName]
        if frame and frame:IsVisible() and frame:GetAlpha() > 0 then
            table.insert(activeFrames, frame)
            table.insert(frameNames, frameName)
        end
    end
    
    if #activeFrames > 0 then
    else
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
    end
    
    return true
end

---Set up secure input widgets and bindings for navigation
---@return table|nil widgets Table of configured widgets, or nil on failure
---@private
function Hijack:_SetupSecureWidgets()
    assert(not InCombatLockdown(), 'Cannot setup widgets during combat')

    local widgets = {}
    local widgetCount = 0
    
    -- Set up PAD1 (primary action)
    widgets.pad1 = Driver:GetWidget('PAD1', 'Hijack')
    if widgets.pad1 then
        SetOverrideBindingClick(widgets.pad1, true, 'PAD1', widgets.pad1:GetName(), 'LeftButton')
        widgetCount = widgetCount + 1
    else
        return nil
    end
    
    -- Set up PAD2 (right-click action)
    widgets.pad2 = Driver:GetWidget('PAD2', 'Hijack')
    if widgets.pad2 then
        SetOverrideBindingClick(widgets.pad2, true, 'PAD2', widgets.pad2:GetName(), 'RightButton')
        widgetCount = widgetCount + 1
    else
        return nil
    end
    
    -- Set up D-Pad navigation widgets
    widgets.up = Driver:GetWidget('PADDUP', 'Hijack')
    if widgets.up then
        SetOverrideBindingClick(widgets.up, true, 'PADDUP', widgets.up:GetName(), 'LeftButton')
        widgetCount = widgetCount + 1
    else
    end
    
    widgets.down = Driver:GetWidget('PADDDOWN', 'Hijack')
    if widgets.down then
        SetOverrideBindingClick(widgets.down, true, 'PADDDOWN', widgets.down:GetName(), 'LeftButton')
        widgetCount = widgetCount + 1
    else
    end
    
    widgets.left = Driver:GetWidget('PADDLEFT', 'Hijack')
    if widgets.left then
        SetOverrideBindingClick(widgets.left, true, 'PADDLEFT', widgets.left:GetName(), 'LeftButton')
        widgetCount = widgetCount + 1
    else
    end
    
    widgets.right = Driver:GetWidget('PADDRIGHT', 'Hijack')
    if widgets.right then
        SetOverrideBindingClick(widgets.right, true, 'PADDRIGHT', widgets.right:GetName(), 'LeftButton')
        widgetCount = widgetCount + 1
    else
    end
    
    return widgets
end

---Set up PreClick and PostClick handlers for navigation and visual feedback
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
function Hijack:EnableNavigation()
    if InCombatLockdown() then
        return
    end
    
    if self.IsActive then
        return
    end
    
    
    -- Step 1: Collect visible frames
    local activeFrames, frameNames = self:_CollectVisibleFrames()
    if #activeFrames == 0 then
        return
    end
    
    -- Step 2: Check if we can reuse existing graph (performance optimization)
    local canReuseGraph = self:_CanReuseGraph(frameNames)
    
    -- Step 3: Build/export graph only if needed
    if not canReuseGraph then
        if not self:_BuildAndExportGraph(activeFrames, frameNames) then
            return
        end
    else
    end
    
    -- Step 4: Get first node to focus
    local firstIndex = NavGraph:GetFirstNodeIndex()
    if not firstIndex then
        return
    end
    
    local firstNode = NavGraph:IndexToNode(firstIndex)
    if not firstNode then
        return
    end
    
    -- Step 5: Set up secure input widgets and bindings
    local widgets = self:_SetupSecureWidgets()
    if not widgets then
        return
    end
    
    -- Step 6: Set up navigation handlers
    self:_SetupNavigationHandlers(widgets)
    
    -- Step 7: Mark navigation as active AFTER all setup succeeds
    self.IsActive = true
    
    -- Step 8: Focus on first node
    self:SetFocus(firstNode)
    
end

---Disable UI navigation and clean up all widgets and state
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
    
    -- Hide gauntlet
    if self.Gauntlet then
        self.Gauntlet:Hide()
    end
    
    -- Hide tooltip (improved cleanup)
    if GameTooltip:IsShown() then
        if not self.CurrentNode or GameTooltip:GetOwner() == self.CurrentNode or GameTooltip:IsOwned(UIParent) then
            GameTooltip:Hide()
        end
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
-- Combat Protection
---------------------------------------------------------------
function Driver:PLAYER_REGEN_DISABLED()
    -- Entering combat: disable navigation immediately
    if Hijack.IsActive then
        Hijack:DisableNavigation()
    end
end

function Driver:PLAYER_REGEN_ENABLED()
    -- Leaving combat: navigation will re-enable via visibility checker if UI is open
end

---------------------------------------------------------------
-- Module Initialization
---------------------------------------------------------------
function Hijack:OnEnable()
    self:CreateGauntlet()
    
    -- Register event-driven visibility detection
    self:_RegisterVisibilityHooks()
    self:_RegisterLateLoadedFrameHooks()
    self:_RegisterGameEvents()
    
    -- Check if any frames are already open
    self:_CheckInitialVisibility()
    
    -- Start fallback polling (safety net)
    VisibilityChecker:Show()
    
end

function Hijack:OnDisable()
    self:DisableNavigation()
    VisibilityChecker:Hide()
    self.RebuildState.hooksRegistered = false
end
