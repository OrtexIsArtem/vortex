---
title: How to Lock a MacBook Keyboard for Cleaning · Vortex
description: "How to clean a MacBook keyboard without turning it off: lock every key, wipe, and get them back in one click. Plus Apple’s advice on cloths and liquids."
heading: How to lock a MacBook keyboard for cleaning
label: MacBook keyboard cleaning
published: 2026-11-01
updated: 2026-11-01
chapter: keyboard
faq:
  - q: Can I clean my MacBook keyboard without turning it off?
    a: >-
      Apple’s advice is to shut down and unplug the power adapter first. If you keep your Mac on, lock the keys before
      you wipe, so nothing types or runs a shortcut, and use a dry, soft, lint-free cloth. Save a damp cloth or a
      disinfectant wipe for when the Mac is shut down.
  - q: How do I lock the keyboard on a Mac for cleaning?
    a: >-
      Use an app that holds key presses back. In Vortex, click the keyboard button on Home: every key stops until you
      click “Turn the keyboard back on”. Vortex needs the Accessibility permission for it.
  - q: Does Vortex lock the trackpad, Touch ID or Caps Lock?
    a: >-
      No. The mouse and trackpad keep working, so you can click the keyboard back on. macOS doesn’t let any app lock
      Touch ID or Caps Lock, so Caps Lock may still be on after you clean.
  - q: What happens if Vortex quits while the keyboard is locked?
    a: >-
      The keys come back. The lock lasts only while Vortex runs, so if it quits or crashes, your keyboard works again.
      Turning off Vortex’s Accessibility permission ends a lock at once too.
  - q: Is Vortex free?
    a: >-
      Yes. Vortex is free and open source under the MIT license, with no account, for macOS 14 or later on Apple
      silicon. It never goes online by itself.
---

The safest way to clean a MacBook keyboard is Apple’s: shut down, unplug the power adapter and wipe the keys with a soft, lint-free cloth. If you’d rather keep your Mac on, lock the keyboard first, so the cloth doesn’t type, quit an app or turn up the volume. This guide covers both, and how [Vortex](../), a free Mac app, locks every key with one click and gives them back with another.

Apple’s advice here is taken from its support articles as of November 2026. Follow the links for the full text.

## The ways at a glance

| Way | Good for | Keep in mind |
| --- | --- | --- |
| Shut down, unplug, wipe | Any cleaning, a damp cloth or disinfectant wipe included | Apple’s advice. Your work waits until the Mac starts up again. |
| Compressed air | A key that doesn’t respond or feels different | Apple’s steps for MacBook (2015 and later) and MacBook Pro (2016 and later) |
| Lock the keys, Mac stays on | A quick dry wipe when you don’t want to shut down | Takes an app such as Vortex. Touch ID and Caps Lock still work. |

## How Apple says to clean a MacBook keyboard

