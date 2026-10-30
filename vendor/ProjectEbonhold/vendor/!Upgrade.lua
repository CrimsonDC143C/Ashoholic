local hooked = false;

local uncollected = nil;
local check;

local function Reset()
    check:SetChecked(0);
    _G[check:GetName().."Text"]:SetText(ezCollections.L["Auction.Uncollected"]);
    uncollected = nil;
end

local function Hook()
    if hooked or not ezCollections.Features.AuctionSearchUncollected or not ezCollections.Config.Misc.AuctionSearchUncollected or not IsAddOnLoaded("Blizzard_AuctionUI") or not AuctionFrameBrowse then return; end

    hooked = true;
    check = CreateFrame("CheckButton", "ezCollectionsAuctionIsUncollectedCheckButton", AuctionFrameBrowse, "UICheckButtonTemplate");
    check:ClearAllPoints();
    check:SetPoint("LEFT", IsUsableCheckButtonText, "RIGHT", 10, 0);
    check:SetSize(24, 24);
    check:HookScript("OnClick", function(self)
        PlaySound("igMainMenuOptionCheckBoxOn");
        uncollected = self:GetChecked() and (IsShiftKeyDown() and 2 or 1) or nil;
        if uncollected == 2 then
            _G[check:GetName().."Text"]:SetText(ezCollections.L["Auction.Uncollected.Unowned"]);
        else
            _G[check:GetName().."Text"]:SetText(ezCollections.L["Auction.Uncollected"]);
        end
    end);
    check:HookScript("OnHide", Reset); -- To reduce the chance of addons sending an uncollected query without the user's knowledge
    check:HookScript("OnEnter", function(self)
        if ezCollections.AuctionSearchUncollectedTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT");
            GameTooltip:SetText(ezCollections.AuctionSearchUncollectedTooltip, nil, nil, nil, nil, 1);
        end
    end);
    check:HookScript("OnLeave", GameTooltip_Hide);
    _G[check:GetName().."Text"]:SetFontObject(GameFontHighlightSmall);
    _G[check:GetName().."Text"]:SetText(ezCollections.L["Auction.Uncollected"]);

    local oldOnUpdate = BrowseResetButton:GetScript("OnUpdate");
    BrowseResetButton:SetScript("OnUpdate", function(self, ...)
        if check:GetChecked() then
            self:Enable();
        else
            oldOnUpdate(self, ...);
        end
    end);
    BrowseResetButton:HookScript("OnClick", Reset);
    hooksecurefunc("AuctionFrameBrowse_Reset", Reset);

    local oldQueryAuctionItems = QueryAuctionItems;
    function QueryAuctionItems(text, minLevel, maxLevel, invType, class, subclass, page, usable, rarity, getAll, ...)
        if uncollected and not getAll and ezCollections.Features.AuctionSearchUncollected and ezCollections.Config.Misc.AuctionSearchUncollected then
            ezCollections:SendAddonMessage("AUCTION:NEXTSEARCHUNCOLLECTED:" .. uncollected);
        end
        return oldQueryAuctionItems(text, minLevel, maxLevel, invType, class, subclass, page, usable, rarity, getAll, ...);
    end
end


hooksecurefunc(ezCollections.AceAddon, "ADDON_LOADED", function(self, event, addon)
    if addon == "Blizzard_AuctionUI" then
        Hook();
    end
end);

function ezCollections:SetAuctionSearchUncollected(enabled)
    if not self.Features.AuctionSearchUncollected then return; end
    if enabled then
        Hook();
        if check then
            check:Show();
        end
    elseif hooked and check then
        check:SetChecked(0);
        _G[check:GetName().."Text"]:SetText(ezCollections.L["Auction.Uncollected"]);
        check:Hide();
        uncollected = nil;
    end
end
