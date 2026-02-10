-- VendorSniper: Auto-buy limited-supply vendor items on restock
-- Park an alt at a vendor, pick items to watch, auto-buy when they restock

local ADDON_NAME, VS = ...

local ADDON_PREFIX = "|cFF33CCFF[VendorSniper]|r "
local GetMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
local VERSION = GetMetadata and GetMetadata(ADDON_NAME, "Version") or "dev"
if VERSION:find("^@") then VERSION = "dev" end

local LDB = LibStub("LibDataBroker-1.1")
local LDBIcon = LibStub("LibDBIcon-1.0")

--------------------------------------------------------------
-- Constants
--------------------------------------------------------------

local FRAME_WIDTH = 320
local FRAME_HEIGHT = 320
local ROW_HEIGHT = 26
local VISIBLE_ROWS = 8
local HEADER_HEIGHT = 36
local FOOTER_HEIGHT = 42
local AUTO_CLOSE_DELAY = 2
local ALERT_SOUND_ID = 8959 -- Raid warning
local DEFAULT_ALERT_DURATION = 5

--------------------------------------------------------------
-- State
--------------------------------------------------------------

VendorSniperDB = VendorSniperDB or {}

local isWatching = false
local merchantOpen = false
local currentVendorID = nil
local currentVendorGUID = nil
local currentVendorName = nil
local autoCloseTimer = nil
local limitedItems = {} -- scanned limited supply items
local mode = "setup" -- "setup" or "monitoring"

--------------------------------------------------------------
-- DB
--------------------------------------------------------------

local function InitializeDB()
    VendorSniperDB.minimap = VendorSniperDB.minimap or { hide = false }
    VendorSniperDB.position = VendorSniperDB.position or nil
    VendorSniperDB.autoClose = VendorSniperDB.autoClose ~= false -- default true
    VendorSniperDB.autoCloseDelay = VendorSniperDB.autoCloseDelay or AUTO_CLOSE_DELAY
    VendorSniperDB.alertDuration = VendorSniperDB.alertDuration or DEFAULT_ALERT_DURATION
    VendorSniperDB.vendors = VendorSniperDB.vendors or {}
    VendorSniperDB.log = VendorSniperDB.log or {}
end

--------------------------------------------------------------
-- Utility
--------------------------------------------------------------

local function GetNPCIDFromGUID(guid)
    if not guid then return nil end
    local npcID = select(6, strsplit("-", guid))
    return npcID and tonumber(npcID)
end

local function GetVendorData()
    if not currentVendorID then return nil end
    return VendorSniperDB.vendors[currentVendorID]
end

local function GetOrCreateVendorData()
    if not currentVendorID then return nil end
    if not VendorSniperDB.vendors[currentVendorID] then
        VendorSniperDB.vendors[currentVendorID] = {
            name = currentVendorName or "Unknown",
            items = {},
        }
    end
    return VendorSniperDB.vendors[currentVendorID]
end

local function HasActiveWatchlist()
    local vendor = GetVendorData()
    if not vendor then return false end
    for _, data in pairs(vendor.items) do
        if data.target > data.bought then
            return true
        end
    end
    return false
end

local function GetWatchedCount()
    local vendor = GetVendorData()
    if not vendor then return 0 end
    local count = 0
    for _, data in pairs(vendor.items) do
        if data.target > data.bought then
            count = count + 1
        end
    end
    return count
end

local function IsItemWatched(itemId)
    local vendor = GetVendorData()
    if not vendor or not vendor.items[itemId] then return false end
    return vendor.items[itemId].target > vendor.items[itemId].bought
end

--------------------------------------------------------------
-- Merchant Scanning
--------------------------------------------------------------

local function ScanMerchant()
    wipe(limitedItems)
    local numItems = GetMerchantNumItems()
    for i = 1, numItems do
        local name, texture, price, quantity, numAvailable, isUsable, extendedCost = GetMerchantItemInfo(i)
        if numAvailable ~= -1 then
            local itemLink = GetMerchantItemLink(i)
            local itemId = itemLink and tonumber(itemLink:match("item:(%d+)"))
            if itemId then
                tinsert(limitedItems, {
                    index = i,
                    itemId = itemId,
                    name = name,
                    texture = texture,
                    price = price,
                    quantity = quantity,
                    numAvailable = numAvailable,
                    isUsable = isUsable,
                })
            end
        end
    end
    return limitedItems
