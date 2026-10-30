------------------------------------------------------------
-- SPELL UNLEARN SERVICE  (Server Communication)
------------------------------------------------------------
local CS = ProjectEbonhold.CS
local SS = ProjectEbonhold.SS

local SpellUnlearnService = {}
ProjectEbonhold.SpellUnlearnService = SpellUnlearnService

function SpellUnlearnService.RequestUnlearn(spellID)
    ProjectEbonhold.sendToServer(CS.REQUEST_UNLEARN_SPELL_ECHOES, tostring(spellID))
end