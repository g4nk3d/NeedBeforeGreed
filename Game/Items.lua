--[[ Need Before Greed - Game/Items.lua
	The classes, what each class can use, the five dungeons and their loot. Pure data and a few lookups;
	no game API (the balance tools run this file too).

	Usability follows Classic proficiencies at level 60: armour (cloth, leather, mail, plate), shields,
	and weapon skills. Rings, necklaces, trinkets and cloaks are for everyone. Item icons are file names
	from the game's own icon library (checked when the game starts; a missing one shows the question mark).

	  I.CLASSES, I.CLASS_NAME[c]      the nine classes, in card order
	  I.TYPES[t]                      { name, badge, use = { class = true } }
	  I:CanUse(class, item)           true when that class can equip the item
	  I.DUNGEONS / I:Dungeon(id)      { id, name, boss, about, tier, calls, items = {...} }
	  I.QUALITY[q]                    { name, color, lo, hi } (gold value range, hidden during a run) ]]

local _, ns = ...
local I = {}
ns.Items = I

I.CLASSES = { "warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid" }
I.CLASS_NAME = { warrior = "Warrior", paladin = "Paladin", hunter = "Hunter", rogue = "Rogue", priest = "Priest",
	shaman = "Shaman", mage = "Mage", warlock = "Warlock", druid = "Druid" }

local function set(...)
	local t = {}
	for i = 1, select("#", ...) do t[select(i, ...)] = true end
	return t
end
local ALL = set("warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid")

