-- GRIP: English (enUS) Locale — Default
-- All user-facing strings. L["key"] = true means the displayed text equals the key.

local L = LibStub("AceLocale-3.0"):NewLocale("GRIP", "enUS", true)
if not L then return end

-- =========================================================================
-- Core/Core.lua — Keybindings
-- =========================================================================

L["GRIP Recruitment"] = true
L["Toggle Window"] = true
L["Send Next /who"] = true
L["Invite Next Candidate"] = true
L["Send Next Post"] = true

-- Campaign cooldown
L["Campaign break: you've been recruiting for %d min (%d actions). Consider a short break!"] = true
L["Campaign auto-paused after %d min (%d actions). Take a %d-min break. Whisper ticker stopped."] = true
L["Campaign cooldown reset after %d min idle."] = true

-- =========================================================================
-- Core/GhostMode.lua — Ghost Mode messages
-- =========================================================================

L["Ghost session timed out after %d min (%d actions). Cooldown: %d min."] = true
L["Ghost: overlay hidden (combat). Will resume after combat."] = true
L["Ghost: overlay restored (combat ended)."] = true

-- =========================================================================
-- Core/Utils.lua — Utility messages
-- =========================================================================

L["No guild invite API available."] = true
L["(guild link unavailable)"] = true

-- =========================================================================
-- Core/Slash.lua — Static popup dialogs
-- =========================================================================

L["Copy this GRIP export string:"] = true
L["Close"] = true
L["Paste a GRIP import string:"] = true
L["Import"] = true
L["Cancel"] = true

-- Core/Slash.lua — Import popup strings
L["No import string provided."] = true
L["Import module not loaded."] = true
L["Invalid blacklist import string."] = true
L["Invalid template import string."] = true
L["Invalid import string. Must start with !GRIP:BL: or !GRIP:TPL:"] = true
L["Imported: %d new blacklist entries (%d already existed)."] = true
L["Imported %d whisper templates (%s rotation)."] = true

-- =========================================================================
-- Core/Slash.lua — Help text
-- =========================================================================

L["GRIP Commands:"] = true
L["  /grip — toggle UI"] = true
L["  /grip build — rebuild /who queue"] = true
L["  /grip scan — next /who (needs click/keybind)"] = true
L["  /grip whisper — start/stop whisper queue"] = true
L["  /grip invite — whisper+invite next (needs click/keybind)"] = true
L["  /grip post — send next post (needs click/keybind)"] = true
L["  /grip clear — clear Potential list"] = true
L["  /grip status — print counts"] = true
L["  /grip link — show guild link info"] = true
L["  /grip permbl list|add|remove|clear — manage permanent blacklist"] = true
L["  /grip ghost [start|stop|status] — Ghost Mode sessions"] = true
L["  /grip sync [on|off|now] — officer sync control"] = true
L["  /grip export bl|templates — export data to clipboard"] = true
L["  /grip import — paste an import string"] = true
L["  /grip templates list|add|remove|rotation — manage whisper templates"] = true
L["  /grip stats [7d|30d] — recruitment stats"] = true
L["  /grip stats reset — clear stats history"] = true
L["  /grip zones diag|reseed|deep|export — zone diagnostics"] = true
L["  /grip reset — reset UI position/size"] = true
L["  /grip tracegate on|off|toggle — execution gate diagnostics"] = true
L["  /grip debug on|off|dump|copy|clear|capture|status"] = true
L["  /grip set <key> <value> — change settings"] = true
L["  /grip minimap on|off|toggle"] = true
L["  /grip help — this help"] = true
L["Settings keys:"] = true
L["  whisper <msg> — set whisper template #1"] = true
L["  general <msg> — set General channel message"] = true
L["  trade <msg> — set Trade channel message"] = true
L["  blacklistdays <n> — temp blacklist duration"] = true
L["  interval <n> — post interval (minutes)"] = true
L["  zoneonly on|off — restrict /who to current zone"] = true
L["  levels <min> <max> <step> — scan range"] = true
L["  debugwindow <name> — debug output window"] = true
L["  verbosity <1|2|3> — debug verbosity"] = true
L["  hidewhispers on|off — suppress outgoing whisper echo"] = true
L["  dailycap <n> — daily whisper cap (0=unlimited)"] = true
L["  sound on|off — master sound toggle"] = true
L["  ghostmode on|off — Ghost Mode (experimental)"] = true
L["  invitefirst on|off — invite before whisper"] = true
L["  cooldown <n>|on|off — campaign break timer"] = true
L["  optout on|off — auto-blacklist opt-out replies"] = true
L["  aggressive on|off — aggressive opt-out detection"] = true
L["  riominscore <n> — M+ score filter (0=disabled)"] = true
L["  riocolumn on|off — show M+ column"] = true
L["Note: {guildlink} in whisper/post messages requires an active Guild Finder listing."] = true