end

--------------------------------------------------------------
-- Purchase Logic
--------------------------------------------------------------

local function BuyWatchedItems()
    local vendor = GetVendorData()
    if not vendor or not vendor.items then return false end

    local numItems = GetMerchantNumItems()
    local anyBought = false

    for i = 1, numItems do
        local name, texture, price, quantity, numAvailable, isUsable, extendedCost = GetMerchantItemInfo(i)
        -- numAvailable: -1 = unlimited, 0 = out of stock, >0 = limited in stock
        local isAvailable = numAvailable == -1 or numAvailable > 0
        if isAvailable then
            local itemLink = GetMerchantItemLink(i)
            local itemId = itemLink and tonumber(itemLink:match("item:(%d+)"))

            if itemId and vendor.items[itemId] then
                local watchData = vendor.items[itemId]
                local remaining = watchData.target - watchData.bought

                if remaining > 0 then
                    if GetMoney() >= price then
                        local canBuy = numAvailable == -1 and remaining or math.min(remaining, numAvailable)
                        for j = 1, canBuy do
                            BuyMerchantItem(i, 1)
                        end
                        watchData.bought = watchData.bought + canBuy

                        tinsert(VendorSniperDB.log, {
                            itemId = itemId,
                            itemName = name,
                            vendorName = currentVendorName,
                            price = price * canBuy,
                            count = canBuy,
                            time = time(),
                        })

                        local complete = watchData.bought >= watchData.target
                        VS:PlayAlert(name, canBuy, complete)

                        if complete then
                            vendor.items[itemId] = nil
                        end

                        anyBought = true
                    else
                        print(ADDON_PREFIX .. "|cFFFF0000Not enough gold|r for " .. (name or "item") .. "!")
                    end
                end
            end
        end
    end

    -- Re-scan to update stock counts after purchases
    if anyBought then
        ScanMerchant()
    end

    -- Check if all targets complete
    if isWatching and not HasActiveWatchlist() then
        VS:StopWatching()
        print(ADDON_PREFIX .. "|cFF00FF00All targets complete!|r")
    end

    return anyBought
end

--------------------------------------------------------------
-- Alert System
--------------------------------------------------------------

local soundTicker = nil

function VS:PlayAlert(itemName, count, complete)
    local countStr = count > 1 and (count .. "x ") or ""
    local completeStr = complete and " (COMPLETE)" or ""
    local msg = "VendorSniper: Bought " .. countStr .. (itemName or "item") .. completeStr

    RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
    print(ADDON_PREFIX .. "|cFF00FF00Bought|r " .. countStr .. (itemName or "item") .. (complete and " |cFF00FF00(COMPLETE)|r" or ""))

    -- Looping sound
    if soundTicker then
        soundTicker:Cancel()
    end
    local duration = VendorSniperDB.alertDuration or DEFAULT_ALERT_DURATION
    local elapsed = 0

    PlaySound(ALERT_SOUND_ID, "Master")
    soundTicker = C_Timer.NewTicker(1.5, function()
        elapsed = elapsed + 1.5
        if elapsed >= duration then
            soundTicker:Cancel()
            soundTicker = nil
            return
        end
        PlaySound(ALERT_SOUND_ID, "Master")
    end)
end

--------------------------------------------------------------
-- Auto-close (after scan/buy, prepare for external reopen)
--------------------------------------------------------------

local function ScheduleAutoClose()
    if not VendorSniperDB.autoClose then return end
    if not merchantOpen then return end
    if autoCloseTimer then
        autoCloseTimer:Cancel()
    end
    local delay = VendorSniperDB.autoCloseDelay or AUTO_CLOSE_DELAY
    autoCloseTimer = C_Timer.NewTimer(delay, function()
        autoCloseTimer = nil
        if merchantOpen and isWatching then
            CloseMerchant()
        end
    end)
