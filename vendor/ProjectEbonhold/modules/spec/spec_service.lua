local addonName, addon = ...






local function RequestCurrentSpec()
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_CURRENT_SPEC, "")
end


local function ApplySpec(specIndex)
    if not specIndex then
        return
    end
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_APPLY_SPECS, tostring(specIndex))
end


local function ResetTalents(specIndex)
    if not specIndex then
        return
    end
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_RESET_TALENT_TREE, tostring(specIndex))
end


local function OnSpecDataReceived(body)
    
    local specIndex = tonumber(body)

    if specIndex and specIndex >= 1 and specIndex <= 5 then
        
        if ProjectEbonhold and ProjectEbonhold.Spec and ProjectEbonhold.Spec.UpdateSelectedSpec then
            ProjectEbonhold.Spec.UpdateSelectedSpec(specIndex)
        end
    end
end


ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_PLAYER_SPEC_INDEX, function(body)
    OnSpecDataReceived(body)
end)


local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        RequestCurrentSpec()
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end)


ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.SpecService = ProjectEbonhold.SpecService or {}
ProjectEbonhold.SpecService.ApplySpec = ApplySpec
ProjectEbonhold.SpecService.ResetTalents = ResetTalents
ProjectEbonhold.SpecService.RequestCurrentSpec = RequestCurrentSpec