-- =========================================================================
-- Core/Slash.lua — Usage strings
-- =========================================================================

L["Usage: /grip permbl list|add <name> [reason]|remove <name>|clear"] = true
L["Usage: /grip debug on|off | dump [n] | copy [n] | clear | capture on|off [max] | status"] = true

-- =========================================================================
-- Core/Slash.lua — Ghost Mode commands
-- =========================================================================

L["Command locked during Ghost session. Use /grip ghost stop first."] = true
L["Ghost Mode session started. Queue actions will execute from any input."] = true
L["Ghost Mode session stopped."] = true
L["Ghost Mode: ACTIVE (%d/%d min, %d actions, %d queued)"] = true
L["Ghost Mode: COOLDOWN (%d min remaining)"] = true
L["Ghost Mode: inactive (ready)"] = true
L["Usage: /grip ghost [start|stop|status]"] = true

-- =========================================================================
-- Core/Slash.lua — Sync commands
-- =========================================================================

L["GRIPDB not initialized."] = true
L["Officer sync: %s"] = true
L["Sync module not loaded."] = true
L["Sync: %s (libs=%s, guild=%s)"] = true
L["  Blacklist hash: %s"] = true
L["  Templates: %s (hash: %s)"] = true
L["  Last broadcast: %ds ago (cooldown: %ds)"] = true
L["  Last broadcast: never"] = true

-- =========================================================================
-- Core/Slash.lua — Export commands
-- =========================================================================

L["Export module not loaded."] = true
L["Export failed (empty blacklist or codec error)."] = true
L["Exported %d blacklist entries — copy the string from the popup."] = true
L["Export failed (no templates or codec error)."] = true
L["Exported %d whisper templates — copy the string from the popup."] = true
L["Usage: /grip export bl|templates"] = true
L["StaticPopup not available."] = true

-- =========================================================================
-- Core/Slash.lua — Permanent blacklist commands
-- =========================================================================

L["GRIPDB not initialized yet."] = true
L["Permanent blacklist: %d"] = true
L["  - %s (%s)"] = true
L["  - %s"] = true
L["  ... and %d more"] = true
L["Permanent blacklisted: %s"] = true
L["Permanent blacklist removed: %s"] = true
L["Not in permanent blacklist: %s"] = true
L["Permanent blacklist cleared: %d"] = true

-- =========================================================================
-- Core/Slash.lua — Template commands
-- =========================================================================

L["Whisper templates (%d), rotation: %s"] = true
L["  [%d] %s"] = true
L["Usage: /grip templates add <message text>"] = true
L["Max %d templates."] = true
L["Added template #%d."] = true
L["Usage: /grip templates remove <1-%d>"] = true
L["Must have at least 1 template."] = true
L["Removed template #%d. (%d remaining)"] = true
L["Whisper rotation: sequential"] = true
L["Whisper rotation: random"] = true
L["Usage: /grip templates rotation sequential|random"] = true
L["Usage: /grip templates list|add <text>|remove <n>|rotation sequential|random"] = true