end

--------------------------------------------------------------
-- Watching Control
--------------------------------------------------------------

function VS:StartWatching()
    if isWatching then return end
    if not HasActiveWatchlist() then
        print(ADDON_PREFIX .. "No items to watch!")
        return
    end

    isWatching = true
    mode = "monitoring"
    self:UpdateFrame()
    print(ADDON_PREFIX .. "Sniping started")

    -- Immediate scan+buy if vendor is already open
    if merchantOpen then
        ScanMerchant()
        BuyWatchedItems()
        self:UpdateFrame()
        ScheduleAutoClose()
    end
end

function VS:StopWatching()
    isWatching = false
    if autoCloseTimer then
        autoCloseTimer:Cancel()
        autoCloseTimer = nil
    end
    mode = "setup"
    self:UpdateFrame()
    print(ADDON_PREFIX .. "Sniping stopped")
end

--------------------------------------------------------------
-- Merchant Event Handlers
--------------------------------------------------------------

function VS:OnMerchantShow()
    merchantOpen = true

    local guid = UnitGUID("npc")
    currentVendorGUID = guid
    currentVendorID = GetNPCIDFromGUID(guid)
    currentVendorName = UnitName("npc")

    ScanMerchant()

    if isWatching then
        local bought = BuyWatchedItems()
        self:UpdateFrame()
        ScheduleAutoClose()
    elseif #limitedItems > 0 or HasActiveWatchlist() then
        mode = "setup"
        self:ShowFrame()
        self:UpdateFrame()
    end
end

function VS:OnMerchantClose()
    merchantOpen = false
    if autoCloseTimer then
        autoCloseTimer:Cancel()
        autoCloseTimer = nil
    end
    self:UpdateFrame()
end

--------------------------------------------------------------
-- Quantity Popup
--------------------------------------------------------------

StaticPopupDialogs["VENDORSNIPER_QUANTITY"] = {
    text = "How many to snipe?\n\n%s",
    button1 = "OK",
    button2 = "Cancel",
    hasEditBox = true,
    OnShow = function(self)
        self.editBox:SetText("1")
        self.editBox:HighlightText()
        self.editBox:SetFocus()
    end,
    OnAccept = function(self)
        local qty = tonumber(self.editBox:GetText())
        if qty and qty > 0 then
            VS:SetWatch(VS._pendingItemId, VS._pendingItemName, math.floor(qty))
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local qty = tonumber(self:GetText())
        if qty and qty > 0 then
            VS:SetWatch(VS._pendingItemId, VS._pendingItemName, math.floor(qty))
        end
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

--------------------------------------------------------------
-- Watchlist Management
--------------------------------------------------------------

function VS:SetWatch(itemId, itemName, quantity)
    if not itemId then return end
    local vendor = GetOrCreateVendorData()
    if not vendor then return end

    vendor.items[itemId] = {
        name = itemName or "Unknown",
        target = quantity,
        bought = 0,
    }
    self:UpdateFrame()
end

function VS:RemoveWatch(itemId)
    local vendor = GetVendorData()
    if not vendor then return end
    vendor.items[itemId] = nil
    self:UpdateFrame()
end

function VS:ToggleWatch(itemId, itemName)
    if IsItemWatched(itemId) then
        self:RemoveWatch(itemId)
    else
        if IsShiftKeyDown() then
            self._pendingItemId = itemId
            self._pendingItemName = itemName
            StaticPopup_Show("VENDORSNIPER_QUANTITY", itemName or "item")
        else
            self:SetWatch(itemId, itemName, 1)
        end
    end
end

function VS:WatchByLink(itemLink)
    if not currentVendorID then
        print(ADDON_PREFIX .. "Open a vendor first!")
        return
    end
    if not itemLink then
        print(ADDON_PREFIX .. "Usage: /vs watch [itemlink] or /vs watch [itemId]")
        return
    end

    local itemId = tonumber(itemLink:match("item:(%d+)"))
    if not itemId then
        -- Try as plain number
        itemId = tonumber(itemLink)
    end
    if not itemId then
        print(ADDON_PREFIX .. "Could not parse item. Use shift-click to insert an item link.")
        return
    end

    local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemId)
    self:SetWatch(itemId, itemName or ("Item " .. itemId), 1)
    print(ADDON_PREFIX .. "Watching: " .. (itemName or ("Item " .. itemId)))
    self:ShowFrame()
