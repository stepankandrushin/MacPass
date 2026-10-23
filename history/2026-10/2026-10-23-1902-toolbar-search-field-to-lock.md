# Toolbar search field stretched to the Lock button again (not released)

The owner on 2026-10-23: since the latest macOS the search field in the toolbar is very short; it should reach the
Lock button. On a1 (macOS 27, Darwin 27.0.0) the field of 0.8.3.2 was about 120 pt wide, its placeholder cut to
"Search Ever", centered between two flexible spaces.

What macOS 27's toolbar does, measured with System Events on a 1391 pt window:

- With no size set (the code since macOS 11), the field stays at its intrinsic width.
- `item.minSize`/`maxSize` still work, but the toolbar caps the field at 333 pt (325 pt field + 8 pt) whatever
  `maxSize` says; a smaller `maxSize` (200) is honoured.
- Without `centeredItemIdentifier`, flexible spaces stay at their minimum and the spare room goes between the window
  title and the first item; with it, both flexible spaces around the centered item take the room.
- A width constraint on the field, at priority 300 or higher, is kept by the toolbar as the item's width; too wide and
  items go into the overflow menu instead of the field shrinking. Below that (100, 10) the 333 pt cap applies.

Commit d59f690e keeps the default layout and the centering, and gives the field a width constraint (priority 750)
that MPToolbarDelegate fits to the room between the items on either side of it, minus 8 pt per flexible space
between: on NSWindowDidResizeNotification (shrinking first by the width the window lost, before the toolbar lays out),
on items added or removed, and once after the window gets its toolbar. A change is measured again, at most 4 passes;
it settles in one. Toolbars without a flexible space next to the field are left alone. macOS before 11 keeps
min 140 / max 400.

Tested on a1 with the Debug build (`scripts/run.sh`) and a throwaway /tmp/mp/test.kdbx (pykeepass, password `test`),
with AllowScreenshots switched on for the test (MacPass sets NSWindowSharingNone otherwise, and screencapture gets
nothing) and deleted afterwards; LastDatabasePath was put back to file:///Users/s/cloud/pass.kdbx. Results:

- 1391 pt window: field 680 pt, from Action (8 pt gap) to Lock (8 pt gap); Cmd-F, typing, filtering, Escape and
  lock all fine.
- Window resized in 13 to 29 pt steps from 1391 down to 900 and up to 1560: no item ever in the overflow menu, the
  field ends 8 pt before Lock (199 pt at 900, 827 pt at 1547). At 800 pt and less, Lock and Inspector go into the
  overflow menu with the field at its 140 pt minimum, as the short field would at about the same width.
- UseUnifiedToolbar off (expanded toolbar): field 938 pt, to Lock.
- Later, after a rebuild: the window's right edge dragged with real CGEvents (60 steps, 15 ms apart) to 918, 518,
  1018, 1568 and back to 1391 pt wide: the field ends 8 pt before Lock each time (207, 307, 857, 680 pt); at 518 pt
  the items go into the overflow menu and all come back on widening. Full screen: the field runs to Lock.
- Not tried: toolbar customization, macOS 11 to 26.

The owner then said a1 is mainly a development machine, so the mouse can be used for tests any time, and that
AllowScreenshots should stay on; it was not set in either MacPass domain on a1, so it was written for
io.github.stepankandrushin.MacPass and left on (noted in dotfiles claude/machines/a1.md).

Before and after screenshots went to the owner through notify-owner. Not released, as asked.
