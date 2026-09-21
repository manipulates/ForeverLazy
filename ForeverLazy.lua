local ADDON = "ForeverLazy"

ForeverLazyDB = ForeverLazyDB or {}

local defaults = {
    sellJunk = true,
    repair = true,
    useGuildRepair = false,
    verbose = true,
}

local function db()
    return ForeverLazyDB
end

local function applyDefaults()
    if type(ForeverVendorDB) == "table" then
        for k, v in pairs(ForeverVendorDB) do
            if ForeverLazyDB[k] == nil then
                ForeverLazyDB[k] = v
            end
        end
    end
    for k, v in pairs(defaults) do
        if ForeverLazyDB[k] == nil then
            ForeverLazyDB[k] = v
        end
    end
end

local function money(copper)
    copper = tonumber(copper) or 0
    if copper <= 0 then
        return "0c"
    end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

local function say(msg)
    if db().verbose then
        print("|cff88ccff" .. ADDON .. "|r " .. msg)
    end
end

local function bagMax()
    if NUM_TOTAL_EQUIPPED_BAG_SLOTS then
        return NUM_TOTAL_EQUIPPED_BAG_SLOTS
    end
    return (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0)
end

local function numSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    end
    return GetContainerNumSlots(bag) or 0
end

local function containerItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if type(info) == "table" then
            return info
        end
    end
    local icon, count, locked, quality, _, _, link, _, hasNoValue, itemID = GetContainerItemInfo(bag, slot)
    if not icon and not itemID then
        return nil
    end
    return {
        stackCount = count,
        isLocked = locked,
        quality = quality,
        hyperlink = link,
        hasNoValue = hasNoValue,
        itemID = itemID,
    }
end

local function useBagItem(bag, slot)
    if C_Container and C_Container.UseContainerItem then
        C_Container.UseContainerItem(bag, slot)
    else
        UseContainerItem(bag, slot)
    end
end

local function itemSellPrice(hyperlink)
    local infoFn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not infoFn or not hyperlink then
        return 0
    end
    return tonumber(select(11, infoFn(hyperlink))) or 0
end

local function merchantOpen()
    return MerchantFrame and MerchantFrame:IsShown()
end

local function sellJunk()
    if not db().sellJunk or not merchantOpen() then
        return 0, 0
    end

    local sold, copper = 0, 0
    for bag = 0, bagMax() do
        for slot = 1, numSlots(bag) do
            local info = containerItem(bag, slot)
            if info
                and info.quality == 0
                and info.hyperlink
                and not info.isLocked
                and not info.hasNoValue
            then
                local unit = itemSellPrice(info.hyperlink)
                useBagItem(bag, slot)
                sold = sold + (info.stackCount or 1)
                copper = copper + unit * (info.stackCount or 1)
            end
        end
    end
    return sold, copper
end

local function doRepair()
    if not db().repair then
        return false, 0, false
    end
    if not CanMerchantRepair or not CanMerchantRepair() then
        return false, 0, false
    end

    local cost = GetRepairAllCost() or 0
    if cost <= 0 then
        return false, 0, false
    end

    local usedGuild = false
    if db().useGuildRepair and CanGuildBankRepair and CanGuildBankRepair() then
        RepairAllItems(true)
        local remaining = GetRepairAllCost() or 0
        if remaining <= 0 then
            return true, cost, true
        end
        usedGuild = remaining < cost
        cost = remaining
    end

    if GetMoney() < cost then
        if usedGuild then
            say("Guild repair was partial. Need " .. money(cost) .. " more.")
        else
            say("Need " .. money(cost) .. " to repair. Skipping.")
        end
        return false, cost, false
    end
    RepairAllItems(false)
    return true, cost, false
end

local busy = false

