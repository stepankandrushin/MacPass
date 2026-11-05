# 0.8.3.5 on a1 and pro: a change to the same entry on two Macs is merged and saved before its conflict copy goes

Steps 1 (the installs) and 2 of next-prompts/2026-11-05-0255-release-merge-in-a-group-fix-and-test-on-two-macs.md.
The release itself (0.8.3.5, build 27170, tag at c6079d73 with ddba9c0a) was done before this session. pass.kdbx was
not opened or edited, and its step 3 is left to the owner.

## Installs

- The release DMG has the same SHA-256 as the build in build/release on a1 (`e8b1f216…`), and Gatekeeper accepts it
  and its app as Notarized Developer ID. On both Macs the app came from the mounted DMG: 0.8.3.4 was moved to the
  Trash as `MacPass 0.8.3.4.app` and 0.8.3.5 copied with `ditto` to /Applications/MacPass.app.
- a1 ran 0.8.3.4 from /Applications with pass.kdbx open and unlocked, not edited: the window's title bar, captured with
  `gui-run screencapture -l<window id>` (AllowScreenshots is on) without bringing it forward, had no "Edited". It
  was quit with NSRunningApplication terminate and started again with `open -g`; pass.kdbx reopened locked. The owner
  has to unlock it again.
- pro ran 0.8.3.4 with only merge-test.kdbx open (its Window menu, over VNC), not edited. Quit and started the same way,
  it reopened merge-test.kdbx, which was unlocked for the test.
- About MacPass says "Version 0.8.3.5 (27170)" on pro and in the second copy on a1 (below); LaunchServices reports
  build 27170 for a1's own copy.
- a3 still runs 0.8.3.4 (27100). The appcast at https://stepankandrushin.github.io/MacPass/appcast.xml listed 0.8.3.5 at
  12:34, a minute after the release. MacPass > Check for Updates could not be clicked from here: a3 has no Screen
  Sharing (nothing listens on 5900), osascript over SSH has no assistive access, and screencapture gets no image. The
  owner has to click it; otherwise Sparkle's daily check (last at 2026-11-04 15:24 UTC) offers it at about 22:24 on
  2026-11-05 and asks before installing.

## The test

As on 2026-11-03: `~/cloud/macpass-merge-test/merge-test.kdbx`, entries in the group Test, a watcher on each Mac logging
every change of the folder and of the Trash (time, mtime, size, hash), and a `log stream` of each MacPass. pro was
driven with vnc-drive from a1 over the LAN; Command is `lsuper` there (`lmeta-a` types an "a"). a1 was driven with
GuiIO, in a second MacPass started with `open -n -a /Applications/MacPass.app merge-test.kdbx`.

That second copy also restored the first copy's window: it opened pass.kdbx, locked, as a tab next to merge-test.kdbx.
The tab was closed with Cmd-W at once, never unlocked, and pass.kdbx was not written (mtime still 2026-11-04 16:26).
The running copy's saved state evidently reads as an unfinished session to a new copy, which restores its windows
although a file was passed.

The same entry (`same-a1`) was renamed on both Macs:

- a1 to `twice-a1` at 12:49:46.4, pro to `twice-pro` at about 12:49:48 (the entries' modification times, 05:49:46 and
  05:49:48 UTC). Each was the first change since its document opened, so each was autosaved 15 s later: a1's at
  12:50:02, pro's at 12:50:03. pro's reached the server first; a3 had it at 12:51:00.
- a1's Nextcloud was in one sync run from 12:39:52, its folder watcher logging about 3,000 changes a second all over
  ~/cloud with Finder at 115 % CPU, and took the conflict only after it: at 12:59:37.8 it renamed a1's save to
  `merge-test (conflicted copy 2026-11-05 125002).kdbx` and put pro's version in its place.
- a1's MacPass saw the change at 12:59:38.8 and merged the file and the copy at 12:59:39.6 to 12:59:40.5. The window
  showed `twice-pro`, edited. Autosave wrote the merge at 12:59:55.1, 17 s after the copy appeared, and the copy went
  to the Trash at the same moment. The file holds `twice-pro`, the later change, with `seed`, ` a1`, `same-pro`,
  `same-a1` and `twice-a1` in its history.
- pro got that save at 13:00:11.5, merged it (one entry change, the history) and wrote nothing; its window showed
  no "Edited" after it. a3 got it at 13:01:00. Its MacPass logged no file coordination for either change, so merge-test.kdbx is
  evidently not open there.
- The three files stayed the same (`6a990dae30`), and nothing was written after 12:59:55 until the watchers stopped at
  13:06. Nothing went back and forth.

On 2026-11-03 a1 merged and trashed the copy without writing, so its change lived only in memory; with ddba9c0a the
merge is saved before the copy goes. a1's window kept "Edited" after both of its saves, the leftover in the title
described in history/2026-11/2026-11-05-0254-merge-in-a-group-taken-for-none.md: closing the document at 13:04 wrote
nothing, which a change not yet autosaved would have. The README's description of merging and conflict copies holds as
written.

## Cleanup

- a1's second copy closed the test document and was quit. Opening merge-test.kdbx had put it first in the fork's
  recent documents, which a fresh launch reopens before LastDatabasePath. File > Open Recent > Clear Menu in that copy
  emptied the list, so the next launch takes LastDatabasePath, still pass.kdbx. The one setting the copy changed, the
  entry table's columns, was written back: the defaults domain is now the same as before the test.
- This run's conflict copy was removed from a1's Trash; the 2026-11-03 one is still there. The 0.8.3.4 apps are in the
  Trash of a1 and pro.
- The watchers, log streams and scratch files on the three Macs were removed. merge-test.kdbx stays open and unlocked
  on pro, as before.

## Not done

- a3's update to 0.8.3.5, through Sparkle by the owner.
- Step 3, pass.kdbx, and the word to the owner that it can join Cairn's `~/c` once every Mac that keeps it open runs
  0.8.3.5: next-prompts/2026-11-05-1308-pass-kdbx-on-two-macs-after-a3-runs-0-8-3-5.md.
