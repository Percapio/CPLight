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
        CPAPI.Log('Cannot navigate: in combat lockdown')
        return nil
    end
    
    if not self.CurrentNode then
        CPAPI.Log('Cannot navigate: no current node')
        return nil
    end
    
    if not NavGraph then
        CPAPI.Log('Cannot navigate: NavGraph module not available')
        return nil
    end
    
    local currentIndex = NavGraph:NodeToIndex(self.CurrentNode)
    if not currentIndex then
        CPAPI.Log('Cannot navigate: current node not in graph, attempting recovery')
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
        CPAPI.Log('Navigate: no edges found for node index %d', currentIndex)
        return nil
    end
    
    local dirKey = direction:lower()
    local targetIndex = edges[dirKey]
    
    if not targetIndex then
        CPAPI.Log('Navigate: no neighbor in %s direction from node index %d', direction, currentIndex)
        return nil
    end
    
    -- Get target node and validate it's still visible
    local targetNode = NavGraph:IndexToNode(targetIndex)
    if not targetNode then
        CPAPI.Log('Navigate: target node at index %d not found in graph', targetIndex)
        NavGraph:InvalidateGraph()
        return nil
    end
    
    if not targetNode:IsVisible() then
        CPAPI.Log('Navigate: target node at index %d is no longer visible, invalidating graph', targetIndex)
        NavGraph:InvalidateGraph()
        return nil
    end
    
    CPAPI.Log('Navigate: found target node index %d in %s direction', targetIndex, direction)
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
    
    CPAPI.Log('Navigating %s from node index %d', direction, currentIndex)
    
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
        CPAPI.Log('SetFocus: node is nil')
        return false
    end
    
    if InCombatLockdown() then
        CPAPI.Log('SetFocus: cannot focus during combat lockdown')
        return false
    end
    
    if not node.IsVisible then
        CPAPI.Log('SetFocus: node has no IsVisible method')
        return false
    end
    
    if not node:IsVisible() then
        CPAPI.Log('SetFocus: node is not visible')
        return false
    end
    
    return true
end

---Configure secure input widgets to target the specified node
---@param node Frame The node to configure widgets for
---@return boolean success True if widgets were configured successfully
---@private
function Hijack:_ConfigureWidgetsForNode(node)
    local widgetsConfigured = 0
    
    -- Update PAD1 (primary action) widget
    local clickWidget = Driver:GetWidget('PAD1', 'Hijack')
    if clickWidget then
        clickWidget:SetAttribute(CPAPI.ActionTypeRelease, 'click')
        clickWidget:SetAttribute('clickbutton', node)
        clickWidget:Show()
        widgetsConfigured = widgetsConfigured + 1
    else
        CPAPI.Log('SetFocus: failed to get PAD1 widget')
    end
    
    -- Update PAD2 (right-click) widget
    local rightWidget = Driver:GetWidget('PAD2', 'Hijack')
    if rightWidget then
        rightWidget:SetAttribute(CPAPI.ActionTypeRelease, 'click')
        rightWidget:SetAttribute('clickbutton', node)
        rightWidget:Show()
        widgetsConfigured = widgetsConfigured + 1
    else
        CPAPI.Log('SetFocus: failed to get PAD2 widget')
    end
    
    if widgetsConfigured == 0 then
        CPAPI.Log('SetFocus: no widgets configured')
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
        CPAPI.Log('SetFocus: focusing on node index %d', nodeIndex)
    else
        CPAPI.Log('SetFocus: focusing on node (index unknown)')
    end
    
    -- Update current node reference
    self.CurrentNode = node
    
    -- Configure secure widgets to target this node
    if not self:_ConfigureWidgetsForNode(node) then
        CPAPI.Log('SetFocus: widget configuration failed, but focus set')
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
        CPAPI.Log('RequestGraphRebuild: skipping, in combat lockdown')
        return
    end
    
    -- Mark rebuild as pending
    Hijack.RebuildState.pending = true
    CPAPI.Log('RequestGraphRebuild: rebuild scheduled (100ms debounce)')
    
    -- Debounce: wait 100ms to let multiple frame changes settle
    C_Timer.After(0.1, function()
        -- Clear pending flag first
        Hijack.RebuildState.pending = false
        
        -- Re-check combat status (might have entered combat during delay)
        if InCombatLockdown() then
            CPAPI.Log('RequestGraphRebuild: aborting, entered combat during debounce')
            return
        end
        
        -- Check if any frames are visible
        local activeFrames, frameNames = Hijack:_CollectVisibleFrames()
        
        if #activeFrames > 0 then
            -- Frames visible: enable/refresh navigation
            if not Hijack.IsActive then
                CPAPI.Log('RequestGraphRebuild: enabling navigation')
                Hijack:EnableNavigation()
            else
                -- Already active: check if frame set changed
                local frameSetChanged = not Hijack:_CanReuseGraph(frameNames)
                if frameSetChanged then
                    CPAPI.Log('RequestGraphRebuild: frame set changed, rebuilding')
                    NavGraph:InvalidateGraph()
                    Hijack:DisableNavigation()
                    Hijack:EnableNavigation()
                else
                    CPAPI.Log('RequestGraphRebuild: frame set unchanged, no rebuild needed')
                end
            end
        else
            -- No frames visible: disable navigation
            if Hijack.IsActive then
                CPAPI.Log('RequestGraphRebuild: no visible frames, disabling navigation')
                Hijack:DisableNavigation()
            end
        end
    end)