-- =========================================================================
-- Core/Slash.lua — Status command
-- =========================================================================

L["Cleared Potential list."] = true
L["Potential: %d, WhoQueue: %d/%d, PostQueue: %d"] = true
L["  Blacklist: %d perm, %d temp"] = true
L["  Perm breakdown: %d opt-out, %d no-response, %d other"] = true
L["  Whispers today: %d/%d"] = true
L["  Whispers today: %d (no cap)"] = true
L["  Templates: %d (%s)"] = true
L["  Sound: %s"] = true
L["  Campaign: %d min active (%d actions), warning at %d min"] = true
L["  Campaign cooldown: enabled (%d min threshold)"] = true
L["  Campaign cooldown: disabled"] = true
L["  Ghost Mode: ACTIVE (%d min, %d actions, %d queued)"] = true
L["  Ghost Mode: enabled (no active session)"] = true
L["  Sync: %s"] = true

-- =========================================================================
-- Core/Slash.lua — Stats command
-- =========================================================================

L["Stats reset."] = true
L["Today"] = true
L["Last 7 Days"] = true
L["Last 30 Days"] = true
L["No stats data available."] = true
L["  Whispers: %d | Invites: %d | Accepted: %d | Declined: %d"] = true
L["  Opt-Outs: %d | Posts: %d | Scans: %d"] = true
L["  Accept Rate: %s"] = true

-- =========================================================================
-- Core/Slash.lua — Link diagnostics
-- =========================================================================

L["Not in a guild (or guild data not loaded yet)."] = true
L["Guild: "] = true
L["ClubId: "] = true
L["Link: "] = true
L["Link bytes: "] = true
L["Requested posting data. Try /grip link again in a few seconds."] = true
L["Open your Communities window once, then try again."] = true

-- =========================================================================
-- Core/Slash.lua — Zone commands
-- =========================================================================

L["Zones diagnostics unavailable."] = true
L["Zones export unavailable."] = true
L["Zone deep scan unavailable."] = true
L["Zones reseeded: %d (was %d)"] = true
L["Zones reseed failed (no zones)."] = true
L["Zones reseed unavailable."] = true
L["Usage: /grip zones diag|reseed|deep [maxMapID]|deep stop|export"] = true

-- =========================================================================
-- Core/Slash.lua — Debug commands
-- =========================================================================

L["Debug: "] = true
L["Debug dump unavailable (Debug module not wired yet)."] = true
L["Debug persisted log is empty (or capture is OFF)."] = true
L["Debug dump (last %d of %d):"] = true
L["Debug clear unavailable (Debug module not wired yet)."] = true
L["Debug persisted log cleared (%d lines)."] = true
L["Debug copy frame unavailable."] = true
L["Debug capture: "] = true
L["Debug capture: %s (max=%d, stored=%d, dropped=%d)"] = true
L["Gate Trace Mode: "] = true
L["Usage: /grip tracegate on|off|toggle"] = true

-- =========================================================================
-- Core/Slash.lua — Set commands
-- =========================================================================

L["Usage: /grip set <key> <value>"] = true
L["Whisper message set (template #1)."] = true
L["General message set."] = true
L["Trade message set."] = true
L["Blacklist days set to "] = true
L["Post interval set to "] = true
L[" minutes."] = true
L["Zone-only scanning: "] = true
L["Scan levels set: %d-%d step %d"] = true
L["Usage: /grip set levels <min> <max> <step>"] = true
L["Usage: /grip set debugwindow <ChatWindowName>"] = true
L["Debug window name set to: "] = true
L["Debug verbosity set to: "] = true
L["Hide outgoing whispers: "] = true
L["Usage: /grip set dailycap <number> (0 = unlimited)"] = true
L["Daily whisper cap disabled (unlimited)."] = true
L["Daily whisper cap set to %d."] = true
L["Opt-out detection: "] = true
L["Aggressive opt-out detection: "] = true
L["Sound feedback: "] = true
L["Ghost Mode: "] = true
L["Invite-first mode: "] = true
L["Usage: /grip set riominscore <number> (0 = disabled)"] = true
L["Raider.IO minimum score filter disabled."] = true
L["Raider.IO minimum M+ score set to %d."] = true
L["M+ score column: "] = true
L["Campaign cooldown disabled."] = true
L["Campaign cooldown enabled (%d min)."] = true
L["Campaign cooldown set to %d minutes."] = true
L["Usage: /grip set cooldown <%d-%d|on|off>"] = true
L["Unknown setting key: %s (use /grip help)"] = true
L["Unknown command. Use /grip help"] = true

