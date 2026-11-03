# A database open on several Macs: merged, not asked about, not sent back (not released)

The owner on 2026-11-03: one Mac's MacPass is left open with the database, work goes on on another Mac where it is
open too, and then on a third; on one Mac several windows are no trouble, across Macs synced by Nextcloud there always
is one.

What happened, from the code and from a1:

- Each Mac's MacPass holds its own decrypted copy. A sync tool replacing the file under it reaches
  `presentedItemDidChange`: a probe on a1 saw every replacement, a sync tool's rename over the file and a write in
  place alike, within about a second of the file changing on a1 (each reported twice).
- Then the *File change strategy*, `Ask` by default: Merge, Keep other or Keep mine, a sheet on every Mac with the
  database unlocked, after every save on another. Keep mine leaves the old copy in memory, and its next save meets
  NSDocument's "changed by another application" with Save Anyway, which drops the other Mac's entries. The fork's own
  bundle ID started with no settings, so a Mac that had chosen Merge as the default in upstream MacPass asks again.
- Merge marked the document edited even when it brought nothing of its own, and autosave (on by default) then wrote
  it again: with two Macs unlocked, each merge made the other merge and save, without end, and each such save could
  meet one coming the other way.
- An entry made in this session has times to the fraction of a second, the file whole seconds, so KeePassKit's merge
  took the same entry from another Mac's save for an older version and gave it a history item.
- A sync tool's conflict copy was never looked at.

Commit c90a995e: the default strategy is Merge. A merge, from a change on disk, a save, an unlock or a
conflict copy, runs with undo registration off, first cutting the open tree's times to whole seconds, as
`_reducePrecicionToSeconds` does on save; after a merge of the document's own file the document is clean if it had no
changes of the user's (or only merges') and the file holds the same groups, entries with their histories, and
deletions, compared by KeePassKit's own `_compareToNode:` without access times; otherwise it is edited and autosave
writes what the file lacks. Every save in place, autosave included, first merges a change on disk not yet merged
(unless the user chose Keep mine for that version), so it never writes over another Mac's save. After an unlock and a
merge of the file, conflict copies beside it (`name (…conflict…).ext`, `name.sync-conflict-….ext`,
`name_conflict-….ext`) that open with the same key are merged; one that adds nothing goes to the Trash when the file
already holds the document, one that adds something once a save has written it. When a change of the master key
elsewhere is merged with the key asked for, the document takes that key, so it no longer saves with the old one.

Tests (MPTestDocument, run with `scripts/build-local.sh test` under gui-run on a1, as codesign needs the console's
keychain): two devices saving in turn, each clean after merging the other's save, no history item; a save after an
unnoticed change elsewhere holds both; a file written over with an older version gets its entries back; a conflict
copy is merged and trashed once saved, and `testing (conflict …).kdbx`, though it opens with the same key, is not. On
the code before (a clean clone with only the new test file), the first three fail: the merges leave the documents
edited and add the history item, and the save fails with "The file has been changed by another application"; the
older-version test passes there too, as it guards the new rule that a merge may leave a document clean. The test host
does not exit after the tests; the run is stopped once the results are in. The whole suite: 33 tests, the same 7
failures as before the change (MPDatabaseLoading's two, MPDatabaseSearch's placeholder, MPTestAutotypeDelay,
MPTestPluginVersion), none in the new tests.

With Cairn on a1 and a throwaway database in the synced folder, the other device's saves made with pykeepass on a
Linux machine:

- Its new entry showed in the open window within 3 to 7 s, with no sheet, and the file stayed as it came, on both
  machines, for the next minute.
- An entry added through Item > New Entry was autosaved 16 s later and reached the other machine 2 s after that.
- The other machine writing an old version over the file: a1 put the two entries back within 19 s, with no history.
- Both changed while the other's sync was stopped: Cairn made `test (conflict me 2026-11-03).kdbx`; at the next
  unlock on a1 it was merged, saved and trashed in the same second, and the file on the other machine held the
  entries of both and nothing changed afterwards.

Not done: offering it upstream as a pull request, and a release; a3 and pro still run 0.8.3.3 and upstream 0.8.1.