end

function VS:ClearWatchlist()
    local vendor = GetVendorData()
    if not vendor then return end
    wipe(vendor.items)
    if isWatching then
        self:StopWatching()
    end
    self:UpdateFrame()
    print(ADDON_PREFIX .. "Watchlist cleared")
end

--------------------------------------------------------------
-- UI: Main Frame
--------------------------------------------------------------

function VS:CreateMainFrame()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "VendorSniperFrame", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local point, _, relPoint, xOfs, yOfs = frame:GetPoint()
        VendorSniperDB.position = { point = point, relPoint = relPoint, x = xOfs, y = yOfs }
    end)
    f:Hide()

    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

    if VendorSniperDB.position then
        local pos = VendorSniperDB.position
        f:ClearAllPoints()
        f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    end

    self:BuildHeader(f)
    self:BuildScrollList(f)
    self:BuildFooter(f)

    tinsert(UISpecialFrames, "VendorSniperFrame")
    self.frame = f
    return f
end

--------------------------------------------------------------
-- UI: Header
--------------------------------------------------------------

function VS:BuildHeader(parent)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("VendorSniper")
    title:SetTextColor(0.2, 0.8, 1.0)
    self.titleText = title

    local closeBtn = CreateFrame("Button", nil, parent, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)

    -- Status text (vendor name / mode)
    local status = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    status:SetPoint("TOPLEFT", 12, -28)
    status:SetTextColor(0.7, 0.7, 0.7)
    self.statusText = status
end

--------------------------------------------------------------
-- UI: Scroll List
--------------------------------------------------------------

function VS:BuildScrollList(parent)
    local scrollFrame = CreateFrame("ScrollFrame", "VendorSniperScrollFrame", parent, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -(HEADER_HEIGHT + 8))
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, FOOTER_HEIGHT + 5)
    self.scrollFrame = scrollFrame

    parent.rows = {}
    for i = 1, VISIBLE_ROWS do
        parent.rows[i] = self:CreateRow(parent, i)
    end
    self.rows = parent.rows

    scrollFrame:SetScript("OnVerticalScroll", function(sf, offset)
        FauxScrollFrame_OnVerticalScroll(sf, offset, ROW_HEIGHT, function()
            VS:UpdateList()
        end)
    end)

    local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyText:SetPoint("CENTER", scrollFrame, "CENTER", 0, 0)
    emptyText:SetTextColor(0.5, 0.5, 0.5)
    emptyText:SetText("No limited-supply items")
    emptyText:Hide()
    self.emptyText = emptyText
end

function VS:CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(FRAME_WIDTH - 50, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", self.scrollFrame, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))

    -- Checkbox (setup mode)
    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(22, 22)
    row.check:SetPoint("LEFT", 0, 0)
    row.check:SetScript("OnClick", function(cb)
        -- Undo the default toggle, we handle it ourselves
        cb:SetChecked(not cb:GetChecked())
        if row.itemId then
            VS:ToggleWatch(row.itemId, row.itemName)
        end
    end)

    -- Icon
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", row.check, "RIGHT", 2, 0)

    -- Name
    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    row.nameText:SetWidth(160)
    row.nameText:SetJustifyH("LEFT")

    -- Stock / progress
    row.infoText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.infoText:SetPoint("RIGHT", -5, 0)
    row.infoText:SetJustifyH("RIGHT")

    -- Hover highlight
    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.08)

    -- Click handler for the whole row
    row:EnableMouse(true)
    row:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and self.itemId and mode == "setup" then
            VS:ToggleWatch(self.itemId, self.itemName)
        end
    end)

    -- Tooltip
    row:SetScript("OnEnter", function(self)
        if self.itemId then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. self.itemId)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return row
