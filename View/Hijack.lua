---------------------------------------------------------------
-- CPLight UI Navigation System
---------------------------------------------------------------
-- Secure state-driven UI navigation for TBC Anniversary (2.5.5)
-- Architecture: Separates secure action handling from insecure visuals
-- following WoW's Protected Action System requirements.

local ADDON_NAME, addon = ...
local Hijack = LibStub("AceAddon-3.0"):GetAddon("CPLight"):NewModule("Hijack", "AceEvent-3.0")
local NODE = LibStub('ConsolePortNode')

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
-- Node Scanning (Insecure - Runs Out of Combat Only)
---------------------------------------------------------------
-- Uses ConsolePortNode library's superior recursive scanner
function Hijack:GetActiveNodes()
    local activeFrames = {}
    for _, frameName in ipairs(ALLOWED_FRAMES) do
        local frame = _G[frameName]
        if frame and frame:IsVisible() and frame:GetAlpha() > 0 then
            table.insert(activeFrames, frame)
        end
    end
    
    -- NODE(unpack(activeFrames)) scans all frames recursively and returns cached nodes
    if #activeFrames > 0 then
        local cache = NODE(unpack(activeFrames))
        local nodes = {}
        -- Extract node references from cache
        for _, cacheItem in ipairs(cache) do
            table.insert(nodes, cacheItem.node)
        end
        return nodes
    end
    
    return {}
end

---------------------------------------------------------------
-- Navigation Logic (Insecure - Will be converted to secure snippets in later phases)
---------------------------------------------------------------
function Hijack:Navigate(direction)
    if not self.CurrentNode or InCombatLockdown() then return end
    
    -- Rescan nodes to handle dynamic UI changes and rebuild NODE cache
    local activeFrames = {}
    for _, frameName in ipairs(ALLOWED_FRAMES) do
        local frame = _G[frameName]
        if frame and frame:IsVisible() and frame:GetAlpha() > 0 then
            table.insert(activeFrames, frame)
        end
    end
    
    if #activeFrames == 0 then return end
    
    -- Rebuild NODE cache with current UI state
    local cache = NODE(unpack(activeFrames))
    
    if #cache == 0 then return end
    
    -- Find current node in cache
    local currentCacheItem = nil
    for _, cacheItem in ipairs(cache) do
        if cacheItem.node == self.CurrentNode then
            currentCacheItem = cacheItem
            break
        end
    end
    
    -- If current node not in cache, use first node
    if not currentCacheItem then
        self:SetFocus(cache[1].node)
        return
    end
    
    -- Use NODE library's superior navigation algorithm
    local targetCacheItem = NODE.NavigateToBestCandidateV3(currentCacheItem, direction)
    
    if targetCacheItem and targetCacheItem.node ~= self.CurrentNode then
        self:SetFocus(targetCacheItem.node)
    end
end

---------------------------------------------------------------
-- Focus Management (Insecure - Updates visuals and prepares secure click)
---------------------------------------------------------------
function Hijack:SetFocus(node)
    if not node or InCombatLockdown() then return end
    
    self.CurrentNode = node
    
    -- Update secure widget to target this node
    local clickWidget = Driver:GetWidget('PAD1', 'Hijack')
    if clickWidget then
        clickWidget:SetAttribute(CPAPI.ActionTypeRelease, 'click')
        clickWidget:SetAttribute('clickbutton', node)
        clickWidget:Show()
    end
    
    -- Also update PAD2 for right-click
    local rightWidget = Driver:GetWidget('PAD2', 'Hijack')
    if rightWidget then
        rightWidget:SetAttribute(CPAPI.ActionTypeRelease, 'click')
        rightWidget:SetAttribute('clickbutton', node)
        rightWidget:Show()
    end
    
    -- Update gauntlet visual
    self:UpdateGauntletPosition(node)
    
    -- Show tooltip
    self:ShowNodeTooltip(node)
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
-- Binding Management (Runs in OnUpdate to detect UI state changes)
---------------------------------------------------------------
local VisibilityChecker = CreateFrame("Frame")
VisibilityChecker.timer = 0
VisibilityChecker:SetScript("OnUpdate", function(self, elapsed)
    self.timer = self.timer + elapsed
    if self.timer < 0.1 then return end
    self.timer = 0
    
    -- Check if any allowed frames are visible
    local visible = false
    for _, frameName in ipairs(ALLOWED_FRAMES) do
        local frame = _G[frameName]
        if frame and frame:IsVisible() and frame:GetAlpha() > 0 then
            visible = true
            break
        end
    end
    
    -- Enable/disable navigation based on visibility
    if visible and not Hijack.IsActive then
        Hijack:EnableNavigation()
    elseif not visible and Hijack.IsActive then
        Hijack:DisableNavigation()
    elseif visible and Hijack.IsActive then
        -- UI is still open: check if current node is still valid
        if Hijack.CurrentNode and not Hijack.CurrentNode:IsVisible() then
            -- Current frame closed, refocus on nearest available node
            local nodes = Hijack:GetActiveNodes()
            if #nodes > 0 then
                Driver.NodeCache = nodes
                Hijack:SetFocus(nodes[1])
            else
                Hijack:DisableNavigation()
            end
        end
    end
end)

