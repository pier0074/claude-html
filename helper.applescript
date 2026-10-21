-- The claude-html delete helper.
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
