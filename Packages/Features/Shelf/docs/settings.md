# Settings

| Setting | Default | Notes |
| --- | --- | --- |
| Watched folders | none | Any number; subfolders count too |
| File types of a folder | ipa, apk, aab, dmg, zip | Per folder; commas or spaces, any case, dots optional; empty takes every file |
| Notch flash colors | blue (5AC8FA), green (4ADE80) | One per new file, in order; + adds a color, − removes the last; after the last, white |

- A folder is added with Add folder… (the folder picker; the empty shelf has the same button), or by typing or pasting a path and pressing Watch (or Enter).
- A folder path watches it for the default types; a file path (an earlier build) watches its folder for that file's type;
  a pattern like `~/StudioProjects/app/last_builds/*.aab` watches that folder for `aab`. `~` is the home folder.
- Adding a folder that is already watched adds the new type to it. A path that does not exist shows "Nothing is at …".
- Test plays the flashes three seconds later — every color, then white — so the window can be closed to watch the notch.
- Colors are picked in the system color panel; it floats above Vortex and keeps the window open while it is shown.
