local hooked = false;

local skinned = false;
local function ElvUIHook()
    if not hooked or not ElvUI or skinned then return; end
    local E = unpack(ElvUI);
    local S = E:GetModule("Skins");
    if not E.private.skins.blizzard.enable or not E.private.skins.blizzard.pvp then return end
    ArenaFrameTab1:SetPoint("BOTTOMLEFT", 11, 46);
    S:HandleTab(ArenaFrameTab1);
    S:HandleTab(ArenaFrameTab2);
    S:HandleTab(ArenaFrameTab3);
    S:HandleTab(PVPParentFrameTab3);
    skinned = true;
    ElvUIHook = function() end
    return true;
end
ezCollections:MergeHook("ezCollectionsElvUIHook", function()
    local E = unpack(ElvUI);
    local S = E:GetModule("Skins");
    S:AddCallback("Skin_PvP_ezCollectionsArena", ElvUIHook);
end);

function ezCollections:SetEmbedArenaFrame(enabled)
    if not self.Features.EmbedArenaFrame then return; end
    if enabled then
        if not hooked then
            hooked = true;
            local lastFrameWasArena = false;
            ArenaFrame:HookScript("OnShow", function(self)
                if not ezCollections.Config.Misc.EmbedArenaFrame then return; end
                PVPMicroButton_SetPushed();
                UpdateMicroButtons();
                if not IsBattlefieldArena() and ezCollections.ArenaFrameCommand then
                    ezCollections:SendAddonCommand(ezCollections.ArenaFrameCommand);
                end
                lastFrameWasArena = true;
            end);
            ArenaFrame:HookScript("OnHide", function(self)
                if not ezCollections.Config.Misc.EmbedArenaFrame then return; end
                PVPMicroButton_SetNormal();
                UpdateMicroButtons();
            end);
            PVPParentFrame:HookScript("OnShow", function(self)
                lastFrameWasArena = false;
            end);
            hooksecurefunc("UpdateMicroButtons", function()
                if not ezCollections.Config.Misc.EmbedArenaFrame then return; end
                if ArenaFrame:IsShown() then
                    PVPMicroButton:SetButtonState("PUSHED", 1);
                    PVPMicroButton_SetPushed();
                end
            end);
            local oldTogglePVPFrame = TogglePVPFrame;
            function TogglePVPFrame()
                if not ezCollections.Config.Misc.EmbedArenaFrame then return oldTogglePVPFrame(); end
                if ( PVPFrame_IsJustBG() ) then
                    PVPFrame_SetJustBG(false);
                else
                    if ( UnitLevel("player") >= SHOW_PVP_LEVEL ) then
                        ToggleFrame(lastFrameWasArena and ArenaFrame or PVPParentFrame);
                    end
                end
            end
            local function CreateTab(parent, id, text, tooltip, x, y)
                local tab = CreateFrame("Button", "$parentTab"..id, parent, "CharacterFrameTabButtonTemplate");
                tab:SetID(id);
                tab:SetText(text);
                if id == 1 then
                    tab:SetPoint("BOTTOMLEFT", x, y);
                else
                    tab:SetPoint("LEFT", "$parentTab"..(id - 1), "RIGHT", -15, 0);
                end
                tab:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
                    GameTooltip:SetText(tooltip, 1.0, 1.0, 1.0);
                end);
                tab:SetScript("OnLeave", GameTooltip_Hide);
                return tab;
            end
            CreateTab(ArenaFrame, 1, PVP, PLAYER_V_PLAYER, 11-2, 46-2):SetScript("OnClick", function(self)
                HideUIPanel(ArenaFrame);
                ShowUIPanel(PVPParentFrame);
                PVPParentFrameTab1:Click();
            end);
            CreateTab(ArenaFrame, 2, BATTLEGROUNDS, BATTLEFIELDS):SetScript("OnClick", function(self)
                HideUIPanel(ArenaFrame);
                ShowUIPanel(PVPParentFrame);
                PVPParentFrameTab2:Click();
            end);
            CreateTab(ArenaFrame, 3, ARENA, ARENA);
            PanelTemplates_SetNumTabs(ArenaFrame, 3);
            PanelTemplates_Tab_OnClick(ArenaFrameTab3, ArenaFrame);
            ArenaFrameGroupJoinButton:SetFrameLevel(ArenaFrameTab3:GetFrameLevel() + 1);
            ArenaFrameJoinButton:SetFrameLevel(ArenaFrameTab3:GetFrameLevel() + 1);
            ArenaFrameCancelButton:SetFrameLevel(ArenaFrameTab3:GetFrameLevel() + 1);
            CreateTab(PVPParentFrame, 3, ARENA, ARENA):SetScript("OnClick", function(self)
                HideUIPanel(PVPParentFrame);
                ShowUIPanel(ArenaFrame);
                PlaySound("igCharacterInfoTab");
            end);
            ElvUIHook();
        end
        ArenaFrameTab1:Show();
        ArenaFrameTab2:Show();
        ArenaFrameTab3:Show();
        PVPParentFrameTab3:Show();
        PanelTemplates_SetNumTabs(PVPParentFrame, 3);
        PanelTemplates_UpdateTabs(PVPParentFrame);
        UpdateMicroButtons();
    elseif hooked then
        ArenaFrameTab1:Hide();
        ArenaFrameTab2:Hide();
        ArenaFrameTab3:Hide();
        PVPParentFrameTab3:Hide();
        PanelTemplates_SetNumTabs(PVPParentFrame, 2);
        PanelTemplates_UpdateTabs(PVPParentFrame);
        UpdateMicroButtons();
    end
end