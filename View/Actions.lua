---------------------------------------------------------------
-- Actions.lua: Smart UI interaction handler for CPLight
---------------------------------------------------------------
-- Provides intelligent click handling for inventory, spells,
-- merchants, and other UI elements. Decoupled from navigation
-- for modularity and future addon support.

local ADDON_NAME, addon = ...
local Actions = LibStub("AceAddon-3.0"):GetAddon("CPLight"):NewModule("Actions", "AceEvent-3.0")

---------------------------------------------------------------
-- State Tracking
---------------------------------------------------------------
Actions.MerchantOpen = false
Actions.TradeOpen = false

---------------------------------------------------------------
-- Event Handlers (Lazy Context Detection)
---------------------------------------------------------------
function Actions:OnEnable()
	self:RegisterEvent("MERCHANT_SHOW", "OnMerchantShow")
	self:RegisterEvent("MERCHANT_CLOSED", "OnMerchantClosed")
	self:RegisterEvent("TRADE_SHOW", "OnTradeShow")
	self:RegisterEvent("TRADE_CLOSED", "OnTradeClosed")
end

function Actions:OnMerchantShow()
	self.MerchantOpen = true
end

function Actions:OnMerchantClosed()
	self.MerchantOpen = false
end

function Actions:OnTradeShow()
	self.TradeOpen = true
end

function Actions:OnTradeClosed()
	self.TradeOpen = false
end

---------------------------------------------------------------
-- Button Type Detection (2.5.5 Compatible)
---------------------------------------------------------------
function Actions:GetButtonType(button)
	if not button or not button.GetName then return "unknown" end
	
	local name = button:GetName()
	if not name then return "unknown" end
	
	-- Spell Book buttons
	if name:match("^SpellButton%d+") then
		return "spellbook"
	end
	
	-- Container (bag) item buttons
	if name:match("^ContainerFrame%d+Item%d+") then
		return "container"
	end
	
	-- Character equipment slots
	if name:match("^Character.+Slot$") then
		return "equipment"
	end
	
	-- Merchant buttons
	if name:match("^MerchantItem%d+") then
		return "merchant"
	end
	
	-- Trade buttons
	if name:match("^TradePlayerItem%d+") or name:match("^TradeRecipientItem%d+") then
		return "trade"
	end
	
	-- Generic button (just click it)
	return "generic"
end

---------------------------------------------------------------
-- Container Item Detection (2.5.5 API)
---------------------------------------------------------------
function Actions:GetContainerInfo(button)
	if not button then return nil end
	
	-- TBC uses GetContainerItemInfo(bag, slot)
	local bagID = button:GetParent():GetID()
	local slotID = button:GetID()
	
	if not bagID or not slotID then return nil end
	
	-- Returns: texture, itemCount, locked, quality, readable, lootable, link, filtered, noValue, itemID
	local texture, count, locked, quality, readable, lootable, link = GetContainerItemInfo(bagID, slotID)
	
	if not texture then return nil end
	
	return {
		bagID = bagID,
		slotID = slotID,
		texture = texture,
		count = count,
		locked = locked,
		quality = quality,
		link = link,
	}
end

---------------------------------------------------------------
-- Smart Action Execution (Primary Logic)
---------------------------------------------------------------
function Actions:ExecuteAction(button, clickType)
	if not button or InCombatLockdown() then return false end
	
	local buttonType = self:GetButtonType(button)
	clickType = clickType or "LeftButton"
	
	-- Route to appropriate handler
	if buttonType == "spellbook" then
		return self:HandleSpellBook(button, clickType)
		
	elseif buttonType == "container" then
		return self:HandleContainer(button, clickType)
		
	elseif buttonType == "equipment" then
		return self:HandleEquipment(button, clickType)
		
	elseif buttonType == "merchant" then
		return self:HandleMerchant(button, clickType)
		
	elseif buttonType == "trade" then
		return self:HandleTrade(button, clickType)
		
	else
		-- Generic fallback: just click it
		return self:HandleGeneric(button, clickType)
	end
