-- The claude-html helper: deletes, opens, resumes and updates from the index.
--
-- A page opened from disk is not allowed to delete files, so the bin on the
-- index is a claude-html://delete/<session id> link, which macOS hands to this
-- app. It shows exactly what would go, and does nothing until you confirm in a
-- dialog of its own: any website can ask it to open, but only your click here
-- can make it act. Files go to the Trash, where Put Back restores them.

on run
	activate
	display dialog "This helper deletes a conversation when you click its bin on the claude-html index, and asks you first, every time." & return & return & "It does nothing on its own." buttons {"OK"} default button 1 with title "claude-html"
end run

on open location theURL
	-- Updating: the link names nothing, so it must be exactly this, in this
	-- case. It opens Terminal on this clone's own claude-html --update; the
	-- update itself says what it would do and refuses what it should.
	considering case
		set isUpdate to (theURL is "claude-html://update")
	end considering
	if isUpdate then
		set here to do shell script "dirname " & quoted form of POSIX path of (path to me)
		try
			do shell script quoted form of (here & "/claude-html") & " --update-terminal"
		on error errText
			activate
			display dialog "Could not open Terminal for the update." & return & return & errText buttons {"OK"} default button 1 with icon stop with title "claude-html"
		end try
		return
	end if

	-- Changing the limits from the Token usage page: the link carries the
	-- new values in a fixed grammar and nothing else, checked here whole
	-- before anything runs. The command checks it again, and asks in a
	-- window of its own, Cancel the default, before it writes anything.
	set limitsPrefix to "claude-html://limits/"
	considering case
		set isLimits to (theURL starts with limitsPrefix)
	end considering
	if isLimits then
		if (length of theURL) is (length of limitsPrefix) then return
		set payload to text ((length of limitsPrefix) + 1) thru -1 of theURL
		if not my isLimitsPayload(payload) then return
		set here to do shell script "dirname " & quoted form of POSIX path of (path to me)
		try
			do shell script quoted form of (here & "/claude-html") & " --limits-apply " & quoted form of payload
		on error errText number errNum
			-- 3: a window asking is already open, which says it all.
			if errNum is not 3 then
				activate
				display dialog "The limits were not changed." & return & return & errText buttons {"OK"} default button 1 with icon stop with title "claude-html"
			end if
		end try
		return
	end if

	-- Opening a project: no dialog, because the point of it is to be quick.
	-- It can only ever reach a folder already in the index, inside the projects
	-- root, and it only ever opens — it never runs anything.
	set openPrefix to "claude-html://open/"
	if theURL starts with openPrefix then
		set sid to text ((length of openPrefix) + 1) thru -1 of theURL
		if sid ends with "/" then set sid to text 1 thru -2 of sid
		if not my isSessionId(sid) then return
		set here to do shell script "dirname " & quoted form of POSIX path of (path to me)
		try
			do shell script quoted form of (here & "/claude-html") & " --open " & quoted form of sid
		on error errText
			activate
			display dialog "Could not open that project." & return & return & errText buttons {"OK"} default button 1 with icon stop with title "claude-html"
		end try
		return
	end if

	-- Resuming: no dialog either. It can only open Terminal on a conversation
	-- the index already lists, through the launcher claude-html wrote for it;
	-- the command checks the id against the manifest before anything opens.
	set resumePrefix to "claude-html://resume/"
	if theURL starts with resumePrefix then
		set sid to text ((length of resumePrefix) + 1) thru -1 of theURL
		if sid ends with "/" then set sid to text 1 thru -2 of sid
		if not my isSessionId(sid) then return
		set here to do shell script "dirname " & quoted form of POSIX path of (path to me)
		try
			do shell script quoted form of (here & "/claude-html") & " --resume-session " & quoted form of sid
		on error errText
			activate
			display dialog "Could not resume that conversation." & return & return & errText buttons {"OK"} default button 1 with icon stop with title "claude-html"
		end try
		return
	end if

	set prefix to "claude-html://delete/"
	if theURL does not start with prefix then return
	set sid to text ((length of prefix) + 1) thru -1 of theURL
	if sid ends with "/" then set sid to text 1 thru -2 of sid
	activate
	if not my isSessionId(sid) then
		display dialog "That link does not name a conversation." buttons {"OK"} default button 1 with icon stop with title "claude-html"
		return
	end if

	-- The app is built beside the scripts, so that is where to find them.
	set here to do shell script "dirname " & quoted form of POSIX path of (path to me)
	set cli to quoted form of (here & "/claude-html")
	try
		set plan to do shell script cli & " --delete-plan " & quoted form of sid
	on error errText
		display dialog "Could not look that conversation up." & return & return & errText buttons {"OK"} default button 1 with icon stop with title "claude-html"
		return
	end try

	set theTitle to sid
	set theAction to ""
	set theReason to ""
	set things to {}
	set promptCount to 0
	set savedDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to tab
	repeat with aLine in paragraphs of plan
		set parts to text items of (contents of aLine)
		if (count of parts) > 1 then
			set k to item 1 of parts
			if k is "TITLE" then
				set theTitle to item 2 of parts
			else if k is "ACTION" then
				set theAction to item 2 of parts
			else if k is "REASON" then
				set theReason to item 2 of parts
			else if k is "ITEM" and (count of parts) > 2 then
				set end of things to (item 3 of parts) & ":  " & (item 2 of parts)
			else if k is "HISTORY" then
				set promptCount to (item 2 of parts) as integer
			end if
		end if
	end repeat
	set AppleScript's text item delimiters to savedDelims

	if theAction is "refuse" then
		display dialog theReason buttons {"OK"} default button 1 with icon stop with title "claude-html"
		return
	end if

	if theAction is "hide" then
		set msg to "Hide " & quote & theTitle & quote & " from the index?" & return & return & "It lives on claude.ai, so it is only hidden here, and a new export will not bring it back. Delete it on claude.ai to remove it for good."
		set okButton to "Hide"
	else
		set msg to "Delete " & quote & theTitle & quote & "?" & return & return & "These move to the Trash, where Put Back restores them:" & return
		set shown to 0
		repeat with t in things
			set shown to shown + 1
			if shown > 10 then exit repeat
			set msg to msg & return & "  " & (contents of t)
		end repeat
		if (count of things) > 10 then set msg to msg & return & "  ...and " & ((count of things) - 10) & " more"
		if promptCount > 0 then set msg to msg & return & return & promptCount & " prompt(s) also come out of your up-arrow history; a copy of them goes to the Trash too."
		set okButton to "Move to Trash"
	end if

	-- Cancel is the default, and pressing it ends everything here.
	display dialog msg buttons {"Cancel", okButton} default button "Cancel" cancel button "Cancel" with icon caution with title "claude-html"

	try
		do shell script cli & " --delete " & quoted form of sid & " --yes"
		display dialog "Done." buttons {"OK"} default button 1 giving up after 3 with title "claude-html"
	on error errText
		display dialog "Not all of it went through. The index now shows what is left." & return & return & errText buttons {"OK"} default button 1 with icon stop with title "claude-html"
	end try
