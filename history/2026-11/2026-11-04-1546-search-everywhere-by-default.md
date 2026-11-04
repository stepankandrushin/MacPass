# Search looks everywhere by default

The owner asked for the search filter to start on *Everywhere* after a fresh install, or whenever no
filter had been set before. It used to start on Title and Username.

The change: `-[MPEntrySearchContext init]` (MacPass/MPEntrySearchContext.m) now uses
`MPEntrySearchAllAttributes`, the flag of the Everywhere button, instead of
`MPEntrySearchTitles|MPEntrySearchUsernames`. `+defaultContext` is this init, and `+userContext`
falls back to it when `EntrySearchFilterContext` is not in the defaults. Everywhere is one of the
exclusive flags (`MPEntrySearchSingleFlags`), so it is used alone. Other code is unchanged:

- Turning every filter off still falls back to Title (`-toggleSearchFlags:`). If it fell back to
  Everywhere, clicking Everywhere could not switch it off.
- Every change to a search context writes it to `EntrySearchFilterContext` (`_updatePreferences`),
  which includes the first search of an install. Any install that has searched once has a stored
  filter and keeps it, so this does not change existing installs. a1 had flags 32 (Everywhere)
  stored already.
- The README lists this under "What's different in this fork".

## Verified on a1

The Debug build (`xcodebuild` with run.sh's flags and `XCODE_XCCONFIG_FILE=build/deployment-target.xcconfig`)
succeeded. Without that xcconfig, Xcode 27 rejects the 10.13 deployment target. A copy of the app
got its own bundle ID (`io.github.stepankandrushin.MacPass.searchtest`), so its settings started
empty and the owner's stayed untouched. It was signed ad hoc and opened
MacPassTests/Databases/Test_Password_1234.kdbx. A search for "Entry" opened the filter bar with
Everywhere selected, and the copy had stored `searchFlags = 32`. Afterwards the copy, its defaults
domain and its LaunchServices registration were removed.

Lessons from the test:

- With two MacPass processes running, System Events' `first process whose unix id is N`
  resolves to the process *by name*. Its `set frontmost` brought the owner's release forward,
  and "1234", Return and Cmd-F went to his pass.kdbx window instead of the test copy. That
  window reported `AXEdited 0` and ~/cloud/pass.kdbx was unchanged since 13:53, so nothing was
  edited or saved. Its Edit menu offered "Undo Set Notes", which predates the test. Address a
  test copy by PID through the AX API (`AXUIElementCreateApplication(pid)`,
  `CGEvent.postToPid`), not through System Events.
- A fresh install has AllowScreenshots off, so `screencapture -l` fails with "could not create
  image from window" and full-screen captures leave the window out. Turn AllowScreenshots on in the
  test copy's own domain; it applies live.