-- badge: the item-type badge sprite (item_type_<badge>)
I.TYPES = {
	cloth   = { name = "Cloth",            badge = "cloth",          use = ALL },
	leather = { name = "Leather",          badge = "leather",        use = set("warrior", "paladin", "hunter", "rogue", "shaman", "druid") },
	mail    = { name = "Mail",             badge = "mail",           use = set("warrior", "paladin", "hunter", "shaman") },
	plate   = { name = "Plate",            badge = "plate",          use = set("warrior", "paladin") },
	shield  = { name = "Shield",           badge = "shield",         use = set("warrior", "paladin", "shaman") },
	sword1  = { name = "One-hand sword",   badge = "one_hand_sword", use = set("warrior", "paladin", "hunter", "rogue", "mage", "warlock") },
	sword2  = { name = "Two-hand sword",   badge = "two_hand_sword", use = set("warrior", "paladin", "hunter") },
	axe1    = { name = "One-hand axe",     badge = "axe",            use = set("warrior", "paladin", "hunter", "shaman") },
	axe2    = { name = "Two-hand axe",     badge = "axe",            use = set("warrior", "paladin", "hunter", "shaman") },
	mace1   = { name = "One-hand mace",    badge = "mace",           use = set("warrior", "paladin", "rogue", "priest", "shaman", "druid") },
	mace2   = { name = "Two-hand mace",    badge = "mace",           use = set("warrior", "paladin", "shaman", "druid") },
	dagger  = { name = "Dagger",           badge = "dagger",         use = set("warrior", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid") },
	staff   = { name = "Staff",            badge = "staff",          use = set("warrior", "hunter", "priest", "shaman", "mage", "warlock", "druid") },
	bow     = { name = "Bow or gun",       badge = "bow_gun",        use = set("warrior", "hunter", "rogue") },
	wand    = { name = "Wand",             badge = "wand",           use = set("priest", "mage", "warlock") },
	trinket = { name = "Ring or trinket",  badge = "trinket_ring",   use = ALL },
}
-- the order of the reference card's columns
I.TYPE_ORDER = { "cloth", "leather", "mail", "plate", "shield", "sword1", "sword2", "axe1", "mace1", "mace2",
	"dagger", "staff", "bow", "wand", "trinket" }

function I:CanUse(class, item)
	local t = self.TYPES[item.t]
	return t ~= nil and t.use[class] == true
end

-- "Warrior, Paladin, ..." for an item's type (made once per type)
local usableBy = {}
function I:UsableBy(item)
	local s = usableBy[item.t]
	if not s then
		local who = {}
		for _, c in ipairs(self.CLASSES) do if self:CanUse(c, item) then who[#who + 1] = self.CLASS_NAME[c] end end
		s = #who == #self.CLASSES and "every class" or table.concat(who, ", ")
		usableBy[item.t] = s
	end
	return s
end

-- 1 poor .. 5 epic. Values are gold; the exact value of each drop is hidden until the end of the run.
I.QUALITY = {
	{ name = "Poor",     color = { 0.62, 0.62, 0.62 }, lo = 1,   hi = 6,   card = "poor" },
	{ name = "Common",   color = { 1, 1, 1 },          lo = 4,   hi = 15,  card = "common" },
	{ name = "Uncommon", color = { 0.12, 1, 0 },       lo = 12,  hi = 45,  card = "uncommon" },
	{ name = "Rare",     color = { 0, 0.44, 0.87 },    lo = 40,  hi = 120, card = "rare" },
	{ name = "Epic",     color = { 0.64, 0.21, 0.93 }, lo = 110, hi = 300, card = "epic" },
}

local IC = "Interface\\Icons\\"
-- name, quality, type, slot, icon
local function L(list)
	local out = {}
	for i, e in ipairs(list) do
		out[i] = { name = e[1], q = e[2], t = e[3], slot = e[4], icon = IC .. e[5], index = i }
	end
	return out
end

I.DUNGEONS = {
	{ id = "mossgate", name = "Mossgate Barrow", boss = "the Barrow King", tier = 1, calls = 2,
		about = "An overgrown burial mound lit by green candles. Old bronze, worn leather and grave rings.",
		items = L({
			{ "Grave-Moss Sandals", 1, "cloth", "Feet", "INV_Boots_Cloth_03" },
			{ "Cracked Barrow Ring", 1, "trinket", "Finger", "INV_Jewelry_Ring_02" },
			{ "Rootbound Jerkin", 2, "leather", "Chest", "INV_Chest_Leather_03" },
			{ "Tarnished Bronze Shortsword", 2, "sword1", "One-hand", "INV_Sword_04" },
			{ "Mourner's Cowl", 2, "cloth", "Head", "INV_Helmet_29" },
			{ "Bronze-Banded Buckler", 3, "shield", "Off hand", "INV_Shield_05" },
			{ "Barrowguard Leggings", 3, "leather", "Legs", "INV_Pants_06" },
			{ "Candlewax Wand", 3, "wand", "Ranged", "INV_Wand_02" },
			{ "Burial Knife", 3, "dagger", "One-hand", "INV_Weapon_ShortBlade_05" },
			{ "Moss-Root Staff", 3, "staff", "Two-hand", "INV_Staff_08" },
			{ "Kingsbarrow Ringmail", 4, "mail", "Chest", "INV_Chest_Chain_05" },
			{ "Thornwoven Gloves", 4, "leather", "Hands", "INV_Gauntlets_05" },
			{ "Old Bronze War Axe", 4, "axe2", "Two-hand", "INV_Axe_09" },
			{ "Signet of the Barrow King", 4, "trinket", "Finger", "INV_Jewelry_Ring_15" },
			{ "Throne-Bone Cleaver", 5, "axe1", "One-hand", "INV_Axe_05" },
			{ "Crown of Green Flame", 5, "cloth", "Head", "INV_Helmet_24" },
		}) },
	{ id = "saltspire", name = "Saltspire Keep", boss = "Morwenna the Sea Witch", tier = 2, calls = 2,
		about = "A storm-lashed sea fort. Salt-crusted mail, sailor's cloaks and pearls from the deep.",
		items = L({
			{ "Salt-Stained Wraps", 1, "cloth", "Wrist", "INV_Bracer_07" },
			{ "Barnacled Belt", 1, "leather", "Waist", "INV_Belt_03" },
			{ "Deckhand's Cutlass", 2, "sword1", "One-hand", "INV_Sword_05" },
			{ "Stormwatch Cloak", 2, "cloth", "Back", "INV_Misc_Cape_08" },
			{ "Tidecaller Gloves", 3, "mail", "Hands", "INV_Gauntlets_10" },
			{ "Harbourmaster's Spyglass", 3, "trinket", "Trinket", "INV_Misc_Spyglass_02" },
			{ "Kelpwoven Robe", 3, "cloth", "Chest", "INV_Chest_Cloth_17" },
			{ "Brine Hook", 3, "dagger", "One-hand", "INV_Weapon_ShortBlade_10" },
			{ "Seawall Greaves", 3, "plate", "Legs", "INV_Pants_04" },
			{ "Pearl of the Drowned", 4, "trinket", "Trinket", "INV_Misc_Gem_Pearl_04" },
			{ "Wavebreaker Hauberk", 4, "mail", "Chest", "INV_Chest_Chain_07" },
			{ "Coral-Crusted Mace", 4, "mace1", "One-hand", "INV_Mace_05" },
			{ "Salt-Eaten Longrifle", 4, "bow", "Ranged", "INV_Weapon_Rifle_04" },
			{ "Captain's Tower Shield", 4, "shield", "Off hand", "INV_Shield_10" },
			{ "Morwenna's Tidal Mantle", 5, "mail", "Shoulder", "INV_Shoulder_14" },
			{ "Choker of the Deep Choir", 5, "trinket", "Neck", "INV_Jewelry_Necklace_09" },
		}) },
	{ id = "gloomroot", name = "Gloomroot Warren", boss = "the Broodmother", tier = 3, calls = 2,
		about = "A rotten forest den under purple fungus. Fangs, bows and gear grown more than made.",
		items = L({
			{ "Sporestained Pants", 1, "cloth", "Legs", "INV_Pants_Cloth_04" },
			{ "Chewed Leather Boots", 1, "leather", "Feet", "INV_Boots_05" },
			{ "Webspinner Wristguards", 2, "leather", "Wrist", "INV_Bracer_02" },
			{ "Fungal Cap", 2, "cloth", "Head", "INV_Helmet_31" },
			{ "Silkthread Shortbow", 3, "bow", "Ranged", "INV_Weapon_Bow_04" },
			{ "Fang of the Warren", 3, "dagger", "One-hand", "INV_Weapon_ShortBlade_11" },
			{ "Mossback Vest", 3, "leather", "Chest", "INV_Chest_Leather_07" },
			{ "Gloomcap Wand", 3, "wand", "Ranged", "INV_Wand_07" },
			{ "Rootwarden Mail", 3, "mail", "Legs", "INV_Pants_03" },
			{ "Broodsilk Robe", 4, "cloth", "Chest", "INV_Chest_Cloth_21" },
			{ "Venomdrip Stiletto", 4, "dagger", "One-hand", "INV_Weapon_ShortBlade_14" },
			{ "Thornbark Greatstaff", 4, "staff", "Two-hand", "INV_Staff_11" },
			{ "Sporecloud Talisman", 4, "trinket", "Trinket", "INV_Jewelry_Talisman_05" },
			{ "Weaver's Spined Gauntlets", 4, "plate", "Hands", "INV_Gauntlets_14" },
			{ "Broodmother's Hunting Bow", 5, "bow", "Ranged", "INV_Weapon_Bow_08" },
			{ "Heart of the Gloom", 5, "trinket", "Trinket", "INV_Misc_Orb_03" },
		}) },
	{ id = "cinderhold", name = "Cinderhold", boss = "the fire giant Brannox", tier = 4, calls = 1,
		about = "A volcanic forge hall of glowing cracks. Heavy plate, molten maces and fire-proof cloaks.",
		items = L({
			{ "Scorched Work Gloves", 1, "leather", "Hands", "INV_Gauntlets_04" },
			{ "Ashen Bracers", 2, "cloth", "Wrist", "INV_Bracer_09" },
			{ "Slagforged Hammer", 2, "mace1", "One-hand", "INV_Hammer_05" },
			{ "Emberproof Cloak", 3, "cloth", "Back", "INV_Misc_Cape_06" },
			{ "Furnace Plate Boots", 3, "plate", "Feet", "INV_Boots_Plate_03" },
			{ "Cinder-Scale Leggings", 3, "mail", "Legs", "INV_Pants_Mail_10" },
			{ "Bellows Sash", 3, "cloth", "Waist", "INV_Belt_10" },
			{ "Magma-Quenched Blade", 4, "sword1", "One-hand", "INV_Sword_10" },
			{ "Forgeheart Breastplate", 4, "plate", "Chest", "INV_Chest_Plate06" },
			{ "Obsidian Bulwark", 4, "shield", "Off hand", "INV_Shield_09" },
			{ "Smoldering Maul", 4, "mace2", "Two-hand", "INV_Hammer_13" },
			{ "Ring of Banked Coals", 4, "trinket", "Finger", "INV_Jewelry_Ring_14" },
			{ "Giantsfall Greatsword", 5, "sword2", "Two-hand", "INV_Sword_39" },
			{ "Helm of the Smoke-King", 5, "plate", "Head", "INV_Helmet_10" },
			{ "Brannox's Fallen Hammer", 5, "mace2", "Two-hand", "INV_Hammer_09" },
			{ "Lavaforged Pauldrons", 5, "plate", "Shoulder", "INV_Shoulder_10" },
		}) },
	{ id = "sunken_observatory", name = "The Sunken Observatory", boss = "the broken Orrery Warden", tier = 5, calls = 1,
		about = "A drowned arcane tower of star charts and lenses. Robes, wands, staves and strange trinkets.",
		items = L({
			{ "Soggy Star Chart", 1, "trinket", "Trinket", "INV_Misc_Map_01" },
			{ "Waterlogged Slippers", 1, "cloth", "Feet", "INV_Boots_Cloth_05" },
			{ "Lensgrinder's Gloves", 2, "leather", "Hands", "INV_Gauntlets_03" },
			{ "Brass Astrolabe Mace", 3, "mace1", "One-hand", "INV_Mace_08" },
			{ "Tidal Lens Wand", 3, "wand", "Ranged", "INV_Wand_04" },
			{ "Stargazer's Vestments", 3, "cloth", "Chest", "INV_Chest_Cloth_25" },
			{ "Orrery Chain Leggings", 3, "mail", "Legs", "INV_Pants_Mail_03" },
			{ "Drowned Scholar's Dirk", 3, "dagger", "One-hand", "INV_Weapon_ShortBlade_06" },
			{ "Robe of Fallen Constellations", 4, "cloth", "Chest", "INV_Chest_Cloth_32" },
			{ "Starsplinter Staff", 4, "staff", "Two-hand", "INV_Staff_13" },
			{ "Ring of the Seventh Lens", 4, "trinket", "Finger", "INV_Jewelry_Ring_29" },
			{ "Warden's Gearplate Helm", 4, "plate", "Head", "INV_Helmet_08" },
			{ "Moonwake Spellblade", 4, "sword1", "One-hand", "INV_Sword_23" },
			{ "Wand of the Last Eclipse", 5, "wand", "Ranged", "INV_Wand_11" },
			{ "Orrery Heartstone", 5, "trinket", "Trinket", "INV_Misc_Orb_02" },
			{ "Staff of the Drowned Sky", 5, "staff", "Two-hand", "INV_Staff_14" },
		}) },
}
local byId = {}
for i, d in ipairs(I.DUNGEONS) do d.index = i byId[d.id] = d end
function I:Dungeon(id) return byId[id] end

-- how likely each quality is in a dungeon's ordinary drops (poor .. epic); the last drop is the boss's
I.QUALITY_WEIGHTS = {
	{ 20, 34, 30, 14, 2 },
	{ 12, 30, 34, 20, 4 },
	{ 8, 24, 36, 25, 7 },
	{ 5, 18, 35, 32, 10 },
	{ 3, 12, 33, 37, 15 },
}
I.BOSS_EPIC = { 25, 32, 40, 48, 56 }   -- percent: the boss drop is epic, otherwise rare

return I
