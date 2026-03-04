-- GRIP: Zone Data
-- Static shipped zone list (grouped by expansion) + exclude patterns.

local ADDON_NAME, GRIP = ...

GRIP.ZONES_BY_EXPANSION = {
  { name = "Midnight", zones = {
    "Harandar",
  }},
  { name = "The War Within", zones = {
    "Azj-Kahet",
    "Azj-Kahet - Lower",
    "Hallowfall",
    "Isle of Dorn",
    "The Ringing Deeps",
  }},
  { name = "Dragonflight", zones = {
    "Emerald Dream",
    "Forbidden Reach",
    "Ohn'ahran Plains",
    "Thaldraszus",
    "The Azure Span",
    "The Waking Shores",
    "Zaralek Cavern",
  }},
  { name = "Shadowlands", zones = {
    "Ardenweald",
    "Bastion",
    "Maldraxxus",
    "Maw",
    "Revendreth",
    "Zereth Mortis",
  }},
  { name = "Battle for Azeroth", zones = {
    "Drustvar",
    "Mechagon Island",
    "Nazjatar",
    "Nazmir",
    "Stormsong Valley",
    "Tiragarde Sound",
    "Vol'dun",
    "Zuldazar",
  }},
  { name = "Legion", zones = {
    "Azsuna",
    "Broken Shore",
    "Dalaran (Broken Isles)",
    "Highmountain",
    "Krokuun",
    "Mac'Aree",
    "Stormheim",
    "Suramar",
    "Val'sharah",
  }},
  { name = "Warlords of Draenor", zones = {
    "Frostfire Ridge",
    "Gorgrond",
    "Nagrand (Draenor)",
    "Shadowmoon Valley (Draenor)",
    "Spires of Arak",
    "Talador",
    "Tanaan Jungle",
  }},
  { name = "Mists of Pandaria", zones = {
    "Dread Wastes",
    "Isle of Thunder",
    "Jade Forest",
    "Krasarang Wilds",
    "Kun-Lai Summit",
    "Timeless Isle",
    "Townlong Steppes",
    "Vale of Eternal Blossoms",
    "Valley of the Four Winds",
  }},
  { name = "Cataclysm", zones = {
    "Deepholm",
    "Gilneas",
    "Kezan",
    "Molten Front",
    "Mount Hyjal",
    "The Lost Isles",
    "Twilight Highlands",
    "Uldum",
    "Vashj'ir",
  }},
  { name = "Wrath of the Lich King", zones = {
    "Borean Tundra",
    "Crystalsong Forest",
    "Dalaran",
    "Dragonblight",
    "Grizzly Hills",
    "Howling Fjord",
    "Icecrown",
    "Sholazar Basin",
    "The Storm Peaks",
    "Zul'Drak",
  }},
  { name = "The Burning Crusade", zones = {
    "Blade's Edge Mountains",
    "Hellfire Peninsula",
    "Isle of Quel'Danas",
    "Nagrand",
    "Netherstorm",
    "Shadowmoon Valley",
    "Shattrath City",
    "Terokkar Forest",
    "Zangarmarsh",
  }},
  { name = "Classic", zones = {
    "Arathi Highlands",
    "Ashenvale",
    "Azshara",
    "Azuremyst Isle",
    "Badlands",
    "Blasted Lands",
    "Bloodmyst Isle",
    "Burning Steppes",
    "Darkshore",
    "Darnassus",
    "Deadwind Pass",
    "Desolace",
    "Dun Morogh",
    "Durotar",
    "Duskwood",
    "Dustwallow Marsh",
    "Eastern Plaguelands",
    "Elwynn Forest",
    "Eversong Woods",
    "Felwood",
    "Feralas",
    "Ghostlands",
    "Hillsbrad Foothills",
    "Ironforge",
    "Loch Modan",
    "Moonglade",
    "Mulgore",
    "Northern Barrens",
    "Northern Stranglethorn",
    "Orgrimmar",
    "Redridge Mountains",
    "Searing Gorge",
    "Silithus",
    "Silvermoon City",
    "Silverpine Forest",
    "Southern Barrens",
    "Stonetalon Mountains",
    "Stormwind City",
    "Stranglethorn Vale",
    "Swamp of Sorrows",
    "Tanaris",
    "Teldrassil",
    "The Cape of Stranglethorn",
    "The Exodar",
    "The Hinterlands",
    "Thousand Needles",
    "Tirisfal Glades",
    "Un'Goro Crater",
    "Undercity",
    "Western Plaguelands",
    "Westfall",
    "Wetlands",
  }},
  { name = "Starting Zones", zones = {
    "Ammen Vale",
    "Camp Narache",
    "Coldridge Valley",
    "Deathknell",
    "Echo Isles",
    "Exile's Reach",
    "New Tinkertown",
    "Northshire",
    "Plaguelands: The Scarlet Enclave",
    "Ruins of Gilneas",
    "Sunstrider Isle",
    "Valley of Trials",
  }},
}