-- Common toggle values (used across many set commands)
L["ON"] = true
L["OFF"] = true
L["ON (experimental)"] = true

-- =========================================================================
-- Recruit/Who.lua — /who scanning
-- =========================================================================

L["Building /who queue…"] = true
L["/who queue ready: %d queries."] = true
L["/who queue is empty. Run /grip build first."] = true
L["Sending /who: %s (%d/%d)"] = true
L["/who results: %d matches (total: %d)."] = true
L["Potential added: %d new. Total potential: %d."] = true
L["All candidates already seen or blacklisted."] = true
L["No results for this bracket."] = true
L["Bracket %s saturated (%d/%d) — expanding by class."] = true
L["/who complete. Scanned %d/%d brackets."] = true
L["No /who queue. Run /grip build first."] = true
L["Cannot scan during combat."] = true
L["/who queue exhausted. Rebuilding…"] = true

-- =========================================================================
-- Recruit/Whisper.lua — Whisper queue
-- =========================================================================

L["Whisper queue started."] = true
L["Whisper queue stopped."] = true
L["Whisper queue paused (combat)."] = true
L["Whisper queue resumed (combat ended)."] = true
L["Whisper queue complete. %d sent, %d failed."] = true
L["Whispered %s (template #%d)."] = true
L["Daily whisper cap reached (%d/%d). Queue stopped."] = true
L["Approaching daily cap: %d/%d whispers sent."] = true
L["No candidates to whisper."] = true
L["Whispers disabled in config."] = true
L["Opt-out detected from %s: \"%s\""] = true

-- =========================================================================
-- Recruit/Invite.lua — Invite pipeline
-- =========================================================================

L["Invited %s to guild."] = true
L["Invite skipped (blacklisted): %s"] = true
L["Invite failed (no API): %s"] = true
L["Invite failed: %s"] = true
L["Cannot invite during combat."] = true
L["No candidates to invite."] = true
L["Invites disabled in config."] = true
L["%s accepted guild invite!"] = true
L["%s declined guild invite."] = true
L["%s already in a guild."] = true
L["%s: no response (%d/%d). Temp blacklisted %dd."] = true
L["%s: no response (%d/%d). Permanent blacklisted."] = true

-- =========================================================================
-- Recruit/Post.lua — Post scheduler
-- =========================================================================

L["Post queued: %s to %s"] = true
L["Post sent: %s"] = true
L["Post failed: %s"] = true
L["No post channel found for: %s"] = true
L["Post queue is empty."] = true
L["Post queue full (%d/%d)."] = true
L["Post scheduler started (%d min interval)."] = true
L["Post scheduler stopped."] = true
L["Posts disabled in config."] = true
L["Cannot post during combat."] = true
L["Post cooldown: %d sec remaining."] = true
L["Channel %s not joined."] = true

-- =========================================================================
-- Sync/ImportExport.lua
-- =========================================================================

L["Unsupported import version: "] = true

-- =========================================================================
-- UI/UI.lua — Main frame
-- =========================================================================

L["GRIP"] = true
L["Home"] = true
L["Settings"] = true
L["Ads"] = true
L["Stats"] = true
L["Press Ctrl+C to copy:"] = true
L["Discord Support"] = true

-- =========================================================================
-- UI/UI_Home.lua — Home page
-- =========================================================================

