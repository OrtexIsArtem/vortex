# Behavior

## Capture
- The shortcut (none by default, set in Settings › Features › Tasks) or + in the tab starts a capture; Esc cancels it at any step.
- First the app in front, its window title and, in a browser, the page address are noted; then the display under the pointer is taken and freezes.
- Vortex's own windows are not on the frozen screen; the notch shows «Стоп-кадр · Esc».
- Dragging draws the frame; outside it the screen dims; its size shows under it. A frame under 8 pt is taken for a click and ignored.
- Once drawn, the framed part moves to the left, the rest blurs, and the fields show: title, priority, source, retake, Cancel, Save.
- The title is «Задача N», selected, so typing replaces it; «Підставити» puts the first line of text found in the frame instead.
- Priority is Low by default; Low, Medium or High.
- Return saves, also from the title field; an emptied title saves as «Задача N»; the retake button draws the frame again on the same frozen screen.
- A second press of the shortcut while a capture is under way does nothing.

## After saving
- The framed part and the whole screen are saved; the text on both is recognized in the background (Ukrainian, Russian, English).
- Text not recognized before Vortex quit is recognized at the next launch.

## The list
- Filters: Active or Done; every priority or one; today, yesterday, the last 7 days or all.
- Active tasks: high priority first, newest first within a priority; done tasks: the last done first.
- Search finds every word of the query in the title, the recognized text, the app, the window title or the page address, ignoring case.
- A row shows the done mark, the picture, title, source, priority and time («14:21», «Учора», «6 жовт.»).
- The done mark finishes a task in one click: it leaves the active list and «Задачу виконано · Скасувати» shows for 5 s; in Done it brings the task back.
- Empty: «Задач ще немає» with how to start; «Активних задач немає», «Виконаних задач ще немає», or «Нічого не знайдено» for a search or narrowed filters.

## The card
- A click on a row opens its card in the tab; «‹ Задачі» goes back.
- The picture shows whole; a click shows the whole screen in Quick Look.
- Title and priority change in place and are saved; an emptied title goes back to «Задача N».
- «Відкрити джерело» opens the page in the browser it came from, or brings the app to the front.
- Готово finishes the task and goes back to the list; the bin deletes it with its pictures.

## Permissions
- Without Screen Recording the first attempt shows the system's prompt; later ones open System Settings at Screen Recording; a notification says how to allow it.
- Page addresses need Automation of each browser, asked by macOS on the first capture from it; Firefox gives none.