end

--------------------------------------------------------------
-- UI: Footer
--------------------------------------------------------------

function VS:BuildFooter(parent)
    -- Action button (Start Watching / Stop)
    local actionBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    actionBtn:SetSize(140, 24)
    actionBtn:SetPoint("BOTTOM", 0, 10)
    actionBtn:SetText("Start Watching")
    actionBtn:SetScript("OnClick", function()
        if isWatching then
            VS:StopWatching()
        else
            VS:StartWatching()
        end
    end)
    self.actionBtn = actionBtn

    -- Refresh status
    local refreshText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    refreshText:SetPoint("BOTTOMLEFT", 8, 38)
    refreshText:SetTextColor(0.5, 0.5, 0.5)
    self.refreshText = refreshText
end

--------------------------------------------------------------
-- UI: Update Functions
--------------------------------------------------------------

function VS:UpdateFrame()
    if not self.frame then return end
    if not self.frame:IsShown() then return end

    self:UpdateHeader()
    self:UpdateList()
    self:UpdateFooter()
end

function VS:UpdateHeader()
    if not self.statusText then return end

    if mode == "monitoring" then
        self.titleText:SetText("VendorSniper")
        self.titleText:SetTextColor(0.0, 1.0, 0.4)
        local vendorName = currentVendorName or "Unknown"
        self.statusText:SetText("SNIPING - " .. vendorName)
        self.statusText:SetTextColor(0.0, 1.0, 0.4)
    else
        self.titleText:SetText("VendorSniper")
        self.titleText:SetTextColor(0.2, 0.8, 1.0)
        if currentVendorName then
            local scanCount = #limitedItems
            local watchCount = GetWatchedCount()
            local parts = {}
            if scanCount > 0 then tinsert(parts, scanCount .. " limited") end
            if watchCount > 0 then tinsert(parts, watchCount .. " watched") end
            local suffix = #parts > 0 and (" - " .. table.concat(parts, ", ")) or ""
            self.statusText:SetText(currentVendorName .. suffix)
        else
            self.statusText:SetText("")
        end
        self.statusText:SetTextColor(0.7, 0.7, 0.7)
    end
end

function VS:UpdateList()
    if not self.frame or not self.frame:IsShown() then return end
    if not self.scrollFrame then return end

    local items
    if mode == "monitoring" then
        -- Show only watched items
        items = {}
        local vendor = GetVendorData()
        if vendor then
            for itemId, data in pairs(vendor.items) do
                if data.target > data.bought then
                    -- Find texture from limitedItems scan
                    local tex = "Interface\\Icons\\INV_Misc_QuestionMark"
                    for _, li in ipairs(limitedItems) do
                        if li.itemId == itemId then
                            tex = li.texture
                            break
                        end
                    end
                    tinsert(items, {
                        itemId = itemId,
                        name = data.name,
                        texture = tex,
                        bought = data.bought,
                        target = data.target,
                    })
                end
            end
        end
    else
        -- Merge scanned limited items + persisted watchlist items not in scan
        items = {}
        local seen = {}
        for _, li in ipairs(limitedItems) do
            tinsert(items, li)
            if li.itemId then
                seen[li.itemId] = true
            end
        end
        -- Add watchlist items that aren't currently in the vendor
        local vendor = GetVendorData()
        if vendor then
            for itemId, data in pairs(vendor.items) do
                if not seen[itemId] and data.target > data.bought then
                    local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemId)
                    tinsert(items, {
                        itemId = itemId,
                        name = data.name,
                        texture = itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark",
                        numAvailable = nil, -- not in vendor currently
                        isWatchlistOnly = true,
                    })
                end
            end
        end
    end

    local numItems = #items
    local offset = FauxScrollFrame_GetOffset(self.scrollFrame)

    FauxScrollFrame_Update(self.scrollFrame, numItems, VISIBLE_ROWS, ROW_HEIGHT)

    for i = 1, VISIBLE_ROWS do
        local row = self.rows[i]
        local index = offset + i
        local item = items[index]

        if item then
            row.itemId = item.itemId
            row.itemName = item.name

            row.icon:SetTexture(item.texture)
            row.nameText:SetText(item.name)

            if mode == "monitoring" then
                row.check:Hide()
                row.icon:SetPoint("LEFT", 4, 0)
                row.infoText:SetText(item.bought .. "/" .. item.target)
                row.infoText:SetTextColor(0.6, 0.8, 1.0)
            else
                row.check:Show()
                row.icon:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
                row.check:SetChecked(IsItemWatched(item.itemId))

                if item.isWatchlistOnly then
                    row.infoText:SetText("(not in vendor)")
                    row.infoText:SetTextColor(1.0, 0.6, 0.2)
                    row.nameText:SetTextColor(1.0, 0.6, 0.2)
                elseif item.numAvailable and item.numAvailable > 0 then
                    row.infoText:SetText("(" .. item.numAvailable .. ")")
                    row.infoText:SetTextColor(0.0, 1.0, 0.0)
                    row.nameText:SetTextColor(0.0, 1.0, 0.0)
                else
                    row.infoText:SetText("(0)")
                    row.infoText:SetTextColor(0.5, 0.5, 0.5)
                    row.nameText:SetTextColor(1.0, 1.0, 1.0)
                end
            end

            row:Show()
        else
            row.itemId = nil
            row.itemName = nil
            row:Hide()
        end
    end

    if numItems == 0 then
        if mode == "monitoring" then
            self.emptyText:SetText("No items being watched")
        else
            self.emptyText:SetText("No limited-supply items at this vendor")
        end
        self.emptyText:Show()
    else
        self.emptyText:Hide()
    end
