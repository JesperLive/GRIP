-- GRIP luacheck configuration
-- Lua 5.1 + WoW Retail API globals

max_line_length = 120
max_code_line_length = 120
max_string_line_length = false
max_comment_line_length = false
self = false
unused_args = false
redefined = false

-- Every file uses: local ADDON_NAME, GRIP = ...
-- ADDON_NAME is intentionally unused in most files (standard WoW pattern)
ignore = {"211/ADDON_NAME"}

exclude_files = {
    "Libs/",
}

stds.wow = {
    read_globals = {
        ---------------------------------------------------------------
        -- Lua extensions (Blizzard additions to Lua 5.1)
        ---------------------------------------------------------------
        "wipe", "strsplit", "date", "time", "format",
        "hooksecurefunc", "geterrorhandler", "securecallfunction",

        ---------------------------------------------------------------
        -- Frame creation and UI fundamentals
        ---------------------------------------------------------------
        "CreateFrame", "CreateColor", "Mixin", "BackdropTemplateMixin",
        "UIParent",
        "GameTooltip", "GameFontHighlightSmall",
        "DEFAULT_CHAT_FRAME",
        "StaticPopup_Show",

        ---------------------------------------------------------------
        -- ScrollBox / DataProvider (11.0+)
        ---------------------------------------------------------------
        "ScrollUtil", "CreateScrollBoxListLinearView",
        "ScrollBoxConstants", "CreateDataProvider",

        ---------------------------------------------------------------
        -- MenuUtil / Menu (12.0+)
        ---------------------------------------------------------------
        "MenuUtil", "Menu",

        ---------------------------------------------------------------
        -- C_* namespaces
        ---------------------------------------------------------------
        "C_AddOns", "C_AddOnProfiler",
        "C_Calendar",
        "C_ChatInfo",
        "C_Club", "C_ClubFinder",
        "C_CreatureInfo",
        "C_DateAndTime",
        "C_FriendList",
        "C_GuildInfo",
        "C_Map",
        "C_Timer",

        ---------------------------------------------------------------
        -- Enums
        ---------------------------------------------------------------
        "Enum",

        ---------------------------------------------------------------
        -- Unit / character APIs
        ---------------------------------------------------------------
        "UnitName", "UnitFullName", "UnitExists",
        "UnitIsPlayer", "UnitIsUnit",
        "GetNumClasses",
        "GetRealZoneText", "GetRealmName", "GetNormalizedRealmName",
        "GetTime", "GetFramerate",
        "InCombatLockdown",
        "IsInGuild", "IsGuildLeader", "CanGuildInvite",

        ---------------------------------------------------------------
        -- Chat APIs
        ---------------------------------------------------------------
        "SendChatMessage",
        "ChatFrame_AddMessageEventFilter",
        "ChatFrame_RemoveAllMessageGroups",
        "GetChatWindowInfo", "NUM_CHAT_WINDOWS",
        "GetChannelList",
        "FCF_OpenNewWindow",

        ---------------------------------------------------------------
        -- Guild APIs
        ---------------------------------------------------------------
        "GuildInvite", "GetGuildInfo",
        "ClubFinderGetCurrentClubListingInfo", "GetClubFinderLink",

        ---------------------------------------------------------------
        -- Encounter Journal (zone exclusion)
        ---------------------------------------------------------------
        "EncounterJournal_LoadUI",
        "EJ_GetNumTiers", "EJ_SelectTier", "EJ_GetInstanceByIndex",

        ---------------------------------------------------------------
        -- Battleground APIs (zone exclusion)
        ---------------------------------------------------------------
        "GetNumBattlegroundTypes", "GetBattlegroundInfo",

        ---------------------------------------------------------------
        -- Addon management
        ---------------------------------------------------------------
        "IsAddOnLoaded", "LoadAddOn",
        "GetAddOnMemoryUsage", "UpdateAddOnMemoryUsage",

        ---------------------------------------------------------------
        -- Sound
        ---------------------------------------------------------------
        "PlaySound", "SOUNDKIT",

        ---------------------------------------------------------------
        -- Screen / cursor
        ---------------------------------------------------------------
        "GetScreenWidth", "GetScreenHeight", "GetCursorPosition",

        ---------------------------------------------------------------
        -- Class data
        ---------------------------------------------------------------
        "CLASS_ICON_TCOORDS", "RAID_CLASS_COLORS", "CUSTOM_CLASS_COLORS",
        "LOCALIZED_CLASS_NAMES_MALE", "LOCALIZED_CLASS_NAMES_FEMALE",

        ---------------------------------------------------------------
        -- UI frames and panels
        ---------------------------------------------------------------
        "FriendsFrame", "HideUIPanel", "Minimap",

        ---------------------------------------------------------------
        -- Unit popup menu (right-click hook)
        ---------------------------------------------------------------
        "UnitPopupMenus", "UnitPopup_OnClick",

        ---------------------------------------------------------------
        -- Libraries
        ---------------------------------------------------------------
        "LibStub",

        ---------------------------------------------------------------
        -- SavedVariables (read access)
        ---------------------------------------------------------------
        "GRIPDB", "GRIPDB_CHAR",

        ---------------------------------------------------------------
        -- StaticPopupDialogs (read access)
        ---------------------------------------------------------------
        "StaticPopupDialogs",
    },

    globals = {
        -- SavedVariables (written by WoW on load, mutated by addon)
        "GRIPDB", "GRIPDB_CHAR",

        -- Slash command registration
        "SLASH_GRIP1",
        "SlashCmdList",

        -- Keybind globals (Bindings.xml)
        "BINDING_HEADER_GRIP", "BINDING_HEADER_GRIP_BINDINGS",
        "BINDING_NAME_GRIP_TOGGLE",
        "BINDING_NAME_GRIP_WHO_NEXT",
        "BINDING_NAME_GRIP_INVITE_NEXT",
        "BINDING_NAME_GRIP_POST_NEXT",

        -- Keybind callback functions (must be global for Bindings.xml)
        "GRIP_ToggleUI", "GRIP_WhoNext",
        "GRIP_InviteNext", "GRIP_PostNext",

        -- Addon compartment callbacks (must be global for TOC metadata)
        "GRIP_OnCompartmentClick",
        "GRIP_OnCompartmentEnter",
        "GRIP_OnCompartmentLeave",

        -- StaticPopupDialogs (we register popup definitions)
        "StaticPopupDialogs",

        -- Unit popup menu (right-click hook mutates this)
        "UnitPopupButtons",
    },
}

std = "lua51+wow"

---------------------------------------------------------------
-- Per-file overrides
---------------------------------------------------------------

-- Locale files: AceLocale pattern L["key"] = value triggers
-- unused variable warnings (211/212) that are false positives.
-- Line length is also suppressed (long locale key strings).
files["Locale/*.lua"] = {
    max_line_length = false,
    ignore = {"211", "212"},
}