Apple’s guide for MacBook, MacBook Pro and MacBook Air comes down to a few rules. ([How to clean your Apple products](https://support.apple.com/103258))

- **Shut down first.** Choose **Apple menu › Shut Down**, then unplug the power adapter and any other cables and devices.
- **Use only a soft, lint-free cloth,** damp for the outside of the Mac. No abrasive cloths, towels or paper towels, and don’t wipe too much: that might cause damage.
- **To disinfect the keys,** you may gently wipe them with a 70 percent isopropyl alcohol wipe, a 75 percent ethyl alcohol wipe or Clorox Disinfecting Wipes. Don’t use anything with bleach or hydrogen peroxide.
- **Keep liquids out.** Don’t get moisture into any opening, and don’t spray liquid or cleaner onto the Mac. No aerosol sprays, solvents or abrasives.
- **If liquid gets inside,** get help from an Apple Store or an Apple Authorized Service Provider as soon as possible.

A MacBook with Apple silicon can be turned on with its keyboard or trackpad ([Apple](https://support.apple.com/120622)), so pressing keys as you wipe may start it up. If it does, shut it down again before you go on.

### A key that sticks: compressed air

If a key on a MacBook (2015 and later) or MacBook Pro (2016 and later) doesn’t respond, or feels different from the others, Apple cleans the keyboard with compressed air. ([How to clean the keyboard of your MacBook or MacBook Pro](https://support.apple.com/102365))

1. Hold your Mac at a 75-degree angle, not quite vertical.
2. Spray the keyboard, or just the affected keys, from left to right.
3. Turn the Mac onto its right side and spray again, from left to right.
4. Turn it onto its left side and do the same.

Use the straw that comes with the can, keep its end about half an inch from the keys, and don’t turn the can upside down while you spray. If a key still doesn’t respond, take your Mac to an Apple Store or an Apple Authorized Service Provider.

## Why cleaning a Mac that’s on goes wrong

Every key works while you clean. The cloth types into whatever is in front, the top row changes the brightness and the volume, and Return can send a message you were still writing. A press that catches ⌘ runs a shortcut: ⌘Q quits the current app, ⌘W closes the front window, and ⌘Delete moves the selected item to the Trash. ([Mac keyboard shortcuts](https://support.apple.com/102650))

So you either shut down or stop the keys first.

## Lock the keyboard with Vortex

[Vortex](../) is a free, [open-source](https://github.com/OrtexIsArtem/vortex) Mac app that lives in the notch. One button on its Home tab locks the keyboard for cleaning:

- **Every key stops:** letters, modifiers, Esc, the function row and the keys for brightness, sound and media.
- **The mouse and trackpad keep working,** so one click on **Turn the keyboard back on** brings the keys back.
- **The window stays open.** While the keys are locked, nothing closes it: not moving the pointer away, a click elsewhere, Esc, the notch or the menu bar icon. Vortex comes to the front, so a key that still gets through lands in Vortex and goes no further.
- **The keys come back by themselves** if Vortex quits or crashes, or if you turn off its Accessibility permission during a lock.

Vortex needs the Accessibility permission for this: macOS lets an app hold keys back only with it. Vortex asks macOS for it only when you click **Turn on**, and it never goes online by itself. The rules the lock follows are in [Vortex’s docs](https://github.com/OrtexIsArtem/vortex/blob/main/Packages/Shell/docs/behavior.md#keyboard-cleaning).

### What it can’t lock

macOS never lets an app lock the Touch ID (power) button or Caps Lock. Caps Lock may still be on when you’re done: press it once to turn it off.

The lock doesn’t turn anything off, either: your Mac stays on. For a damp cloth or a disinfectant wipe, shut down and unplug first, as Apple says.

If all you need is the lock, small apps that do only that exist too.

## Lock your keyboard for cleaning, step by step

1. **Install Vortex.** It’s free, for macOS 14 or later on Apple silicon. [Download it below](#download). Vortex isn’t notarized by Apple, so the first launch takes one more step, shown there.
2. **Turn on Accessibility.** Vortex’s setup has an **Accessibility** page: press **Turn on**, then switch on Vortex in **System Settings › Privacy & Security › Accessibility**. Until then, the keyboard button shows a yellow warning, and clicking it opens that page.
3. **Open Vortex.** Point at the notch, or click it. On a Mac without one, click Vortex’s icon in the menu bar.
4. **Lock the keys.** On **Home**, click the keyboard icon at the top right of the panel at the bottom; its tooltip says **Lock the keyboard for cleaning**. The window now shows **Keyboard cleaning mode** and **All keys are locked**.
5. **Clean.** Unplug the power adapter and other cables, as Apple advises, and wipe the keys with a dry, soft, lint-free cloth.
6. **Turn the keys back on.** Click **Turn the keyboard back on** with the trackpad or mouse. The keys work again at once, in the app you were using.

You can try it in your browser first: [the keyboard demo](../#keyboard) on the home page lights up the keys you press, then locks them while you wipe with the pointer. It never holds back your real keys.