end

function VS:UpdateFooter()
    if not self.actionBtn then return end

    if mode == "monitoring" then
        self.actionBtn:SetText("Stop")

        if not merchantOpen then
            self.refreshText:SetText("|cFFFF4444PAUSED|r - reopen vendor")
        else
            self.refreshText:SetText("|cFF00FF00Active|r - " .. GetWatchedCount() .. " item(s) watched")
        end
    else
        local count = GetWatchedCount()
        if count > 0 then
            self.actionBtn:SetText("Start Watching (" .. count .. ")")
            self.actionBtn:Enable()
        else
            self.actionBtn:SetText("Select items to watch")
            self.actionBtn:Disable()
        end
        self.refreshText:SetText("Click items to watch. Shift-click for quantity.")
    end
end

--------------------------------------------------------------
-- Frame Show/Hide/Toggle
--------------------------------------------------------------

function VS:ShowFrame()
    if not self.frame then
        self:CreateMainFrame()
    end
    self.frame:Show()
    self:UpdateFrame()
end

function VS:HideFrame()
    if self.frame then
        self.frame:Hide()
    end
end

function VS:ToggleFrame()
    if self.frame and self.frame:IsShown() then
        self:HideFrame()
    else
        self:ShowFrame()
    end
end

--------------------------------------------------------------
-- Minimap Button
--------------------------------------------------------------

local dataObject = LDB:NewDataObject("VendorSniper", {
    type = "launcher",
    icon = "Interface\\Icons\\INV_Misc_SpyGlass_03",
    OnClick = function(_, button)
        if button == "LeftButton" then
            VS:ToggleFrame()
        elseif button == "RightButton" then
            if isWatching then
                VS:StopWatching()
            else
                VS:StartWatching()
            end
        end
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine("VendorSniper", 0.2, 0.8, 1.0)
        tooltip:AddLine(" ")
        local status = isWatching and "|cFF00FF00SNIPING|r" or "|cFFFF0000OFF|r"
        tooltip:AddLine("Status: " .. status, 1, 1, 1)
        local count = GetWatchedCount()
        if count > 0 then
            tooltip:AddLine("Watching: " .. count .. " item(s)", 0.7, 0.7, 0.7)
        end
        tooltip:AddLine(" ")
        tooltip:AddLine("|cFFFFFFFFLeft-click:|r Toggle window", 0.7, 0.7, 0.7)
        tooltip:AddLine("|cFFFFFFFFRight-click:|r Toggle sniping", 0.7, 0.7, 0.7)
    end,
})