local function onMerchant()
    if busy then
        return
    end
    busy = true

    C_Timer.After(0.15, function()
        local scheduled = false
        local ok, err = pcall(function()
            if not merchantOpen() then
                return
            end

            local repaired, cost, guild = doRepair()
            if repaired then
                if guild then
                    say("Repaired with guild funds (" .. money(cost) .. ").")
                else
                    say("Repaired for " .. money(cost) .. ".")
                end
            end

            local totalSold, totalCopper = 0, 0
            local function pass()
                local n, c = sellJunk()
                totalSold = totalSold + n
                totalCopper = totalCopper + c
            end
            pass()
            scheduled = true
            C_Timer.After(0.35, function()
                local laterOk, laterErr = pcall(function()
                    if merchantOpen() then
                        pass()
                    end
                    if totalSold > 0 then
                        say("Sold " .. totalSold .. " junk for " .. money(totalCopper) .. ".")
                    end
                end)
                busy = false
                if not laterOk then
                    print("|cff88ccff" .. ADDON .. "|r error: " .. tostring(laterErr))
                end
            end)
        end)

        if not scheduled then
            busy = false
        end
        if not ok then
            print("|cff88ccff" .. ADDON .. "|r error: " .. tostring(err))
        end
    end)
end

local settingsCategory

local function registerCheckbox(category, key, title, tooltip)
    local variable = ADDON .. "_" .. key
    local varType = (Settings.VarType and Settings.VarType.Boolean) or type(true)
    local setting = Settings.RegisterAddOnSetting(
        category,
        variable,
        key,
        ForeverLazyDB,
        varType,
        title,
        defaults[key]
    )
    Settings.CreateCheckbox(category, setting, tooltip)
    return setting
end

local function buildOptions()
    if settingsCategory then
        return
    end
    if not Settings or not Settings.RegisterVerticalLayoutCategory then
        return
    end

    applyDefaults()

    local category, layout = Settings.RegisterVerticalLayoutCategory("Forever Lazy")
    settingsCategory = category
    if not layout and category and category.GetLayout then
        layout = category:GetLayout()
    end

    if layout and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(
            "All hail the Roach King! Olympus forver!"
        ))
    end

    registerCheckbox(
        category,
        "sellJunk",
        "Auto-sell junk",
        "Sell grey items when you open a merchant."
    )
    registerCheckbox(
        category,
        "repair",
        "Auto-repair",
        "Repair all equipped gear when the merchant can repair."
    )
    registerCheckbox(
        category,
        "useGuildRepair",
        "Use guild repair",
        "Spend guild bank money first if the client allows it. Leave off on Forever unless you confirm guild repair exists."
    )
    registerCheckbox(
        category,
        "verbose",
        "Chat messages",
        "Print repair cost and junk sold in chat."
    )

    Settings.RegisterAddOnCategory(category)
end

local function openOptions()
    buildOptions()
    if settingsCategory and Settings and Settings.OpenToCategory then
        local id = settingsCategory.GetID and settingsCategory:GetID() or settingsCategory
        Settings.OpenToCategory(id)
        return
    end
    print("|cff88ccff" .. ADDON .. "|r Options UI is unavailable. Use /fl sell, repair, guild, quiet.")
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("MERCHANT_SHOW")
f:RegisterEvent("MERCHANT_CLOSED")
f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        applyDefaults()
        buildOptions()
        print("|cff88ccff" .. ADDON .. "|r loaded. /fl opens options.")
    elseif event == "MERCHANT_SHOW" then
        onMerchant()
    elseif event == "MERCHANT_CLOSED" then
        busy = false
    end
end)

SLASH_FOREVERLAZY1 = "/fl"
SLASH_FOREVERLAZY2 = "/foreverlazy"
SLASH_FOREVERLAZY3 = "/lv"
SlashCmdList.FOREVERLAZY = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" or msg == "options" or msg == "config" then
        openOptions()
        return
    end
    if msg == "sell" then
        ForeverLazyDB.sellJunk = not ForeverLazyDB.sellJunk
        say("Auto-sell junk: " .. (ForeverLazyDB.sellJunk and "on" or "off"))
    elseif msg == "repair" then
        ForeverLazyDB.repair = not ForeverLazyDB.repair
        say("Auto-repair: " .. (ForeverLazyDB.repair and "on" or "off"))
    elseif msg == "guild" then
        ForeverLazyDB.useGuildRepair = not ForeverLazyDB.useGuildRepair
        say("Guild repair: " .. (ForeverLazyDB.useGuildRepair and "on" or "off"))
    elseif msg == "quiet" then
        ForeverLazyDB.verbose = not ForeverLazyDB.verbose
        print("|cff88ccff" .. ADDON .. "|r chat: " .. (ForeverLazyDB.verbose and "on" or "off"))
    else
        print("|cff88ccff" .. ADDON .. "|r /fl opens Options. Also: sell, repair, guild, quiet")
    end
end