end

---------------------------------------------------------------
-- Handler: SpellBook
---------------------------------------------------------------
function Actions:HandleSpellBook(button, clickType)
	local spellID = button:GetID()
	
	if clickType == "LeftButton" then
		-- Cast spell or learn talent
		CastSpell(spellID, SpellBookFrame.bookType)
		return true
		
	elseif clickType == "RightButton" then
		-- Toggle spell details (if available)
		ToggleSpellBook(SpellBookFrame.bookType)
		return true
	end
	
	return false
end

---------------------------------------------------------------
-- Handler: Container (Bags)
---------------------------------------------------------------
function Actions:HandleContainer(button, clickType)
	local itemInfo = self:GetContainerInfo(button)
	if not itemInfo then return false end
	
	if clickType == "LeftButton" then
		-- Use item OR sell to merchant OR equip
		if self.MerchantOpen then
			-- Sell item to merchant
			UseContainerItem(itemInfo.bagID, itemInfo.slotID)
			return true
		else
			-- Use/Equip item
			UseContainerItem(itemInfo.bagID, itemInfo.slotID)
			return true
		end
		
	elseif clickType == "RightButton" then
		-- Secondary action (pickup for trade/AH)
		if self.TradeOpen then
			ClickTradeButton(1) -- Assuming first trade slot
			return true
		else
			-- Pickup item
			PickupContainerItem(itemInfo.bagID, itemInfo.slotID)
			return true
		end
	end
	
	return false
end

---------------------------------------------------------------
-- Handler: Equipment Slot
---------------------------------------------------------------
function Actions:HandleEquipment(button, clickType)
	local slotID = button:GetID()
	
	if clickType == "LeftButton" then
		-- Unequip item (pickup)
		PickupInventoryItem(slotID)
		return true
		
	elseif clickType == "RightButton" then
		-- Show item in dressing room (if available)
		return false
	end
	
	return false
end

---------------------------------------------------------------
-- Handler: Merchant
---------------------------------------------------------------
function Actions:HandleMerchant(button, clickType)
	local merchantIndex = button:GetID()
	
	if clickType == "LeftButton" then
		-- Buy item
		BuyMerchantItem(merchantIndex)
		return true
		
	elseif clickType == "RightButton" then
		-- Buy stack (if applicable)
		local name, _, _, quantity = GetMerchantItemInfo(merchantIndex)
		if quantity and quantity > 1 then
			BuyMerchantItem(merchantIndex, quantity)
			return true
		end
	end
	
	return false
end

---------------------------------------------------------------
-- Handler: Trade Window
---------------------------------------------------------------
function Actions:HandleTrade(button, clickType)
	local tradeSlot = button:GetID()
	
	if clickType == "LeftButton" then
		-- Click trade slot (add/remove item)
		ClickTradeButton(tradeSlot)
		return true
		
	elseif clickType == "RightButton" then
		-- Cancel trade item
		ClickTradeButton(tradeSlot)
		return true
	end
	
	return false
end

---------------------------------------------------------------
-- Handler: Generic Fallback
---------------------------------------------------------------
function Actions:HandleGeneric(button, clickType)
	-- Just trigger the button's normal click behavior
	if button:IsEnabled() and button.Click then
		button:Click(clickType)
		return true
	end
	
	return false
end

---------------------------------------------------------------
-- Public API
---------------------------------------------------------------
function Actions:CanHandleButton(button)
	local buttonType = self:GetButtonType(button)
	return buttonType ~= "unknown"
end

function Actions:GetButtonContext(button)
	local buttonType = self:GetButtonType(button)
	local context = {
		type = buttonType,
		merchantOpen = self.MerchantOpen,
		tradeOpen = self.TradeOpen,
	}
	
	if buttonType == "container" then
		context.itemInfo = self:GetContainerInfo(button)
	end
	
	return context
end

return Actions