--------------------------------------------------------------
-- Slash Commands
--------------------------------------------------------------

SLASH_VENDORSNIPER1 = "/vs"
SLASH_VENDORSNIPER2 = "/vendorsniper"

SlashCmdList["VENDORSNIPER"] = function(msg)
    local rawMsg = msg and strtrim(msg) or ""
    msg = strlower(rawMsg)

    if msg == "" then
        VS:ToggleFrame()

    elseif msg == "start" then
        VS:StartWatching()

    elseif msg == "stop" then
        VS:StopWatching()

    elseif msg == "clear" then
        VS:ClearWatchlist()

    elseif msg == "status" then
        local status = isWatching and "|cFF00FF00SNIPING|r" or "|cFFFF0000OFF|r"
        print(ADDON_PREFIX .. "Status: " .. status)
        if currentVendorName then
            print(ADDON_PREFIX .. "Vendor: " .. currentVendorName)
        end
        local count = GetWatchedCount()
        print(ADDON_PREFIX .. "Watching: " .. count .. " item(s)")
        -- Show watched items
        local vendor = GetVendorData()
        if vendor then
            for itemId, data in pairs(vendor.items) do
                if data.target > data.bought then
                    print(ADDON_PREFIX .. "  " .. data.name .. " " .. data.bought .. "/" .. data.target)
                end
            end
        end

    elseif msg == "log" then
        if #VendorSniperDB.log == 0 then
            print(ADDON_PREFIX .. "No purchases logged yet")
        else
            print(ADDON_PREFIX .. "Purchase log:")
            for i = math.max(1, #VendorSniperDB.log - 9), #VendorSniperDB.log do
                local entry = VendorSniperDB.log[i]
                local gold = math.floor(entry.price / 10000)
                print(ADDON_PREFIX .. "  " .. (entry.count or 1) .. "x " .. entry.itemName .. " (" .. gold .. "g) from " .. entry.vendorName)
            end
        end

    elseif msg == "autoclose" then
        VendorSniperDB.autoClose = not VendorSniperDB.autoClose
        print(ADDON_PREFIX .. "Auto-close: " .. (VendorSniperDB.autoClose and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"))

    elseif msg:match("^watch%s+") then
        local linkOrId = strtrim(rawMsg:match("^%w+%s+(.+)"))
        VS:WatchByLink(linkOrId)

    else
        print(ADDON_PREFIX .. "v" .. VERSION .. " Commands:")
        print("  /vs - Toggle window")
        print("  /vs watch [itemlink] - Add item to watchlist")
        print("  /vs start - Start sniping")
        print("  /vs stop - Stop sniping")
        print("  /vs clear - Clear watchlist")
        print("  /vs status - Show status")
        print("  /vs log - Show purchase log")
        print("  /vs autoclose - Toggle auto-close after scan")
    end
end

--------------------------------------------------------------
-- Events
--------------------------------------------------------------

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("MERCHANT_SHOW")
eventFrame:RegisterEvent("MERCHANT_CLOSED")
eventFrame:RegisterEvent("MERCHANT_UPDATE")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        InitializeDB()
        LDBIcon:Register("VendorSniper", dataObject, VendorSniperDB.minimap)
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        print(ADDON_PREFIX .. "v" .. VERSION .. " loaded. Type |cFFFFFF00/vs|r for options.")
        self:UnregisterEvent("PLAYER_LOGIN")

    elseif event == "MERCHANT_SHOW" then
        VS:OnMerchantShow()

    elseif event == "MERCHANT_CLOSED" then
        VS:OnMerchantClose()

    elseif event == "MERCHANT_UPDATE" then
        -- Fires when merchant inventory changes (restock, purchase, etc.)
        if isWatching and merchantOpen then
            ScanMerchant()
            BuyWatchedItems()
            VS:UpdateFrame()
        end
    end
end)
