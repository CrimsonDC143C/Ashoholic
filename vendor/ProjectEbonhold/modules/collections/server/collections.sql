-- Source query for modules/collections/Data/appearances_data.lua.
--
-- Every item the wardrobe can browse: armor and weapons that carry a display,
-- in the inventory types the server's Transmogrification::CannotTransmogrify
-- accepts. Rings, necks, trinkets, relics, bags and ammo have no visual, so
-- they are left out; heirlooms (quality 7) are excluded because their entries
-- duplicate looks that already exist on normal items.
--
-- No entry-range cap: custom items (prestige weapons, shop cosmetics, forged
-- gear) live above the Blizzard range and must be browsable too.
--
-- The ORDER BY is what gives each category its display order in the wardrobe,
-- so keep it stable: the fold in Data/appearances.lua groups on
-- (class, subclass, invType) and preserves this order inside each group.
SELECT entry, displayid, Quality, class, subclass, InventoryType
FROM item_template
WHERE class IN (2, 4)          -- ITEM_CLASS_WEAPON, ITEM_CLASS_ARMOR
  AND displayid > 0
  AND Quality <= 6             -- 0 poor .. 6 artifact; 7 = heirloom, skipped
  AND InventoryType IN (1, 3, 4, 5, 6, 7, 8, 9, 10, 13, 14, 15, 16, 17, 19, 20, 21, 22, 23, 25, 26)
ORDER BY class, subclass, InventoryType, displayid, entry;
