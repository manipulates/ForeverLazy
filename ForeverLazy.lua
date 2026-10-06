local ADDON = "ForeverLazy"

ForeverLazyDB = ForeverLazyDB or {}

local defaults = {
    sellJunk = true,
    repair = true,
    useGuildRepair = false,
    verbose = true,
    repairBelow = 100,
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
        return nil
    end
    if not GetContainerItemInfo then
        return nil
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

local function lowestDurability()
    local lowest
    for slot = 1, 19 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            local pct = cur / max * 100
            if not lowest or pct < lowest then
                lowest = pct
            end
        end
    end
    return lowest
end

local function doRepair()
    if not db().repair then
        return false, 0, false
    end
    local lowest = lowestDurability()
    if not lowest or lowest > (tonumber(db().repairBelow) or 100) then
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

local REPO_URL = "github.com/manipulates/ForeverLazy"

local function addonVersion()
    local fn = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return fn and fn(ADDON, "Version") or ""
end

local PANEL_WIDTH = 540
local GREY = { 0.62, 0.62, 0.62 }

local function makeText(parent, template, text, color)
    local fs = parent:CreateFontString(nil, "ARTWORK", template)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetText(text)
    if color then
        fs:SetTextColor(color[1], color[2], color[3])
    end
    return fs
end

local function makeSection(parent, title, y)
    local header = makeText(parent, "GameFontNormal", title)
    header:SetPoint("TOPLEFT", 16, y)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.12)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    line:SetWidth(PANEL_WIDTH)
    return header
end

local function makeCheckbox(parent, key, title, hint, x, y)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", x, y)

    local label = makeText(parent, "GameFontHighlight", title)
    label:SetPoint("LEFT", cb, "RIGHT", 4, 1)

    if hint then
        local note = makeText(parent, "GameFontHighlightSmall", hint, GREY)
        note:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
        note:SetWidth(PANEL_WIDTH - x - 40)
    end

    cb:SetScript("OnClick", function(self)
        db()[key] = self:GetChecked() and true or false
    end)
    cb.refresh = function()
        cb:SetChecked(db()[key] and true or false)
    end
    return cb
end

local function makeSlider(parent, key, x, y)
    local name = ADDON .. "RepairSlider"
    local label = makeText(parent, "GameFontHighlight", "Repair threshold")
    label:SetPoint("TOPLEFT", x, y)

    local value = makeText(parent, "GameFontNormal", "")
    value:SetPoint("LEFT", label, "RIGHT", 10, 0)

    local note = makeText(parent, "GameFontHighlightSmall",
        "Only repair once your most damaged item is at or below this.", GREY)
    note:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)

    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -16)
    slider:SetWidth(280)
    slider:SetMinMaxValues(10, 100)
    slider:SetValueStep(5)
    if slider.SetObeyStepOnDrag then
        slider:SetObeyStepOnDrag(true)
    end

    local text = _G[name .. "Text"] or slider.Text
    local low = _G[name .. "Low"] or slider.Low
    local high = _G[name .. "High"] or slider.High
    if text then text:SetText("") end
    if low then low:SetText("10%") low:SetTextColor(GREY[1], GREY[2], GREY[3]) end
    if high then high:SetText("100%") high:SetTextColor(GREY[1], GREY[2], GREY[3]) end

    local function show(v)
        value:SetText(v >= 100 and "any damage" or (v .. "%"))
    end

    slider:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / 5 + 0.5) * 5
        db()[key] = v
        show(v)
    end)
    slider.refresh = function()
        local v = tonumber(db()[key]) or 100
        slider:SetValue(v)
        show(v)
    end
    return slider
end

local function buildPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Forever Lazy"

    local title = makeText(panel, "GameFontNormalHuge", "Forever Lazy")
    title:SetPoint("TOPLEFT", 16, -16)

    local version = makeText(panel, "GameFontHighlightSmall", "v" .. addonVersion(), GREY)
    version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 3)

    local tagline = makeText(panel, "GameFontHighlight", "Sells your junk and repairs your gear when you open a vendor.")
    tagline:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)

    local boxes = {}

    makeSection(panel, "Vendor", -76)
    boxes[#boxes + 1] = makeCheckbox(panel, "sellJunk", "Auto-sell junk", "Sells grey items when a merchant opens.", 16, -108)
    boxes[#boxes + 1] = makeCheckbox(panel, "repair", "Auto-repair", "Repairs all equipped gear when the merchant can repair.", 16, -158)
    boxes[#boxes + 1] = makeCheckbox(panel, "useGuildRepair", "Use guild repair", "Spends guild bank money first. Leave off on Forever unless guild repair works for you.", 44, -208)
    boxes[#boxes + 1] = makeSlider(panel, "repairBelow", 20, -268)

    makeSection(panel, "Chat", -372)
    boxes[#boxes + 1] = makeCheckbox(panel, "verbose", "Chat messages", "Prints repair cost and junk sold.", 16, -404)

    local aboutHeader = makeSection(panel, "About", -464)
    local about = makeText(panel, "GameFontHighlight",
        "Retail spoiled us. Classic never caught up, and I kept forgetting to repair my armor and clear the grey junk out of my bags. "
        .. "So I wrote this to do it for me. Nothing fancy, but it gets the job done.")
    about:SetPoint("TOPLEFT", aboutHeader, "BOTTOMLEFT", 0, -16)
    about:SetWidth(PANEL_WIDTH)

    local credit = makeText(panel, "GameFontNormal", "A Chrome Jesus piece. 2026.")
    credit:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 0, -12)

    local link = CreateFrame("EditBox", nil, panel)
    link:SetFontObject("GameFontHighlightSmall")
    link:SetTextColor(GREY[1], GREY[2], GREY[3])
    link:SetAutoFocus(false)
    link:SetSize(300, 16)
    link:SetPoint("TOPLEFT", credit, "BOTTOMLEFT", 0, -6)
    link:SetText(REPO_URL)
    link:SetScript("OnEditFocusLost", function(self) self:SetText(REPO_URL) end)
    link:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local commands = makeText(panel, "GameFontHighlightSmall", "Chat commands: /fl   /fl sell   /fl repair   /fl guild   /fl quiet", GREY)
    commands:SetPoint("TOPLEFT", link, "BOTTOMLEFT", 0, -14)

    panel:SetScript("OnShow", function()
        for _, cb in ipairs(boxes) do
            cb.refresh()
        end
    end)
    return panel
end

local legacyPanel

local function buildOptions()
    if settingsCategory or legacyPanel then
        return
    end

    applyDefaults()

    local ok, err = pcall(function()
        local panel = buildPanel()
        if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
            local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
            Settings.RegisterAddOnCategory(category)
            settingsCategory = category
        elseif InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(panel)
            legacyPanel = panel
        end
    end)
    if not ok then
        print("|cff88ccff" .. ADDON .. "|r options failed to build: " .. tostring(err))
    end
end

local function openOptions()
    buildOptions()
    if settingsCategory and Settings and Settings.OpenToCategory then
        local id = settingsCategory.GetID and settingsCategory:GetID() or settingsCategory
        if not pcall(Settings.OpenToCategory, id) then
            pcall(Settings.OpenToCategory, settingsCategory)
        end
        return
    end
    if legacyPanel and InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(legacyPanel)
        InterfaceOptionsFrame_OpenToCategory(legacyPanel)
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