-- Build flattened STATIC_ZONES (used as fallback by GetZonesGroupedForUI).
GRIP.STATIC_ZONES = {}
for _, group in ipairs(GRIP.ZONES_BY_EXPANSION) do
  for _, z in ipairs(group.zones) do
    GRIP.STATIC_ZONES[#GRIP.STATIC_ZONES + 1] = z
  end
end

-- Continent → expansion display name mapping for dynamic zone grouping.
-- Lower order = appears first (newest expansion first).
-- Continents not in this table get their raw C_Map name and order 0 (top).
GRIP.CONTINENT_DISPLAY_NAMES = {
  ["Khaz Algar"]        = { display = "The War Within",         order = 1 },
  ["Dragon Isles"]      = { display = "Dragonflight",           order = 2 },
  ["Shadowlands"]       = { display = "Shadowlands",            order = 3 },
  ["Zandalar"]          = { display = "Battle for Azeroth",     order = 4 },
  ["Kul Tiras"]         = { display = "Battle for Azeroth",     order = 4 },
  ["Broken Isles"]      = { display = "Legion",                 order = 5 },
  ["Argus"]             = { display = "Legion",                 order = 5 },
  ["Draenor"]           = { display = "Warlords of Draenor",    order = 6 },
  ["Pandaria"]          = { display = "Mists of Pandaria",      order = 7 },
  ["Northrend"]         = { display = "Wrath of the Lich King", order = 8 },
  ["Outland"]           = { display = "The Burning Crusade",    order = 9 },
  ["Eastern Kingdoms"]  = { display = "Eastern Kingdoms",       order = 10 },
  ["Kalimdor"]          = { display = "Kalimdor",               order = 11 },
}

-- Seasonal zones: only shown when the associated holiday is active.
GRIP.SEASONAL_ZONES = {
  ["Darkmoon Island"] = { holiday = "Darkmoon Faire", fallback = "darkmoon" },
}

-- Pattern excludes: any zone name containing these substrings is filtered out.
GRIP.STATIC_ZONE_EXCLUDE_PATTERNS = {
  "Scenario",
  "Prototype",
  "Disabled",
  "Arena",
  "BfA -",
  "Cataclysm -",
  "N'zoth Assault",
}

-- Exact-name excludes: zones that should never appear in any list.
GRIP.STATIC_ZONE_EXCLUDE_EXACT = {
  -- Continents / world-level
  "Cosmic", "Kalimdor", "Northrend", "Outland", "Pandaria", "Shadowlands",
  "Dragon Isles", "The Great Sea", "The Maelstrom", "Kul Tiras", "Zandalar",
  "Eastern Kingdoms", "Broken Isles", "Argus",

  -- PvP / world PvP
  "Ashran", "Tol Barad", "Tol Barad Peninsula", "Wintergrasp",

  -- Scenarios
  "Dagger in the Dark", "Secrets of Ragefire", "Cooking: Impossible",
  "Inconspicuous Crate", "Sir Thomas", "Town Hall",

  -- Arenas
  "Dalaran Sewers", "Ruins of Lordaeron", "Blade's Edge Arena", "Nagrand Arena",
  "Tiger's Peak", "Tol'viron Arena", "Ashamane's Fall", "Black Rook Hold Arena",
  "Empyrean Domain", "Enigma Crucible", "Hookpoint", "Maldraxxus Coliseum",
  "Mugambala", "Nokhudon Proving Grounds", "The Robodrome",

  -- Seasonal (handled separately via SEASONAL_ZONES)
  "Brewfest", "Darkmoon Island",

  -- Removed/unavailable zones
  "Havenswood", "Strand of the Ancients", "Alliance Housing District",

  -- Sub-zones / micro-zones
  "Elder Rise", "Nifflevar", "Prowler's Hill", "Queldanil Lodge", "Terror Run",
  "The Bone Wastes", "The Underbelly", "Trueshot Lodge", "Witch Hill",
  "Wyrmrest Temple", "Spine of the Destroyer", "Mimiron's Workshop",
  "Cenarius' Dream", "Coldheart Interstitia",
}
