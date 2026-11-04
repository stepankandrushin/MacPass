# A merge below the root group was taken for none: fixed (not released)

The task of next-prompts/2026-11-03-2305-fix-unsaved-merge-after-concurrent-edit.md, the defect of
history/2026-11/2026-11-03-2305-test-merge-on-two-macs.md: a1 merged pro's earlier rename of the same entry and the
Nextcloud conflict copy of its own save, stayed unedited and trashed the copy at once, so only File > Save wrote the
merge.

## The cause

It was not NSDocument's change count. `MPTreesHoldTheSame` (c90a995e) compared the trees with KeePassKit's
`-[KPKGroup _compareToNode:options:]`, whose loop over the subgroups takes both sides from the receiver
(`otherGroup = obj` of `self.mutableGroups`): each subgroup is compared with itself, so any difference below the root
group counts as none. The test database keeps its entries in a group `Test`, as pass.kdbx keeps its entries in groups.
a1's merge of pro's save therefore found the merged tree the same as before (`changed` NO) and the same as the file,
took the `NSChangeCleared` branch, and `_mergeConflictCopies` trashed the copy as one that adds nothing. The merge of
pro's next save at 23:00:12 did the same. All of MPTestDocument's tests had their entries in the root group. Also,
`-[KPKEntry _compareToNode:options:]` compares only the number of history items, as the result of its loop over them
is never used.

It is shown with the real versions. a1's 22:59:11 save (the conflict copy, still in a1's Trash) was opened as the
document, and pro's 22:59:24 save (dl.rseS/merge-test.kdbx in the 11-03 session's /tmp/mp-merge-test on a1, whose
entry is pro's 22:59:08 rename `same-pro` with `seed` and ` a1` in its history) was put in its place. The code of
0.8.3.4 cleared the document and trashed the copy. With the fix, the document is edited and the copy kept, and the save
holds `same-a1` with `seed`, ` a1` and `same-pro` in its history, as File > Save wrote on 11-03.

The same blind spot hit every merge whose difference was below the root group: a file written over by a Mac with an
older copy stayed as it was in the document, which was left clean; and a conflict copy that added entries in a group was
merged into the document, not saved, and trashed at once.

## The fix, ddba9c0a

`MPTreesHoldTheSame` matches groups (the root included) and entries by UUID. It compares each by version, the way
KeePassKit's merge tells versions apart: the modification time, the time it was moved, and, for an entry, the
modification times of the older versions in its history. It also compares the deletions, and still leaves access times
out. A difference within one version is not counted. KeePassKit's merge keeps its own side of such a difference on
either Mac: it does so for equal modification times, and for a group's tags and an entry's quality-check flag, which it
does not copy. Counting such a difference would set two Macs saving the database back and forth, or write a stale value
back over another Mac's change. `_mergeTree`'s rules are unchanged; they now rest on a comparison that sees the whole
tree. The README's caveat about the same entry changed on two Macs is gone.

## Tests

New in MPTestDocument, with helpers `_addGroup:to:`, `_add:toGroup:`, `_rename:to:` (it pushes the history first, as
the inspector does) and `_autosave:` (NSAutosaveInPlaceOperation):

- `testAChangeToTheSameEntryElsewhereIsMergedAndSaved`: a1's sequence with the entry in a group. The document renames
  the entry and autosaves. The file is then moved to `test (conflicted copy 2026-11-03 225911).kdbx`, and the other
  device's earlier rename is written in its place. After the merge the document must be edited, with
  hasUnautosavedChanges and the copy kept. After an autosave the file must hold `same-a1` with `same-pro` in its
  history, the copy must be in the Trash and the document clean. On the code before, three checks fail:
  hasUnautosavedChanges and documentEdited are NO, and the copy is already in the Trash.
- `testAFileWrittenOverWithAnOlderVersionGetsBackWhatItLostInAGroup`: on the code before, the document stays clean
  (one failure).