function Hijack:EnableNavigation()
    if InCombatLockdown() or self.IsActive then return end
    
    -- Scan for nodes using NODE library
    local nodes = self:GetActiveNodes()
    if #nodes == 0 then return end
    
    -- Store both nodes and cache for navigation
    Driver.NodeCache = nodes
    Driver.CurrentIndex = 1
    self.IsActive = true
    
    -- Set up secure input widgets with override bindings
    local padWidget = Driver:GetWidget('PAD1', 'Hijack')
    SetOverrideBindingClick(padWidget, true, 'PAD1', padWidget:GetName(), 'LeftButton')
    
    local pad2Widget = Driver:GetWidget('PAD2', 'Hijack')
    SetOverrideBindingClick(pad2Widget, true, 'PAD2', pad2Widget:GetName(), 'RightButton')
    
    -- D-Pad navigation widgets (will trigger insecure navigation for now)
    local upWidget = Driver:GetWidget('PADDUP', 'Hijack')
    SetOverrideBindingClick(upWidget, true, 'PADDUP', upWidget:GetName(), 'LeftButton')
    
    local downWidget = Driver:GetWidget('PADDDOWN', 'Hijack')
    SetOverrideBindingClick(downWidget, true, 'PADDDOWN', downWidget:GetName(), 'LeftButton')
    
    local leftWidget = Driver:GetWidget('PADDLEFT', 'Hijack')
    SetOverrideBindingClick(leftWidget, true, 'PADDLEFT', leftWidget:GetName(), 'LeftButton')
    
    local rightWidget = Driver:GetWidget('PADDRIGHT', 'Hijack')
    SetOverrideBindingClick(rightWidget, true, 'PADDRIGHT', rightWidget:GetName(), 'LeftButton')
    
    -- Set up PreClick handlers for D-Pad navigation (temporary insecure solution)
    -- PreClick only fires on button DOWN, preventing double navigation on press+release
    upWidget:SetScript('PreClick', function(self, button, down)
        if down then Hijack:Navigate('UP') end
    end)
    downWidget:SetScript('PreClick', function(self, button, down)
        if down then Hijack:Navigate('DOWN') end
    end)
    leftWidget:SetScript('PreClick', function(self, button, down)
        if down then Hijack:Navigate('LEFT') end
    end)
    rightWidget:SetScript('PreClick', function(self, button, down)
        if down then Hijack:Navigate('RIGHT') end
    end)
    
    -- Set up visual feedback handlers for PAD1/PAD2 (only on down press)
    padWidget:SetScript('PreClick', function(self, button, down)
        if down then Hijack:SetGauntletPressed(true) end
    end)
    padWidget:SetScript('PostClick', function(self, button, down)
        Hijack:SetGauntletPressed(false)
    end)
    pad2Widget:SetScript('PreClick', function(self, button, down)
        if down then Hijack:SetGauntletPressed(true) end
    end)
    pad2Widget:SetScript('PostClick', function(self, button, down)
        Hijack:SetGauntletPressed(false)
    end)
    
    -- Focus first node
    self:SetFocus(nodes[1])
    
    CPAPI.Log('UI Navigation Enabled (%d nodes)', #nodes)
end

function Hijack:DisableNavigation()
    if InCombatLockdown() or not self.IsActive then return end
    
    self.IsActive = false
    
    -- Release all input widgets
    Driver:ReleaseAll()
    
    -- Clear bindings
    for id in pairs(Driver.Widgets) do
        local widget = Driver.Widgets[id]
        if widget then
            ClearOverrideBindings(widget)
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
    Driver.NodeCache = {}
    Driver.CurrentIndex = 1
    self.CurrentNode = nil
    
    CPAPI.Log('UI Navigation Disabled')
end

---------------------------------------------------------------
-- Combat Protection
---------------------------------------------------------------
function Driver:PLAYER_REGEN_DISABLED()
    -- Entering combat: disable navigation
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
    VisibilityChecker:Show()
    CPAPI.Log('Hijack System Initialized (Secure State Driver Architecture)')
end

function Hijack:OnDisable()
    self:DisableNavigation()
    VisibilityChecker:Hide()
end