-- Column headers
L["Name"] = true
L["Lvl"] = true
L["Class"] = true
L["Race"] = true
L["Zone"] = true
L["M+"] = true
L["W"] = true
L["I"] = true

-- Column tooltip titles
L["Whisper Status"] = true
L["Invite Status"] = true

-- Column tooltip bodies
L["W = Whisper status for this candidate."] = true
L["I = Invite status for this candidate."] = true

-- Row tooltip status words
L["Sent"] = true
L["Failed"] = true
L["Pending"] = true
L["Accepted"] = true
L["Declined"] = true
L["Unknown"] = true

-- Row tooltip lines
L["Whisper: %s"] = true
L["Invite: %s"] = true
L["Zone: %s"] = true
L["M+ Score: %s"] = true
L["Raider.IO M+: %d"] = true

-- Empty state
L["No potential candidates yet. Click Scan to begin."] = true
L["Initializing… (database not ready yet)"] = true

-- Buttons
L["Scan"] = true
L["Whisper+Invite Next"] = true
L["Post Next"] = true
L["Clear"] = true

-- Button tooltips
L["Scan (Send Next /who)"] = true
L["Send the next /who query from the scan queue.\nRequires a click or keybind (hardware event)."] = true
L["Whisper + Invite Next"] = true
L["Whisper the next candidate, then send a guild invite.\nRequires a click or keybind (hardware event)."] = true
-- "Send Next Post" already defined in keybindings section
L["Send the next queued Trade/General post.\nRequires a click or keybind (hardware event)."] = true
L["Clear Potential List"] = true
L["Remove all candidates from the Potential list.\nDoes NOT affect blacklists or whisper history."] = true

L["Home unavailable yet (DB not initialized)."] = true

-- Ghost strip
L["Ghost: Active"] = true
L["Ghost: Cooldown"] = true
L["Ghost: Ready"] = true
L["Stop"] = true
L["Start"] = true
L["|cff00ff00Ghost: Active|r  %s / %s  |  Queue: %d  |  Actions: %d"] = true
L["|cffff8800Ghost: Cooldown|r  %s remaining"] = true
L["|cff888888Ghost: Ready|r"] = true

-- Hint bar
L["Tip: /grip help  \194\183  None selected in filters = allow all"] = true

-- Row tooltip
L["Level %d"] = true
L["Right-click for options"] = true

-- Button tooltip dynamic bodies
L["Send next /who query.\nRequires keybind or button click.\nQueue: %d/%d remaining"] = true
L["Whisper the next candidate, then queue\na guild invite.\nRequires keybind or button click.\nWhisper queue: %d  |  Pending invites: %d"] = true
L["Send next Trade/General channel post.\nRequires keybind or button click.\nQueue: %d posts remaining"] = true

-- Dynamic hints
L["Click Scan or press your Scan keybind to find unguilded players"] = true
L["Whisper queue has %d candidates \xe2\x80\x94 click Whisper+Invite to start"] = true
L["%d temp-blacklisted players will expire in ~%d days"] = true
L["Tip: /grip help  \xC2\xB7  Right-click rows for options"] = true

-- Panel title with counts
L["Blacklist (perm %d; temp %d)"] = true

-- Scan cooldown
L["Scan (%.0fs)"] = true

-- Init state
L["Initializing\xe2\x80\xa6"] = true
L["Initializing\xe2\x80\xa6 (database not ready yet)"] = true

-- Status bar
L[" (waiting\xe2\x80\xa6)"] = true
L["Potential: |cffffffff%d|r   |   BL: |cff888888perm %d|r  %stemp %d|r\nWho: %d/%d%s   |   Whisper: %d (%s)   |   Post: %d%s"] = true

-- Onboarding
L["Welcome to GRIP!"] = true
L["Quick Setup:"] = true
L["1. Settings tab: set your level range and zone/race/class filters."] = true
L["2. Settings tab: edit your whisper template. Use {player} and {guildlink}."] = true
L["3. Ads tab: write your Trade/General recruitment messages."] = true
L["4. Click Scan to start finding unguilded players!"] = true
L["Tip: Hover any button for details. See /grip help for all commands."] = true
L["Tip: Right-click a candidate row for quick blacklist/invite actions."] = true
L["Got it!"] = true

