# 0.8.3.4 on three Macs: new entries merge cleanly, a change to the same entry on two Macs is left unsaved

The test from next-prompts/2026-11-03-2224-test-merge-on-two-macs.md, with a throwaway database. a3 and pro had
0.8.3.4 (a3 installed it from Sparkle at 22:24), FileChangeStrategy unset (Merge) on both. pass.kdbx was not touched.

Setup:

- `~/cloud/macpass-merge-test/merge-test.kdbx` (Nextcloud), made with pykeepass (KDBX 4, Argon2) and copied to a3 at
  22:27:30; a3 uploaded it 18 s later, but pro and a1 got it only at 22:38: both were in one Nextcloud run since 22:02
  (another session's reorganisation of `realty/`, about 11,000 renames and 2,800 downloads), which takes no new change
  until it ends.
- Opened with `open -a /Applications/MacPass.app <file>` over SSH. On pro that launched MacPass without reopening
  pass.kdbx, as a file was passed.
- The owner, at a3, could not see pro's window over Screen Sharing: AllowScreenshots (off by default) gives document
  windows `NSWindowSharingNone`, which hides them from Screen Sharing as from screenshots. `defaults write
  io.github.stepankandrushin.MacPass AllowScreenshots -bool YES` on pro took effect in the running app at once; it is
  still on there.
- The owner then asked for the test to be done without his Macs: a3 kept the database open and unlocked as a third
  copy, a1 ran the notarized 0.8.3.4 from build/release/dmg (build 27100), pro was driven with vnc-drive over the LAN
  (192.168.1.20:5900, the password of the p20 link file). A watcher on each Mac logged every change of the folder and
  of the Trash (time, mtime, size, hash).

What held:

- Unlocking on pro and a1 wrote nothing. a3's entry made by the owner was saved there four times within 30 s (22:41:43
  to 22:42:12), each time with the same entries; pro had each save 10 to 50 s later and wrote nothing.
- An entry made on a1 (22:49:58, autosaved 22:50:13, uploaded 22:50:17) reached pro and a3 at 22:51:01; pro showed it
  with no sheet and no "Edited", and neither wrote in the next 65 s. An entry made on pro (autosaved 22:52:48) reached
  a3 at 22:53:00 and a1 at 22:53:10, the same way. Nextcloud took 10 to 60 s per direction, its polling.
- A Nextcloud conflict copy is merged and trashed: see below. a3 merged every save quietly and wrote nothing after
  22:42:12.

What did not:

- The same entry renamed on two Macs: pro to `same-pro`, a1 to `same-a1` three seconds later. Each save came at the
  moment of the edit (pro's click on the row saved at 22:59:08, before the rename, which saved at 22:59:24; a1 saved
  at 22:59:11). At 22:59:15 a1's Nextcloud renamed a1's save to `merge-test (conflicted copy 2026-11-03 225911).kdbx`
  and put pro's 22:59:08 version in its place. a1's MacPass saw the change at 22:59:16.25, merged the file and the
  copy (two entry changes in its log), and moved the copy to the Trash at 22:59:16.86, **without writing the file**.
  Its window showed `same-a1`, not edited, nothing to undo. At 23:00:12 it merged pro's 22:59:24 save the same way and
  again wrote nothing. File > Save at 23:00:50 wrote the right merge (`same-a1`, the later change, with `seed`, ` a1`
  and `same-pro` in its history). a3 and pro merged it and stayed clean, and all three files have been the same since.
  For 95 s a1's change was only in its memory and in the trashed copy: a close or a quit then, with the document not
  edited, would have saved nothing, and pro's version would have been the database.
- After a save of its own, a window can stay "Edited" with no further autosave: a1 from 22:54:36 (still at 22:56:49,
  Undo "Set Title"), pro from 22:52:48 until it merged a1's save at 22:55:32, which left it clean without writing.

So `_mergeTree`'s rule (edited unless the file holds all the document does) is not what happened on a1. Its
`updateChangeCount:NSChangeDone` evidently did not leave the document edited, maybe because of NSDocument's change count
after a save made in the middle of an edit, which would also explain the windows that stay "Edited". This is not
established yet; the next step is a unit test of exactly this sequence:
next-prompts/2026-11-03-2305-fix-unsaved-merge-after-concurrent-edit.md. README's "goes to the Trash once the
database holds it" now says it does not yet hold for this case.

Not done: step 2 (pass.kdbx), as the same failure there could lose a change. pass.kdbx cannot join Cairn's `~/c`
yet: besides this, a1 has a Debug build of the fork (0.8.2, build 27120-main of 2026-10-23, build/Build/Products/Debug)
with pass.kdbx open and unlocked, started at 22:37:13 by someone other than this session. That build asks on a change
on disk (FileChangeStrategy unset means Ask before 0.8.3.4). The test database stays open on a3 and pro.
