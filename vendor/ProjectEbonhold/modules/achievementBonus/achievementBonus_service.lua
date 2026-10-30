


local addonName, addon = ...

AchievementBonusService = {}
AchievementBonusService.data = {}

function AchievementBonusService:Initialize()
    
    self.data = {
        [13] = 1.05,      
        [31] = 1.05,      
        [941] = 1.05,     
        [1576] = 1.05,    
        [1182] = 1.05,    
        [1681] = 1.15,    
        [46] = 1.10,      
        [1283] = 1.05,    
        [1285] = 1.05,    
        [1284] = 1.05,    
        [1286] = 1.05,    
        [1287] = 1.05,    
        [1288] = 1.07,    
        [1289] = 1.10,    
        [2136] = 1.12,    
        [2137] = 1.15,    
        [2138] = 1.25,    
        [735] = 1.05,     
        [730] = 1.05,     
        [522] = 1.01,     
        [762] = 1.05,     
        [948] = 1.05,     
        [556] = 1.05,     
        [557] = 1.02,     
        [503] = 1.05,     
        [504] = 1.05,     
        [505] = 1.05,     
        [506] = 1.05,     
        [507] = 1.05,     
        [508] = 1.05,     
        [32] = 1.05,      
        [978] = 1.05,     
        [732] = 1.05,     
        [731] = 1.05,     
        [116] = 1.05,     
        [733] = 1.05,     
        [6] = 1.02,       
        [7] = 1.03,       
        [8] = 1.05,       
        [9] = 1.05,       
        [10] = 1.05,      
        [11] = 1.05,      
        [12] = 1.05,      
        [973] = 1.02,     
        [974] = 1.03,     
        [975] = 1.05,     
        [976] = 1.10,     
        [977] = 1.20,     
    }
end

function AchievementBonusService:GetBonus(achievementId)
    return self.data[achievementId]
end

function AchievementBonusService:HasBonus(achievementId)
    return self.data[achievementId] ~= nil
end

function AchievementBonusService:SetBonus(achievementId, bonus)
    self.data[achievementId] = bonus
end

function AchievementBonusService:RemoveBonus(achievementId)
    self.data[achievementId] = nil
end

function AchievementBonusService:GetAllBonuses()
    return self.data
end


AchievementBonusService:Initialize()