-- =========================================================================
-- UI/UI_Settings.lua — Settings page
-- =========================================================================

-- Level controls
L["Scan Levels (min / max / step)"] = true
L["Min"] = true
L["Max"] = true
L["Step"] = true
L["Apply + Rebuild"] = true
L["Levels must be numbers."] = true
L["Settings unavailable yet (DB not initialized)."] = true

-- Zone-only
L["Include current zone in /who query"] = true

-- Apply + Rebuild tooltip
L["Apply Level Range"] = true
L["Save the min/max/step values and rebuild the /who queue."] = true

-- Zone Only tooltip
L["Zone Only"] = true
L["When enabled, appends your current zone name to /who queries.\nNarrows results to players near you."] = true

-- Filter info
L["Filters are allowlists. If nothing is checked in a category, that category allows ALL."] = true

-- Checklist section titles
L["Zones"] = true
L["Races"] = true
L["Classes"] = true

-- Filter buttons
L["All"] = true
L["None"] = true
L["Current"] = true
L["Clear Selections"] = true

-- Filter button tooltips
L["Select All Zones"] = true
L["Enable all zones in the filter list."] = true
L["Deselect All Zones"] = true
L["Disable all zones — an empty zone list allows ALL zones."] = true
L["Current Zone"] = true
L["Enable only your current zone in the filter."] = true
L["Could not determine current zone."] = true
L["Zone \"%s\" not found in zone lists."] = true
L["Select All Races"] = true
L["Enable all races in the filter."] = true
L["Deselect All Races"] = true
L["Disable all races — an empty race list allows ALL races."] = true
L["Select All Classes"] = true
L["Enable all classes in the filter."] = true
L["Deselect All Classes"] = true
L["Disable all classes — an empty class list allows ALL classes."] = true
L["Clear Filter Selections"] = true
L["Clear all zone, race, and class filter selections.\nEmpty filters = allow all."] = true
L["Cleared filter selections."] = true

-- Whisper template section
L["Whisper Templates (supports {player} {guild} {guildlink})"] = true
L["Prev"] = true
L["Next"] = true
L["+ Add"] = true
L["- Remove"] = true
L["Message %d/%d"] = true

-- Template nav tooltips
L["Previous Template"] = true
L["Show the previous whisper template."] = true
L["Next Template"] = true
L["Show the next whisper template."] = true
L["Add Template"] = true
L["Add a new blank whisper template (max 10)."] = true
L["Remove Template"] = true
L["Remove the currently displayed template."] = true

-- Token insert buttons
L["Insert {guildlink}"] = true
L["Insert {guild}"] = true
L["Insert {player}"] = true
L["Insert a clickable Guild Finder link token.\nRequires an active listing in the Guild Finder."] = true
L["Insert the guild name token."] = true
L["Insert the target player's name token."] = true
L["No room to insert {guildlink} (max 255 after expansion)."] = true
L["No room to insert {guild} (max 255 after expansion)."] = true
L["No room to insert {player} (max 255 after expansion)."] = true

-- Save/Preview
L["Save All"] = true
L["Save all whisper templates."] = true
L["Save All Templates"] = true
L["Save all whisper templates to SavedVariables.\nTemplates are also auto-saved when switching tabs."] = true
L["Saved %d whisper template(s)."] = true
L["Template %d is too long after token expansion (max 255)."] = true
L["Preview"] = true
L["Preview the current template with tokens expanded.\nShows what the whisper will look like in-game."] = true
L["Preview Template"] = true
L["Template is too long after token expansion (max 255)."] = true
L["Preview: "] = true

-- Rotation
L["Rotation:"] = true
L["Sequential"] = true
L["Random"] = true
L["Send templates in order (1, 2, 3, …, repeat)."] = true
L["Pick a random template for each whisper."] = true

