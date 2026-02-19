-- AutoBuy.lua: Automation module (git-only, excluded from CurseForge/Wago package)
-- Adds auto-buy on vendor open, snipe mode (auto-close), and MERCHANT_UPDATE auto-buy
-- This file is loaded by VendorSniper.toc but excluded via .pkgmeta
-- Without this file, Core.lua works standalone with alert + Buy All button

local ADDON_NAME, VS = ...

local ADDON_PREFIX = "|cFF33CCFF[VendorSniper]|r "
local AUTO_CLOSE_DELAY = 2

--------------------------------------------------------------
-- State
--------------------------------------------------------------

local autoCloseTimer = nil

--------------------------------------------------------------
-- Snipe Mode
--------------------------------------------------------------

local function ScheduleAutoClose()
    if not VS.sniping then return end
    if not VS.merchantOpen then return end
    if autoCloseTimer then
        autoCloseTimer:Cancel()
    end
    local delay = VendorSniperDB.autoCloseDelay or AUTO_CLOSE_DELAY
    autoCloseTimer = C_Timer.NewTimer(delay, function()
        autoCloseTimer = nil
        if VS.merchantOpen and VS.sniping then
            CloseMerchant()
        end
    end)
end

function VS:StartSniping()
    if VS.sniping then return end
    if not VS.HasActiveWatchlist() then
        print(ADDON_PREFIX .. "Watchlist is empty. Add items first.")
        return
    end

    VS.sniping = true
    self:UpdateFrame()
    local delay = VendorSniperDB.autoCloseDelay or AUTO_CLOSE_DELAY
    print(ADDON_PREFIX .. "|cFF00FF00Snipe mode started.|r Auto-closing vendor every " .. delay .. "s.")

    if VS.merchantOpen then
        ScheduleAutoClose()
    end
end

function VS:StopSniping()
    VS.sniping = false
    if autoCloseTimer then
        autoCloseTimer:Cancel()
        autoCloseTimer = nil
    end
    self:UpdateFrame()
    print(ADDON_PREFIX .. "Snipe mode stopped.")
end

--------------------------------------------------------------
-- Slash command hook: /vs snipe
--------------------------------------------------------------

function VS:ToggleSnipe()
    if VS.sniping then
        self:StopSniping()
    else
        self:StartSniping()
    end
end

--------------------------------------------------------------
-- Callback: All watchlist targets complete
--------------------------------------------------------------

function VS:OnAllTargetsComplete()
    if VS.sniping then
        VS:StopSniping()
    end
end

--------------------------------------------------------------
-- Callback: After merchant opens - auto-buy + start auto-close
--------------------------------------------------------------

function VS:OnMerchantShowPost()
    -- Auto-buy watchlist items if any are in stock
    if VS.HasActiveWatchlist() then
        VS:BuyWatchedItems()
        VS:UpdateFrame()
    end

    -- Auto-close for snipe loop
    ScheduleAutoClose()
end

--------------------------------------------------------------
-- Callback: After merchant closes - cancel auto-close timer
--------------------------------------------------------------

function VS:OnMerchantClosePost()
    if autoCloseTimer then
        autoCloseTimer:Cancel()
        autoCloseTimer = nil
    end
end

--------------------------------------------------------------
-- Callback: After MERCHANT_UPDATE - auto-buy on restock
--------------------------------------------------------------

function VS:OnMerchantUpdatePost()
    if VS.HasActiveWatchlist() then
        VS:BuyWatchedItems()
        VS:UpdateFrame()
    end
end