end

---Register OnShow/OnHide hooks for all allowed frames
---@private
function Hijack:_RegisterVisibilityHooks()
    if self.RebuildState.hooksRegistered then
        CPAPI.Log('_RegisterVisibilityHooks: hooks already registered, skipping')
        return
    end
    
    CPAPI.Log('_RegisterVisibilityHooks: registering OnShow/OnHide hooks for %d frames', #ALLOWED_FRAMES)
    
    local hooksRegistered = 0
    for _, frameName in ipairs(ALLOWED_FRAMES) do
        local frame = _G[frameName]
        if frame then
            -- Use HookScript to avoid overwriting existing handlers
            frame:HookScript('OnShow', function()
                if not InCombatLockdown() then
                    CPAPI.Log('Frame OnShow: %s', frameName)
                    RequestGraphRebuild()
                end
            end)
            
            frame:HookScript('OnHide', function()
                if not InCombatLockdown() then
                    CPAPI.Log('Frame OnHide: %s', frameName)
                    RequestGraphRebuild()
                end
            end)
            
            hooksRegistered = hooksRegistered + 1
        end
    end
    
    self.RebuildState.hooksRegistered = true
    CPAPI.Log('_RegisterVisibilityHooks: registered hooks for %d frames', hooksRegistered)
end

---Register game events for dynamic content changes
---@private
function Hijack:_RegisterGameEvents()
    -- BAG_UPDATE fires when bag contents change (items added/removed)
    self:RegisterEvent('BAG_UPDATE', function()
        if not InCombatLockdown() and self.IsActive then
            CPAPI.Log('BAG_UPDATE: requesting graph rebuild for dynamic content')
            RequestGraphRebuild()
        end
    end)
    
    CPAPI.Log('_RegisterGameEvents: registered BAG_UPDATE event')
end

---Check initial frame visibility state on startup
---@private
function Hijack:_CheckInitialVisibility()
    CPAPI.Log('_CheckInitialVisibility: checking for frames already open')
    
    -- Wait 0.5s after hooks are registered to check initial state
    -- This ensures all frames are loaded and visible state is stable
    C_Timer.After(0.5, function()
        if InCombatLockdown() then
            CPAPI.Log('_CheckInitialVisibility: skipping, in combat')
            return
        end
        
        local activeFrames = self:_CollectVisibleFrames()
        if #activeFrames > 0 then
            CPAPI.Log('_CheckInitialVisibility: found %d visible frames, enabling navigation', #activeFrames)
            RequestGraphRebuild()
        else
            CPAPI.Log('_CheckInitialVisibility: no visible frames')
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
            CPAPI.Log('VisibilityChecker: current node became invisible, requesting rebuild')
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
        CPAPI.Log('_CanReuseGraph: no current frames provided')
        return false
    end
    
    -- Check if NavGraph is valid
    if not NavGraph or not NavGraph:IsValid() then
        CPAPI.Log('_CanReuseGraph: graph is invalid or NavGraph module unavailable')
        return false
    end
    
    -- Check if we have previous state to compare against
    if not self.LastGraphState or not self.LastGraphState.frameNames or #self.LastGraphState.frameNames == 0 then
        CPAPI.Log('_CanReuseGraph: no previous graph state to compare')
        return false
    end
    
    -- Compare frame counts first (fast check)
    if #currentFrameNames ~= #self.LastGraphState.frameNames then
        CPAPI.Log('_CanReuseGraph: frame count changed (%d → %d), rebuild required', #self.LastGraphState.frameNames, #currentFrameNames)
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
            CPAPI.Log('_CanReuseGraph: frame set changed (new frame: %s), rebuild required', frameName)
            return false
        end
    end
    
    -- Verify node count hasn't changed (detects dynamic content changes)
    local currentNodeCount = NavGraph:GetNodeCount()
    if currentNodeCount ~= self.LastGraphState.nodeCount then
        CPAPI.Log('_CanReuseGraph: node count changed (%d → %d), rebuild required', self.LastGraphState.nodeCount, currentNodeCount)
        return false
    end
    
    -- All checks passed: graph can be reused
    CPAPI.Log('_CanReuseGraph: graph is valid and frame set unchanged, reusing existing graph')
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
        CPAPI.Log('_CollectVisibleFrames: found %d visible frames: %s', #activeFrames, table.concat(frameNames, ', '))
    else
        CPAPI.Log('_CollectVisibleFrames: no visible frames found')
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
        CPAPI.Log('_BuildAndExportGraph: NavGraph module not available')
        return false
    end
    
    -- Build graph using NavigationGraph module
    local success = NavGraph:BuildGraph(frames)
    if not success then
        CPAPI.Log('_BuildAndExportGraph: NavGraph:BuildGraph() returned false')
        return false
    end
    
    local nodeCount = NavGraph:GetNodeCount()
    if not nodeCount or nodeCount == 0 then
        CPAPI.Log('_BuildAndExportGraph: graph built but has 0 nodes')
        return false
    end
    
    CPAPI.Log('_BuildAndExportGraph: graph built with %d nodes', nodeCount)
    
    -- Export graph to secure Driver frame
    if not NavGraph:ExportToSecureFrame(Driver) then
        CPAPI.Log('_BuildAndExportGraph: failed to export graph to Driver frame')
        return false
    end
    
    CPAPI.Log('_BuildAndExportGraph: graph exported to Driver frame successfully')
    
    -- Save state for future reuse checks
    if frameNames and #frameNames > 0 then
        self.LastGraphState.frameNames = frameNames
        self.LastGraphState.nodeCount = nodeCount
        CPAPI.Log('_BuildAndExportGraph: saved graph state (%d frames, %d nodes)', #frameNames, nodeCount)
    end
    
    return true
end

---Set up secure input widgets and bindings for navigation
---@return table|nil widgets Table of configured widgets, or nil on failure
---@private
function Hijack:_SetupSecureWidgets()
    local widgets = {}
    local widgetCount = 0
    
    -- Set up PAD1 (primary action)
    widgets.pad1 = Driver:GetWidget('PAD1', 'Hijack')
    if widgets.pad1 then
        SetOverrideBindingClick(widgets.pad1, true, 'PAD1', widgets.pad1:GetName(), 'LeftButton')
        widgetCount = widgetCount + 1
    else
        CPAPI.Log('EnableNavigation: failed to get PAD1 widget')
        return nil
    end
    
    -- Set up PAD2 (right-click action)
    widgets.pad2 = Driver:GetWidget('PAD2', 'Hijack')
    if widgets.pad2 then
        SetOverrideBindingClick(widgets.pad2, true, 'PAD2', widgets.pad2:GetName(), 'RightButton')
        widgetCount = widgetCount + 1
    else
        CPAPI.Log('EnableNavigation: failed to get PAD2 widget')
        return nil
    end
    
    -- Set up D-Pad navigation widgets
    widgets.up = Driver:GetWidget('PADDUP', 'Hijack')
    if widgets.up then
        SetOverrideBindingClick(widgets.up, true, 'PADDUP', widgets.up:GetName(), 'LeftButton')
        widgetCount = widgetCount + 1
    else
        CPAPI.Log('EnableNavigation: failed to get PADDUP widget')
    end
    
    widgets.down = Driver:GetWidget('PADDDOWN', 'Hijack')
    if widgets.down then
        SetOverrideBindingClick(widgets.down, true, 'PADDDOWN', widgets.down:GetName(), 'LeftButton')
        widgetCount = widgetCount + 1
    else
        CPAPI.Log('EnableNavigation: failed to get PADDDOWN widget')
    end
    
    widgets.left = Driver:GetWidget('PADDLEFT', 'Hijack')
    if widgets.left then
        SetOverrideBindingClick(widgets.left, true, 'PADDLEFT', widgets.left:GetName(), 'LeftButton')
        widgetCount = widgetCount + 1
    else
        CPAPI.Log('EnableNavigation: failed to get PADDLEFT widget')
    end
    
    widgets.right = Driver:GetWidget('PADDRIGHT', 'Hijack')
    if widgets.right then
        SetOverrideBindingClick(widgets.right, true, 'PADDRIGHT', widgets.right:GetName(), 'LeftButton')
        widgetCount = widgetCount + 1
    else
        CPAPI.Log('EnableNavigation: failed to get PADDRIGHT widget')
    end
    
    CPAPI.Log('EnableNavigation: configured %d secure input widgets with bindings', widgetCount)
    return widgets
end

---Set up PreClick and PostClick handlers for navigation and visual feedback
---@param widgets table Table of widgets to configure handlers for
---@private
function Hijack:_SetupNavigationHandlers(widgets)
    if not widgets then
        CPAPI.Log('EnableNavigation: cannot setup handlers, widgets table is nil')
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
    
    CPAPI.Log('EnableNavigation: navigation handlers configured')
end

---Enable UI navigation by building graph and setting up input handlers
function Hijack:EnableNavigation()
    if InCombatLockdown() then
        CPAPI.Log('EnableNavigation: cannot enable during combat lockdown')
        return
    end
    
    if self.IsActive then
        CPAPI.Log('EnableNavigation: navigation already active')
        return
    end
    
    CPAPI.Log('EnableNavigation: starting navigation enable sequence')
    
    -- Step 1: Collect visible frames
    local activeFrames, frameNames = self:_CollectVisibleFrames()
    if #activeFrames == 0 then
        return
    end
    
    -- Step 2: Check if we can reuse existing graph (performance optimization)
    local canReuseGraph = self:_CanReuseGraph(frameNames)
    
    -- Step 3: Build/export graph only if needed
    if not canReuseGraph then
        CPAPI.Log('EnableNavigation: building new navigation graph')
        if not self:_BuildAndExportGraph(activeFrames, frameNames) then
            CPAPI.Log('EnableNavigation: failed to build/export graph, aborting')
            return
        end
    else
        CPAPI.Log('EnableNavigation: reusing existing navigation graph')
    end
    
    -- Step 4: Get first node to focus
    local firstIndex = NavGraph:GetFirstNodeIndex()
    if not firstIndex then
        CPAPI.Log('EnableNavigation: no first node index available')
        return
    end
    
    local firstNode = NavGraph:IndexToNode(firstIndex)
    if not firstNode then
        CPAPI.Log('EnableNavigation: first node at index %d not found', firstIndex)
        return
    end
    
    -- Step 5: Set up secure input widgets and bindings
    local widgets = self:_SetupSecureWidgets()
    if not widgets then
        CPAPI.Log('EnableNavigation: failed to setup secure widgets, aborting')
        return
    end
    
    -- Step 6: Set up navigation handlers
    self:_SetupNavigationHandlers(widgets)
    
    -- Step 7: Mark navigation as active AFTER all setup succeeds
    self.IsActive = true
    
    -- Step 8: Focus on first node
    self:SetFocus(firstNode)
    
    CPAPI.Log('EnableNavigation: UI navigation enabled successfully (%d nodes)', NavGraph:GetNodeCount())
end

---Disable UI navigation and clean up all widgets and state
function Hijack:DisableNavigation()
    if InCombatLockdown() then
        CPAPI.Log('DisableNavigation: cannot disable during combat lockdown')
        return
    end
    
    if not self.IsActive then
        CPAPI.Log('DisableNavigation: navigation not active')
        return
    end
    
    -- Get node count before invalidating graph
    local nodeCount = NavGraph and NavGraph:GetNodeCount() or 0
    CPAPI.Log('DisableNavigation: disabling navigation, had %d nodes in graph', nodeCount)
    
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
        CPAPI.Log('DisableNavigation: cleared bindings for %d widgets', bindingsCleared)
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
    
    CPAPI.Log('DisableNavigation: UI navigation disabled successfully')
end

---------------------------------------------------------------
-- Combat Protection
---------------------------------------------------------------
function Driver:PLAYER_REGEN_DISABLED()
    -- Entering combat: disable navigation immediately
    CPAPI.Log('Combat started, disabling navigation')
    if Hijack.IsActive then
        Hijack:DisableNavigation()
    end
end

function Driver:PLAYER_REGEN_ENABLED()
    -- Leaving combat: navigation will re-enable via visibility checker if UI is open
    CPAPI.Log('Combat ended, navigation can re-enable if UI visible')
end

---------------------------------------------------------------
-- Module Initialization
---------------------------------------------------------------
function Hijack:OnEnable()
    self:CreateGauntlet()
    
    -- Register event-driven visibility detection
    self:_RegisterVisibilityHooks()
    self:_RegisterGameEvents()
    
    -- Check if any frames are already open
    self:_CheckInitialVisibility()
    
    -- Start fallback polling (safety net)
    VisibilityChecker:Show()
    
    CPAPI.Log('Hijack System Initialized (Event-Driven Architecture with 1s Fallback Polling)')
end

function Hijack:OnDisable()
    self:DisableNavigation()
    VisibilityChecker:Hide()
end