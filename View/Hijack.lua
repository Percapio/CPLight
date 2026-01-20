local ADDON_NAME, addon = ...
local Hijack = LibStub("AceAddon-3.0"):GetAddon("CPLight"):NewModule("Hijack", "AceEvent-3.0")

-- API FIX: Anniversary Client (2.5.5)
local function SetCursor(x, y)
    if C_Cursor and C_Cursor.SetCursorPosition then
        C_Cursor.SetCursorPosition(x, y)
    elseif SetCursorPosition then
        SetCursorPosition(x, y)
    end
end

local Driver = CreateFrame("Frame", "CPLightBindingDriver", UIParent)

local ALLOWED_FRAMES = {
    "CharacterFrame", "SpellBookFrame", "BetterBagsBagBackpack", "TradeSkillFrame",
    "GuildFrame", "FriendsFrame", "MSBTMainOptionsFrame", "GarrisonLandingPage",
    "CollectionsJournal", "EncounterJournal", "PetJournalParent", "ToyBoxFrame",
    "WardrobeFrame", "AchievementFrame", "CalendarFrame", "LFGParentFrame",
    "LFDRoleCheckPopup", "AuctionFrame", "BankFrame", "MailFrame", "QuestLogFrame",
    "GossipFrame", "MerchantFrame", "LootFrame", "GuildRecruitmentFrame"
}

---------------------------------------------------------------
-- 1. RECURSIVE SCANNER (Adopted from Navigation.lua)
---------------------------------------------------------------
function Hijack:ScanForButtons(frame)
    local candidates = {}
    local function Collect(current)
        if not current or not current.GetChildren then return end
        for _, child in ipairs({current:GetChildren()}) do
            if child:IsVisible() and child:IsObjectType("Button") and child:IsEnabled() then
                table.insert(candidates, child)
            end
            Collect(child) -- Search deeper
        end
    end
    Collect(frame)
    return candidates
end

function Hijack:GetActiveNodes()
    local allNodes = {}
    for _, frameName in ipairs(ALLOWED_FRAMES) do
        local frame = _G[frameName]
        if frame and frame:IsVisible() and frame:GetAlpha() > 0 then
            local nodes = self:ScanForButtons(frame)
            for _, node in ipairs(nodes) do
                table.insert(allNodes, node)
            end
        end
    end
    return allNodes
end

---------------------------------------------------------------
-- 2. NAVIGATION LOGIC (Merged Cone Logic)
---------------------------------------------------------------
function Hijack:Navigate(direction)
    if not self.CurrentNode then return end
    
    local nodes = self:GetActiveNodes()
    local cx, cy = self.CurrentNode:GetCenter()
    local bestNode, bestScore = nil, math.huge
    
    local vectors = {
        UP    = {x = 0, y = 1},  DOWN  = {x = 0, y = -1},
        LEFT  = {x = -1, y = 0}, RIGHT = {x = 1, y = 0}
    }
    local v = vectors[direction]

    for _, node in ipairs(nodes) do
        if node ~= self.CurrentNode then
            local nx, ny = node:GetCenter()
            if nx then
                local dx, dy = nx - cx, ny - cy
                local dot = (dx * v.x) + (dy * v.y)
                
                if dot > 0 then -- Node is in the right general direction
                    -- Cone check: Is it more in this direction than the other?
                    local inCone = (v.x ~= 0 and math.abs(dx) >= math.abs(dy)) or 
                                   (v.y ~= 0 and math.abs(dy) >= math.abs(dx))
                    
                    if inCone then
                        local distSq = (dx*dx) + (dy*dy)
                        if distSq < bestScore then
                            bestScore = distSq
                            bestNode = node
                        end
                    end
                end
            end
        end
    end
    
    if bestNode then self:SetFocus(bestNode) end
end

---------------------------------------------------------------
-- 3. CORE SYSTEMS (Hijack Structure)
---------------------------------------------------------------
function Hijack:OnEnable()
    self:CreateGauntlet()
    self:CreateSecureButton()
    
    Driver:SetScript("OnUpdate", function(f, elapsed)
        f.timer = (f.timer or 0) + elapsed
        if f.timer > 0.1 then
            f.timer = 0
            local visible = false
            for _, name in ipairs(ALLOWED_FRAMES) do
                local frame = _G[name]
                if frame and frame:IsVisible() and frame:GetAlpha() > 0 then 
                    visible = true; break 
                end
            end
            
            if visible and not self.IsActive then self:EnableNavigation()
            elseif not visible and self.IsActive then self:DisableNavigation() end
        end
    end)
end