-- Checkboxes
L["Hide outgoing whisper echoes"] = true
L["Suppress Whisper Echo"] = true
L["Hide your own outgoing whisper text from the chat window.\nThe whisper is still sent — only the echo is hidden."] = true

L["Invite first (safer)"] = true
L["Invite First"] = true
L["Send the guild invite BEFORE the whisper.\nSafer: the player sees the invite popup even if they ignore whispers."] = true

-- Sound section
L["Sound Feedback"] = true
L["Enable sound feedback"] = true
L["Master Sound Toggle"] = true
L["Enable or disable all GRIP sound notifications."] = true
L["Whisper queue complete"] = true
L["Play a sound when the whisper queue finishes."] = true
L["Invite accepted"] = true
L["Play a sound when a player accepts your guild invite."] = true
L["Scan results found"] = true
L["Play a sound when a /who scan finds new candidates."] = true
L["Daily cap warning"] = true
L["Play a sound when approaching the daily whisper cap."] = true

-- Opt-out section
L["Opt-Out Detection Languages"] = true
L["English"] = true
L["English (Required)"] = true
L["English opt-out detection is always active and cannot be disabled."] = true
L["English is always enabled for opt-out detection."] = true

L["Français (French)"] = true
L["French Opt-Out Phrases"] = true
L["Enable detection of French opt-out phrases (e.g., \"non merci\", \"pas intéressé\")."] = true

L["Deutsch (German)"] = true
L["German Opt-Out Phrases"] = true
L["Enable detection of German opt-out phrases (e.g., \"nein danke\", \"kein Interesse\")."] = true

L["Español (Spanish)"] = true
L["Spanish Opt-Out Phrases"] = true
L["Enable detection of Spanish opt-out phrases (e.g., \"no gracias\", \"no me interesa\")."] = true

L["Aggressive language detection"] = true
L["Aggressive Language Detection"] = true
L["Detect aggressive opt-out phrases (profanity, hostile responses).\nBlacklists the player immediately when detected."] = true

-- Raider.IO section
L["Raider.IO Integration"] = true
L["Requires the Raider.IO addon to be installed."] = true
L["Minimum M+ Score (0 = disabled):"] = true
L["Show M+ column in Potential list"] = true
L["M+ Column"] = true
L["Show each candidate's Mythic+ score in the Potential list.\nRequires the Raider.IO addon."] = true

-- Officer Sync section
L["Officer Sync"] = true
L["Enable officer sync"] = true
L["Share permanent blacklist entries with other officers running GRIP.\nUses guild addon channel — no external services."] = true
L["Sync whisper templates"] = true
L["Template Sync"] = true
L["Sync whisper templates with other officers.\nUses last-write-wins: the most recently edited set is shared."] = true
L["Last sync: never"] = true

-- Ghost Mode section
L["Ghost Mode (Experimental)"] = true
L["Enable Ghost Mode"] = true
L["Queue hardware-gated actions (invites, posts, /who) into a\nsingle overlay. Any keypress or click drains the queue one action at a time."] = true
L["Ghost Session Max (minutes)"] = true
L["Ghost Cooldown (minutes)"] = true

-- =========================================================================
-- UI/UI_Ads.lua — Ads page
-- =========================================================================

L["Advertisement Config"] = true
L["Enable scheduled posting"] = true
L["Scheduled Posting"] = true
L["When enabled, GRIP will automatically queue Trade/General posts at the configured interval."] = true
L["Post Interval (minutes):"] = true
L["General Channel Message:"] = true
L["Trade Channel Message:"] = true
L["Save Messages"] = true
L["Save Ad Messages"] = true
L["Save the General and Trade channel message templates."] = true
L["Messages saved."] = true

-- Token buttons (shared with Settings)
-- (Already defined above: "Insert {guildlink}", "Insert {guild}", "Insert {player}")

