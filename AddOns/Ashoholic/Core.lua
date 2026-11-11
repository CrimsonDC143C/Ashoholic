local addonName = ...
local addon = _G[addonName] or {}
_G[addonName] = addon

addon.name = addon.name or addonName
