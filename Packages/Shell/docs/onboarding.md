# Onboarding

## When it shows
- At launch, after the first status read, an onboarding that isn't completed opens at its saved page; a fresh install, or one from a release without the onboarding, opens at Welcome.
- It lives in its own standard window, centered on the pointer's screen, about 560×620 pt, with only a close button; never in the notch window.
- Only Done's final button completes it; after that no launch shows it unless Vortex is blocked.
- Closing it (close button or ⌘W) hides it and keeps the page; the menu bar menu then has "Continue setup", which closes the notch window and reopens it at the saved page, even over a single page.
- "Continue setup" shows whenever the onboarding isn't completed, blocked or not; the menu bar icon shows then too, even if hidden.
- ⌘Q in the window quits Vortex; Esc closes only a single page; Return presses the page's main button.

## Pages
- Order: Welcome, Basics, Accessibility, Screen Recording, Paste from Other Apps, the features' own steps, Done.
- Only permissions that enabled features (or keyboard cleaning with Home on) need get rows and pages; one macOS doesn't ask for (`notNeeded`) gets none.
- A saved page that no longer exists resumes at the next page in order, else Done.
- Welcome: the vortex animation (about 2.5 s; only its last frame with Reduce Motion), "Vortex", three lines and "Get started"; a dark backdrop in both appearances.
- Basics: the Notifications row and "Open at login"; after "Turn on" the hint about the notification shows for 15 s or until the status changes.
- "Open at login" shows on for a fresh install, and the real state for one that set it up before; in release builds the user's choice is applied on leaving Basics, never while it shows. Afterwards the switch shows and sets the real state.
- A hard page: the reasons of every feature that needs it, the drawn System Settings mock, and the "Turn on" checkbox; Screen Recording and the pasteboard add the relaunch note.
- The mock's pointer and switch move by Core Animation: the page uses no CPU while it shows. No text is cut short: a page too long for the window scrolls.
- Done: a row per needed permission with ✓, ↻ or the warning; a row that is off opens its page, and Next or Skip there comes back to Done; the notifications row opens Basics.
- Done's hint names the notch only while a notch display is connected, by hover when Open on hover is on, else by click; then the menu bar icon while it shows, otherwise the "Open Vortex" shortcut if one is set.

## Checkboxes, Skip and Next
- Every checkbox shows what macOS says; before the first read it shows no state, and Skip and Next are hidden.
- Clicking a checkbox that is off asks macOS through `PermissionsClient.request`; clicking one that is on, ↻ included, does nothing.
- After "Turn on", more clicks on it do nothing until the status changes, or for 2 s (15 s for notifications).
- Next works only when every permission on the page is on; Skip shows only while one is off and none of those is required.
- A required permission that is off shows "Required": no Skip, Next disabled, and Done's final button disabled. One that can be skipped shows "Optional" while it is off, with Skip beside the disabled Next.
- A feature's step shows Skip until the feature marks it done, then only Next.
- Navigation buttons ignore clicks for 300 ms after each page change.

## Restarts
- Opening the pasteboard's pane marks it "Checked after restart" (↻): Next works and Done shows ↻.
- A page with a permission that works only after a relaunch shows "Restart now"; Vortex comes back on the same page. So it does after System Settings' «Quit & Reopen»: Vortex opens itself again, as System Settings does only while it still runs.
- Done's button reads "Restart and start" while something waits for a relaunch; after that relaunch Done shows again, with "Start using Vortex".
- Vortex relaunches at most once per onboarding; any relaunch clears the pending checks.
- Once a relaunch is asked for, no other navigation or final button is taken until Vortex is gone.

## The single page
- A feature's request shows that permission's page in the same window, with Close instead of Skip and Next.
- With the onboarding on screen, a request only brings it to the front at its page; with it closed before completion, the request gets a single page and the saved page stays.
- A new request switches the single page to the latest permission.
- On a grant it shows ✓ and closes after 1.5 s, the pasteboard's too, which then reads `notNeeded`; turned off again within those 1.5 s, it stays open with the checkbox off. A grant that waits for a relaunch offers "Restart Vortex" and "Later".
- "Restart Vortex" and "Restart to check" reopen the page once after the relaunch.
- After Close the app that was in front gets the front back.

## Blocked
- While a required permission is off, every entry point (hover, notch and ear clicks, the menu bar icon, its menu, the shortcuts, files dragged onto the notch) opens the blocking page instead of the notch window, which closes.
- Before completion that is the onboarding, jumped to the first page with a missing required permission, also from "Continue setup"; after it, the single page of that permission, with Close only.
- It opens by itself at launch, before a page waiting for that relaunch, and whenever Vortex becomes blocked after it.
- A hover shows the blocking page without activating Vortex; entry points used before the first status read wait for it.
- On the grant the blocking page shows ✓, then the next missing required page, or closes.

## The guide panel
- System Settings in front within 10 s of "Turn on" (once per click) turns the window into a 340×300 panel next to System Settings: right of it, left of it, or bottom right of its display.
- It holds the title, a smaller mock, the live checkbox and "Back"; it never takes focus and has no close control.
- It turns back into the window, in front, on the grant, on "Back" or when System Settings quits; it hides while another app is in front.
- "Continue setup", a blocked entry point or a request brings a showing panel forward as a panel; one that hid behind another app turns back into the window, in front.
- Back on the page with the permission still off: "Already on in System Settings? Turn it off and on again." and "Not in the list? Click + and choose Vortex.", with the pane button. For the pasteboard only after a relaunch still reads it off: before one, its page says "Checked after restart" and offers "Restart to check".
