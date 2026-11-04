local addonName = ...
local addon = _G[addonName]

local function OpacitySlider()
    local slider = _G.ColorPickerFrameOpacitySlider
    if slider and slider.GetValue then return slider end
    local function Find(parent, depth)
        if not parent or not parent.GetNumChildren or depth > 5 then return nil end
        for i = 1, parent:GetNumChildren() do
            local child = select(i, parent:GetChildren())
            if child:GetObjectType() == "Slider" then return child end
            local found = Find(child, depth + 1)
            if found then return found end
        end
    end
    return Find(ColorPickerFrame, 0)
end

local function SliderRange(slider)
    local minimum, maximum = slider:GetMinMaxValues()
    minimum = minimum or 0
    if not maximum or maximum <= minimum then maximum = minimum + 1 end
    return minimum, maximum - minimum
end

function addon:CloseColorPicker(owner)
    if ColorPickerFrame._ashOwner == owner then ColorPickerFrame:Hide() end
end

function addon:OpenColorPicker(color, onChange, onCancel, owner, defaultColor, onDefault)
    local picker = ColorPickerFrame
    picker:Hide()
    local alpha = math.max(0, math.min(1, color[4] or 1))
    local function Apply()
        if picker._ashApply ~= Apply then return end
        local r, g, b = picker:GetColorRGB()
        local a = alpha
        local slider = picker._ashOpSlider
        if slider and (picker._ashForceFrames or 0) == 0 then
            local minimum, range = SliderRange(slider)
            a = math.max(0, math.min(1, (slider:GetValue() - minimum) / range))
        end
        onChange(r, g, b, a)
    end
    picker._ashOwner = owner
    picker._ashApply = Apply
    picker._ashInitial = alpha
    picker.func, picker.opacityFunc, picker.swatchFunc = Apply, Apply, Apply
    picker.cancelFunc = function()
        picker._ashApply = nil
        onCancel()
    end
    picker.hasOpacity, picker.opacity = true, alpha
    picker.hasDefault = nil
    picker.defaultColor = defaultColor
    picker.defaultFunc = onDefault
    picker._ashOpSlider = OpacitySlider()
    picker._ashForceFrames = 8
    picker._ashLastSliderValue, picker._ashLastApplyTime = nil, 0
    if not picker._ashMonitorInstalled then
        picker._ashMonitorInstalled = true
        picker:HookScript("OnShow", function(self)
            self._ashForceFrames, self._ashLastSliderValue = 8, nil
        end)
        picker:HookScript("OnHide", function(self)
            -- Some 3.3.5 forks reset opacity before hiding; never apply on hide.
            self._ashForceFrames, self._ashLastSliderValue, self._ashLastApplyTime = 0, nil, nil
            self._ashApply, self._ashOwner = nil, nil
        end)
        picker:HookScript("OnUpdate", function(self)
            if not self._ashApply then return end
            local slider = self._ashOpSlider or OpacitySlider()
            self._ashOpSlider = slider
            if not slider then return end
            if not slider._ashMouseUpHooked then
                slider._ashMouseUpHooked = true
                slider:HookScript("OnMouseUp", function()
                    if picker._ashApply then picker._ashApply() end
                end)
            end
            local minimum, range = SliderRange(slider)
            -- Forks can reset opacity a few frames after Show or SetColorRGB.
            if self._ashForceFrames > 0 then
                self._ashForceFrames = self._ashForceFrames - 1
                slider:SetValue(minimum + self._ashInitial * range)
                self.opacity = self._ashInitial
                self._ashLastSliderValue = slider:GetValue()
                return
            end
            local value = slider:GetValue()
            if self._ashLastSliderValue == nil then self._ashLastSliderValue = value end
            if value ~= self._ashLastSliderValue then
                self._ashLastSliderValue = value
                self.opacity = math.max(0, math.min(1, (value - minimum) / range))
                local now = GetTime()
                if now - (self._ashLastApplyTime or 0) >= 0.08 then
                    self._ashLastApplyTime = now
                    self._ashApply()
                end
            end
        end)
    end
    picker:SetColorRGB(color[1], color[2], color[3])
    picker:SetFrameStrata("FULLSCREEN_DIALOG")
    picker:SetFrameLevel(200)
    picker:Show()
    local defaultButton = _G.ColorPickerFrameDefaultButton
    if defaultButton then defaultButton:Hide() end
end
