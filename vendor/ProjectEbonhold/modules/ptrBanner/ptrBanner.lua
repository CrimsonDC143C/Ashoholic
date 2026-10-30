local addonName, addon = ...

-- Top-centered banner that reminds the player they are on the PTR (test) realm
-- and shows the current addon version. Only created/shown on a dev realm, as
-- reported by utils.IsDevRealm() (realm name contains "(PTR)").

local function CreateBanner()
    local banner = CreateFrame("Frame", "ProjectEbonholdPTRBanner", UIParent)
    banner:SetFrameStrata("HIGH")
    banner:SetPoint("TOP", UIParent, "TOP", 0, -8)

    local text = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("CENTER")
    text:SetWidth(700)
    text:SetJustifyH("CENTER")
    text:SetText(string.format(
        "|cffff5555[PTR TEST REALM] You are connected to the Public Test Realm \226\128\148 Addon Version %s|r",
        tostring(addon.version)))
    banner.text = text

    -- Size the frame to its (possibly wrapped) text so a background, if added
    -- later, fits.
    banner:SetWidth(text:GetWidth() + 20)
    banner:SetHeight(text:GetHeight() + 8)

    return banner
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function()
    if not utils or not utils.IsDevRealm() then
        return
    end
    if not ProjectEbonholdPTRBanner then
        CreateBanner()
    end
    ProjectEbonholdPTRBanner:Show()
end)
