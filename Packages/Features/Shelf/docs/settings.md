# Settings

| Setting | Default | Notes |
| --- | --- | --- |
| Watched folders | none | Any number; subfolders count too |
| File types of a folder | ipa, apk, aab, dmg, zip | Per folder; commas or spaces, any case, dots optional; empty takes every file |

- A folder is added with Add folder… (the folder picker; the empty shelf has the same button), or by typing or pasting a path and pressing Watch (or Enter).
- A folder path watches it for the default types; a file path (an earlier build) watches its folder for that file's type;
  a pattern like `~/StudioProjects/app/last_builds/*.aab` watches that folder for `aab`. `~` is the home folder.
- Adding a folder that is already watched adds the new type to it. A path that does not exist shows "Nothing is at …".