- `testTwoDevicesTakeEachOthersChangesInAGroupWithoutSendingThemBack`: two devices add and rename entries in a group in
  turn, and each is clean after merging the other's save. It guards the new comparison against saving back and forth,
  and passes before and after.

The whole suite under gui-run on a1 ran 36 tests with the same 7 failures as before (MPDatabaseLoading's two,
MPDatabaseSearch's placeholder, MPTestAutotypeDelay, MPTestPluginVersion), none of them in MPTestDocument.

How it was run: a clone in /tmp/macpass-merge-fix on a1, with Carthage, DDHotKey and .local-build.xcconfig copied in.
It was built with an xcconfig that includes the local one and sets PRODUCT_BUNDLE_IDENTIFIER to
`io.github.stepankandrushin.$(PRODUCT_NAME:rfc1034identifier).mergetest`, so the test host had its own defaults,
recent documents and saved state while the owner's 0.8.3.4 ran on a1. The test host does not exit, so the runner
stopped xcodebuild and then the host by its path, /private/tmp/macpass-merge-fix/…. The committed MPDocument.m and
MPTestDocument.m are the same blobs as the tested ones.

## In MacPass on a1

The clone was also built as an app, Debug and Release, with the bundle ID above and a trace of NSDocument's change
counters written to a file (the trace was not committed). It opened a scratch database in /tmp and was driven with
GuiIO (`ssh a1 gui click/type/key`). The other Mac's save was made with pykeepass and put in place as Nextcloud does:
the own save renamed to a conflicted copy, the other one renamed into place.

- Old code, entries in a group, a rename saved at once: the merge cleared the document, the copy went to the Trash at
  once, and nothing was written in the next 25 s.
- Fixed code, the same steps: the document was edited and the copy kept. Autosave wrote `same-a1` 15 s later, with
  `first-a1` and `same-pro` in its history, and then trashed the copy.
- With the entries in the root group, the old code was right too.

## NSDocument, checked rather than assumed (macOS 27.0.1)

This comes from AppKit's code (`dyld_info -disassemble`) and the trace:

- NSDocument keeps (generation, count) pairs, one since saving and one since autosaving among others. NSChangeDone adds
  one to the count, and also to the generation when the count is below zero. NSChangeCleared sets them to zero. An
  autosave in place sets "since saving" to "since autosaving" minus the save's token.
- isDocumentEdited and hasUnautosavedChanges are also YES while an editor is registered (an inspector field being typed
  in), and there is no autosave timer then.
- A save closes the open undo group before it takes its change-count token, so an inspector edit is counted before its
  own save: the count was not off by one.
- "Each save came at the moment of the edit": this is NSDocument's own autosave, which cannot be cancelled and comes
  right after a change is committed. Only the first change after opening waits the 15 s.
- "A window can stay Edited": after such a save the title bar can keep "Edited" while NSDocument reports the document
  saved, with nothing to autosave (seen on a1, in the trace and a screenshot). This is a leftover in the title, not
  unsaved work, and was not changed.

## Left as it was

- When two Macs change the same entry within the same whole second, KeePassKit's merge keeps each side's own version.
  The fix leaves both Macs clean then, and the next save of either decides.
- A group's tags and an entry's quality-check flag changed on another Mac are not taken by the merge: KeePassKit's
  `_updateFromNode:` does not copy them.

## Cleanup

- The scratch app was stopped, its defaults domain deleted, and its three builds unregistered from LaunchServices.
- 14 scratch databases from these runs were removed from a1's Trash: the tests trash conflict copies into the user's
  Trash, as the earlier conflict-copy test does. The 11-03 conflict copy is still in a1's Trash.
- /tmp/macpass-merge-fix was removed.
- The installed MacPass on a1 (0.8.3.4) and pass.kdbx were not touched.

## Not done

Nothing was released, pushed or installed: that is the owner's call. The rest of the prompt's steps 3 and 4 (the two-Mac
test with the fix installed, the release, pass.kdbx's step) are in
next-prompts/2026-11-05-0255-release-merge-in-a-group-fix-and-test-on-two-macs.md.
