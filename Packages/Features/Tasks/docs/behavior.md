# Behavior

## Capture
- The shortcut (none by default, set in Settings › Features › Tasks) or + in the tab starts a capture; Esc cancels it at any step.
- First the app in front (the one behind Vortex's window when Vortex itself is in front), its window title and, in a browser, the page address are noted (a browser's one-time Automation prompt is answered first); then the display under the pointer is taken and freezes.
- Vortex's own windows are not on the frozen screen; the notch shows «Стоп-кадр · Esc», later «Нова задача · Esc»; «Виділи область · Esc — скасувати» shows above the Dock.
- Dragging draws the frame, with a crosshair pointer (macOS 15+); outside it the screen dims; its size shows under it. A frame under 8 pt is taken for a click and ignored.
- Once drawn, the framed part moves to the left, the rest blurs, and the fields show: title, priority, source, retake, Cancel, Save.
- The title is «Задача N», selected, so typing replaces it, also right after a frame drawn with the mouse; ⌘V, ⌘C, ⌘X, ⌘A and ⌘Z work in it, also under a Cyrillic layout; «Підставити» puts the first line of text found in the frame instead and hides once it is the title.
- Priority is Low by default; Low, Medium or High.
- Return saves, also from the title field; an emptied title saves as «Задача N»; the retake button draws the frame again on the same frozen screen.
- A second press of the shortcut while a capture is under way does nothing.
- Vortex comes to the front with the frozen screen; saving or cancelling gives the front back to the app the user was in, with its keyboard focus.
- Another app coming to the front ends the capture, so the frozen screen never hides it: a prompt of the system (Screen Recording's periodic confirmation, a browser's Automation) or ⌘Tab.

## After saving
- The framed part and the whole screen are saved; the text on both is recognized in the background (Ukrainian, Russian, English).
- Text not recognized before Vortex quit is recognized at the next launch.

## The list
- Filters: Active or Done; every priority or one; today, yesterday, the last 7 days or all.
- Active tasks: high priority first, newest first within a priority; done tasks: the last done first.
- Search finds every word of the query in the title, the recognized text, the app, the window title or the page address, ignoring case.
- A row shows the done mark, the picture, title, source, priority and time («14:21», «Учора», «6 жовт.»), kept current past midnight.
- The done mark finishes a task in one click: it leaves the active list and «Задачу виконано · Скасувати» shows for 5 s under the list; in Done it brings the task back.
- A click on the done mark only marks the task; anywhere else on the row opens it.
- Marked done in the list, the row crumples into a paper ball that flies into «Виконані», which bumps as it lands; the task leaves the list once the row has crumpled. With Reduce Motion it just leaves.
- Empty: «Задач ще немає» with how to start; «Активних задач немає», «Виконаних задач ще немає», or «Нічого не знайдено» for a search or narrowed filters.

## The card
- A click on a row opens its card in the tab; «‹ Задачі» goes back.
- The picture shows whole; a click shows the whole screen over the display under the pointer, fitted to it: the framed part as it was, the rest dimmed as while framing, an outline closing in on the part; the notch shows «Задача N · Esc».
- The whole screen fades in already dimmed, so it never flashes undimmed first; only the outline moves.
- A click, Esc, Space or Return closes the whole screen, and so does another app coming to the front, the capture shortcut, or the Vortex window closing or losing the keyboard; the app in front stays in front, and the Vortex window stays open under it and keeps the keyboard all along (other keys do nothing meanwhile); an app that came to the front keeps it.
- With the Vortex window closed by the time the picture is read, the whole screen does not show.
- Clicks close it only from 0.35 s after it shows, so a double click on the picture leaves it open; it can't be opened during a capture.
- Tasks saved before the place of the part was kept (before 7 Oct 2026) show the whole screen without the dimming.
- Title and priority change in place; the title is saved once typing pauses, and an emptied one is «Задача N» again when leaving it.
- Each change saves only itself, so a title saved after the pause never undoes a priority or done mark set meanwhile.
- «Відкрити джерело» opens the page in the browser it came from, or brings the app to the front.
- Готово finishes the task and goes back to the list; the bin deletes it with its pictures.

## Permissions
- Without Screen Recording the first attempt ever shows the system's prompt; later ones, also after a relaunch, open System Settings at Screen Recording; a notification says how to allow it.
- Page addresses need Automation of each browser, asked by macOS on the first capture from it; Firefox gives none.
