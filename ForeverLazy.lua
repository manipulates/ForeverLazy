local ADDON = "ForeverLazy"

ForeverVendorDB = ForeverVendorDB or {}

local defaults = {
    sellJunk = true,
    repair = true,
    useGuildRepair = false,
    verbose = true,
}

local function applyDefaults()
    for k, v in pairs(defaults) do
        if ForeverVendorDB[k] == nil then
            ForeverVendorDB[k] = v
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
    if ForeverVendorDB.verbose then
        print("|cff88ccff" .. ADDON .. "|r " .. msg)
    end
end

local function bagMax()
    return NUM_BAG_SLOTS or 4
end

local function sellJunk()
    if not ForeverVendorDB.sellJunk then
        return 0, 0
    end
    if not MerchantFrame or not MerchantFrame:IsShown() then
        return 0, 0
    end

    local sold, copper = 0, 0
    for bag = 0, bagMax() do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.quality == 0 and info.hyperlink then
                local unit = select(11, C_Item.GetItemInfo(info.hyperlink)) or 0
                C_Container.UseContainerItem(bag, slot)
                sold = sold + (info.stackCount or 1)
                copper = copper + unit * (info.stackCount or 1)
            end
        end
    end
    return sold, copper
end

local function doRepair()
    if not ForeverVendorDB.repair then
        return false, 0, false
    end
    if not CanMerchantRepair or not CanMerchantRepair() then
        return false, 0, false
    end

    local cost = GetRepairAllCost() or 0
    if cost <= 0 then
        return false, 0, false
    end

    local guild = false
    if ForeverVendorDB.useGuildRepair and CanGuildBankRepair and CanGuildBankRepair() then
        RepairAllItems(true)
        guild = true
    else
        if GetMoney() < cost then
            say("Need " .. money(cost) .. " to repair. Skipping.")
            return false, cost, false
        end
        RepairAllItems(false)
    end
    return true, cost, guild
end

local busy = false

local function onMerchant()
    if busy then
        return
    end
    busy = true

    C_Timer.After(0.15, function()
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
        C_Timer.After(0.35, function()
            pass()
            if totalSold > 0 then
                say("Sold " .. totalSold .. " junk for " .. money(totalCopper) .. ".")
            end
            busy = false
        end)
    end)
end

local settingsCategory

local function registerCheckbox(category, key, title, tooltip)
    local variable = ADDON .. "_" .. key
    local setting = Settings.RegisterAddOnSetting(
        category,
        variable,
        key,
        ForeverVendorDB,
        Settings.VarType.Boolean,
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

    applyDefaults()

    local category, layout = Settings.RegisterVerticalLayoutCategory("Forever Vendor")
    settingsCategory = category
    
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(
        "All hail the Roach King! Olympus forver!"
    ))
    
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
    if settingsCategory then
        Settings.OpenToCategory(settingsCategory:GetID())
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("MERCHANT_SHOW")
f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        applyDefaults()
        buildOptions()
        print("|cff88ccff" .. ADDON .. "|r loaded. /fv opens options.")
    elseif event == "MERCHANT_SHOW" then
        onMerchant()
    end
end)

SLASH_FOREVERVENDOR1 = "/fv"
SLASH_FOREVERVENDOR2 = "/forevervendor"
SlashCmdList.FOREVERVENDOR = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" or msg == "options" or msg == "config" then
        openOptions()
        return
    end
    if msg == "sell" then
        ForeverVendorDB.sellJunk = not ForeverVendorDB.sellJunk
        say("Auto-sell junk: " .. (ForeverVendorDB.sellJunk and "on" or "off"))
    elseif msg == "repair" then
        ForeverVendorDB.repair = not ForeverVendorDB.repair
        say("Auto-repair: " .. (ForeverVendorDB.repair and "on" or "off"))
    elseif msg == "guild" then
        ForeverVendorDB.useGuildRepair = not ForeverVendorDB.useGuildRepair
        say("Guild repair: " .. (ForeverVendorDB.useGuildRepair and "on" or "off"))
    elseif msg == "quiet" then
        ForeverVendorDB.verbose = not ForeverVendorDB.verbose
        print("|cff88ccff" .. ADDON .. "|r chat: " .. (ForeverVendorDB.verbose and "on" or "off"))
    else
        print("|cff88ccff" .. ADDON .. "|r /fv opens Options. Also: sell, repair, guild, quiet")
    end
end