end open location

-- Only a session id may reach the shell: 36 characters, hex and four hyphens.
on isSessionId(s)
	if length of s is not 36 then return false
	repeat with i from 1 to 36
		set c to character i of s
		if i is in {9, 14, 19, 24} then
			if c is not "-" then return false
		else if "0123456789abcdef" does not contain c then
			return false
		end if
	end repeat
	return true
end isSessionId

-- The limits a link may carry, as limits-cli.sh reads them:
--   v1/<rules>/<budget>/<warn>/<notify>
-- rules: none, or 1 to 8 of day-HHMM-percent joined by dots; budget: none,
-- or dollars-period; warn: two percentages; notify: on or off. Lower case
-- letters, digits, dots, slashes and hyphens, at most 160 of them.
on isLimitsPayload(s)
	if (length of s) < 1 or (length of s) > 160 then return false
	considering case
		repeat with c in (characters of s)
			if "abcdefghijklmnopqrstuvwxyz0123456789./-" does not contain (contents of c) then return false
		end repeat
		set parts to my splitText(s, "/")
		if (count of parts) is not 5 then return false
		if item 1 of parts is not "v1" then return false
		set r to item 2 of parts
		if r is not "none" then
			set rs to my splitText(r, ".")
			-- An empty field splits into no items at all: refused, not taken as none.
			if (count of rs) < 1 or (count of rs) > 8 then return false
			repeat with oneRule in rs
				if not my isRule(contents of oneRule) then return false
			end repeat
		end if
		set b to item 3 of parts
		if b is not "none" then
			set bs to my splitText(b, "-")
			if (count of bs) is not 2 then return false
			if not my isAmount(item 1 of bs) then return false
			if {"day", "week", "month"} does not contain {item 2 of bs} then return false
		end if
		set w to my splitText(item 4 of parts, "-")
		if (count of w) is not 2 then return false
		if not my isPct99(item 1 of w) then return false
		if not my isPct99(item 2 of w) then return false
		if {"on", "off"} does not contain {item 5 of parts} then return false
	end considering
	return true
end isLimitsPayload

on isRule(t)
	set p to my splitText(t, "-")
	if (count of p) is not 3 then return false
	considering case
		if {"mon", "tue", "wed", "thu", "fri", "sat", "sun"} does not contain {item 1 of p} then return false
	end considering
	set hm to item 2 of p
	if (length of hm) is not 4 or not my isDigits(hm) then return false
	if ((text 1 thru 2 of hm) as integer) > 23 then return false
	if "012345" does not contain (character 3 of hm) then return false
	set pc to item 3 of p
	return (my isPct99(pc) or pc is "100")
end isRule

on isDigits(t)
	if (length of t) < 1 then return false
	repeat with c in (characters of t)
		if "0123456789" does not contain (contents of c) then return false
	end repeat
	return true
end isDigits

on isPct99(t)
	if (length of t) < 1 or (length of t) > 2 then return false
	if not my isDigits(t) then return false
	return (character 1 of t) is not "0"
end isPct99

on isAmount(t)
	set p to my splitText(t, ".")
	if (count of p) > 2 then return false
	set n to item 1 of p
	if (length of n) < 1 or (length of n) > 6 or not my isDigits(n) then return false
	if (character 1 of n) is "0" then return false
	if (count of p) is 2 then
		set f to item 2 of p
		if (length of f) < 1 or (length of f) > 2 or not my isDigits(f) then return false
	end if
	return true
end isAmount

on splitText(t, d)
	set saved to AppleScript's text item delimiters
	set AppleScript's text item delimiters to d
	set out to text items of t
	set AppleScript's text item delimiters to saved
	return out
end splitText