-- Scheduler status
L["Scheduler: active (%d min interval)"] = true
L["Scheduler: paused"] = true
L["Post queue: %d"] = true
L["Next post in: %d sec"] = true

-- =========================================================================
-- UI/UI_Stats.lua — Stats page
-- =========================================================================

L["Recruitment Statistics"] = true
-- "Today", "Last 7 Days", "Last 30 Days" already defined above

-- Stat labels
L["Whispers"] = true
L["Invites"] = true
-- "Accepted", "Declined" already defined above
L["Opt-Outs"] = true
L["Posts"] = true
L["Scans"] = true

L["Accept Rate"] = true
L["Peak Hour"] = true
L["N/A"] = true
L["%s (%d actions)"] = true

-- =========================================================================
-- UI/UI_Home_Popups.lua — Popup dialogs
-- =========================================================================

L["Remove %s from permanent blacklist?"] = true
L["Remove"] = true
L["Removed %s from permanent blacklist."] = true
L["Add %s to permanent blacklist?\n(Optional reason)"] = true
L["Blacklist"] = true
L["Blacklisted %s: %s"] = true
L["Blacklisted %s."] = true
L["Clear all %s candidates from the Potential list?"] = true

-- =========================================================================
-- UI/UI_Home_Blacklist.lua — Blacklist panel
-- =========================================================================

-- Panel title: "Blacklist" already defined above
L["Export"] = true
L["Export permanent blacklist"] = true
L["Copies a shareable string to a popup for Ctrl+C."] = true
L["Exported %d blacklist entries."] = true

-- Import
-- "Import" already defined above
L["Import blacklist or templates"] = true
L["Paste a GRIP export string to import data."] = true

-- Column headers: "Name", "Reason" already defined above
L["Reason"] = true

-- Empty state
L["Permanent blacklist is empty.\nTip: right-click a Potential entry to add it."] = true
L["No permanent blacklist entries.\nTemp blacklist active: %d.\nTip: right-click a Potential entry to add a permanent entry."] = true

-- Row tooltip
L["Reason: "] = true
L["Added: "] = true
L["Click to remove from blacklist"] = true
L["Click to remove"] = true

-- =========================================================================
-- UI/UI_Home_Menu.lua — Right-click context menu
-- =========================================================================

L["Blacklist…"] = true
L["Blacklist… (already blacklisted)"] = true
L["Invite to Guild"] = true
L["Invite to Guild (disabled in combat)"] = true
L["Cannot invite in combat."] = true
L["Invite blocked (%s): %s"] = true

-- =========================================================================
-- UI/UI_Widgets.lua — Reusable widgets
-- =========================================================================

-- " min" suffix is in slider display, not typically localized
-- "All"/"None" already defined above

-- =========================================================================
-- UI/Minimap.lua — Minimap button + compartment
-- =========================================================================

-- Minimap tooltip
-- "GRIP" already defined above
L["Left-click: Toggle window (Home)"] = true
L["Middle-click: Settings"] = true
L["Right-click: Ads"] = true
L["Drag: Move button"] = true
L["/grip minimap off  (hide)"] = true
L["Cannot open GRIP window in combat."] = true
L["Minimap button: "] = true

-- Compartment menu
L["GRIP v%s"] = true
L["Toggle UI"] = true
L["Status"] = true
L["Build Scan Queue"] = true
L["Locked during Ghost session."] = true
L["Who queue rebuilt."] = true
L["Stop Ghost Session"] = true
L["Start Ghost Session"] = true
L["Stop Whispers"] = true
L["Start Whispers"] = true

-- Compartment tooltip
L["Left-click: Toggle window"] = true
L["Right-click: Quick actions"] = true

-- =========================================================================
-- Core/Events.lua — Event messages
-- =========================================================================

L["Loaded: %s (v%s)"] = true
L["Type /grip help for commands."] = true

-- =========================================================================
-- @localization(locale="enUS", format="lua_additive_table", same-key-is-true=true, namespace="")@
-- =========================================================================