function Hijack:EnableNavigation()
    if InCombatLockdown() then return end
    
    local nodes = self:GetActiveNodes()
    if #nodes == 0 then return end
    self.IsActive = true
    
    ClearOverrideBindings(Driver)
    SetOverrideBindingClick(Driver, true, "PAD1", "CPLightSecureClick", "LeftButton")
    SetOverrideBindingClick(Driver, true, "PAD2", "CPLightSecureClick", "RightButton")
    SetOverrideBindingClick(Driver, true, "PADDUP", "CPLightSecureClick", "UP")
    SetOverrideBindingClick(Driver, true, "PADDDOWN", "CPLightSecureClick", "DOWN")
    SetOverrideBindingClick(Driver, true, "PADDLEFT", "CPLightSecureClick", "LEFT")
    SetOverrideBindingClick(Driver, true, "PADDRIGHT", "CPLightSecureClick", "RIGHT")
    
    self:SetFocus(nodes[1])
end

function Hijack:DisableNavigation()
    if InCombatLockdown() then return end
    
    self.IsActive = false
    ClearOverrideBindings(Driver)
    
    -- Clear secure button target
    if self.ClickButton then
        self.ClickButton:SetAttribute("clickbutton", nil)
    end
    
    -- Hide tooltip
    if GameTooltip:GetOwner() == self.CurrentNode then
        GameTooltip:Hide()
    end
    
    if self.Gauntlet then self.Gauntlet:Hide() end
    self.CurrentNode = nil
end

function Hijack:SetFocus(node)
    if not node then return end
    self.CurrentNode = node
    
    -- Set secure clickbutton BEFORE any other interactions
    if not InCombatLockdown() and self.ClickButton then
        self.ClickButton:SetAttribute("clickbutton", node)
    end
    
    -- Explicitly trigger tooltip
    if node:HasScript("OnEnter") then
        local onEnterScript = node:GetScript("OnEnter")
        if onEnterScript then
            onEnterScript(node)
        else
            -- Fallback: Manually show tooltip
            if node:GetName() then
                GameTooltip:SetOwner(node, "ANCHOR_RIGHT")
                GameTooltip:SetText(node:GetName())
                GameTooltip:Show()
            end
        end
    end
    
    -- Move gauntlet to node center
    if self.Gauntlet then
        self.Gauntlet:ClearAllPoints()
        self.Gauntlet:SetPoint("CENTER", node, "CENTER", 0, 0)
        self.Gauntlet:Show()
    end
end

---------------------------------------------------------------
-- 4. VISUAL GAUNTLET
---------------------------------------------------------------
function Hijack:CreateGauntlet()
    self.Gauntlet = CreateFrame("Frame", "CPLightGauntlet", UIParent)
    self.Gauntlet:SetFrameStrata("TOOLTIP")
    self.Gauntlet:SetFrameLevel(200)
    self.Gauntlet:SetSize(32, 32)
    
    local tex = self.Gauntlet:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\CURSOR\\Point")
    self.Gauntlet.tex = tex
    
    self.Gauntlet.defaultSize = 32
    self.Gauntlet.pressedSize = 38
    self.Gauntlet:Hide()
end

function Hijack:SetGauntletPressed(pressed)
    if not self.Gauntlet then return end
    
    if pressed then
        self.Gauntlet.tex:SetTexture("Interface\\CURSOR\\Interact")
        self.Gauntlet:SetSize(self.Gauntlet.pressedSize, self.Gauntlet.pressedSize)
    else
        self.Gauntlet.tex:SetTexture("Interface\\CURSOR\\Point")
        self.Gauntlet:SetSize(self.Gauntlet.defaultSize, self.Gauntlet.defaultSize)
    end
end

---------------------------------------------------------------
-- 5. SECURE BUTTON (Proxy Click + Navigation)
---------------------------------------------------------------
function Hijack:CreateSecureButton()
    local btn = CreateFrame("Button", "CPLightSecureClick", UIParent, "SecureActionButtonTemplate")
    self.ClickButton = btn
    
    btn:RegisterForClicks("AnyUp")
    btn:SetSize(1, 1)
    btn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    btn:SetAlpha(0)
    btn:Show()
    
    -- PreClick: Move cursor to gauntlet position
    btn:SetScript("PreClick", function(self, button)
        if button == "LeftButton" or button == "RightButton" then
            if Hijack.Gauntlet and Hijack.Gauntlet:IsVisible() and Hijack.CurrentNode then
                local x, y = Hijack.Gauntlet:GetCenter()
                if x and y then
                    -- Anniversary client requires screen coordinates (not scaled UI coordinates)
                    local scale = UIParent:GetEffectiveScale()
                    local screenX = x * scale
                    local screenY = y * scale
                    SetCursor(screenX, screenY)
                end
                Hijack:SetGauntletPressed(true)
            end
        end
    end)
    
    btn:SetScript("PostClick", function(self, button)
        if button == "LeftButton" or button == "RightButton" then
            Hijack:SetGauntletPressed(false)
        end
    end)
    
    -- Handle D-Pad navigation via button parameter
    local hijackModule = self
    btn:SetScript("OnClick", function(secureBtn, button)
        if button == "UP" then
            hijackModule:Navigate("UP")
        elseif button == "DOWN" then
            hijackModule:Navigate("DOWN")
        elseif button == "LEFT" then
            hijackModule:Navigate("LEFT")
        elseif button == "RIGHT" then
            hijackModule:Navigate("RIGHT")
        end
    end)
end