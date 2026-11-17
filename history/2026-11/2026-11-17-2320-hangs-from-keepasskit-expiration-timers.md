# MacPass stopped answering for seconds at a time after days open: KeePassKit's expiration timers kept every copied entry

On a3 the release 0.8.3.6 had been running since 2026-11-07 12:17 with pass.kdbx open. At about 22:52 the owner could
not bring its window up with the mouse, and Auto-Type did nothing in Chrome. An earlier hang like it had gone away
with a restart.

## What a3 showed

- `log show` reported a 20.11 s HID response delay at 22:52:24 so the main thread took no click for 20 s from 22:52:04
  on. The file had changed at 22:47:27 and presentedItemDidChange ran then. Autosave was scheduled at 22:51:56 and
  fired 13 s late.
- The CPU report /Library/Logs/DiagnosticReports/MacPass_2026-11-15-000633_s.cpu_resource.diag has 90 s of CPU in
  162 s with the app in the background at background QoS on the efficiency cores. Its stacks run from the block of
  `-[MPDocument presentedItemDidChange]` through `_handleFileChangeWithStrategy:setAsDefault:` then
  `mergeWithContentsFromURL:key:` then `_mergeTree:isOwnFile:options:` and `-[KPKTree copyWithZone:]` down to
  `+[NSObject cancelPreviousPerformRequestsWithTarget:selector:object:]` in the copy of each time info
- `sample` at 22:56 found the main thread idle by then, but each run loop pass walked a long array of timers in
  `__CFRunLoopDoTimers`
- `heap` counted 14672 NSTimer and 21732 KPKTimeInfo against 6941 KPKEntry with history items and about 200 groups.
  Some 14500 time infos whose entries were gone were thus still alive, one per timer.
- pass.kdbx is KDBX 3.1 with AES-KDF at 6000 rounds so the decryption during a merge costs next to nothing.

## The cause

In KeePassKit 3.3.2 and on its master KeePassKit/Core/KPKTimeInfo.m runs `-_updateExpireState` on every change of
`expires` or `expirationDate` and so for every time info that `copyWithZone:` makes and the parser fills. It first
calls `cancelPreviousPerformRequestsWithTarget:selector:object:` which walks every delayed perform of the run loop.
When the entry expires at a later date it calls `performSelector:withObject:afterDelay:` which keeps the time info
until then, often years ahead. A copy of the tree therefore left one time info behind for each expiring entry and
history item, and made every later copy slower.

The fork made it far worse. Since c90a995e in 0.8.3.4 MacPass merges every save another Mac makes, and
`_mergeTree:isOwnFile:options:` copies the tree three times through `MPTreeAsSaved` on top of the parse of the file
and the copy each save makes. With pass.kdbx open on three Macs, saves arrive many times a day. After ten days each
merge spent tens of seconds on the main thread, more under App Nap, and clicks and the Auto-Type hotkey waited for it.

## The fix

The new MacPass/KPKTimeInfo+MPExpirationTimer.m replaces the implementation of `-[KPKTimeInfo _updateExpireState]` in
`+load` or logs and leaves the one of KeePassKit if the method is gone. The new one does what the old one did with
at most one timer per time info: a CFRunLoopTimer on the main run loop in the common modes. The timer holds the time
info weakly and is invalidated when its holder is freed, an associated object of the time info. Setting a new timer
or none frees the old one. No time info is kept alive past its use any more, and nothing walks the delayed performs.
Expired entries are still marked at their date, now also during a menu or a drag. The `-dealloc` of KPKTimeInfo
still calls `cancelPreviousPerformRequestsWithTarget:selector:object:` which is cheap now that its list is short.

The README has a line on it in What's different in this fork.

## Tests

The new MacPassTests/MPTestExpirationTimer.m has four tests:

- `testCopiesOfAnExpiringEntryAreFreed` makes five copies of a tree with an expiring entry and its history item, and
  all ten copied time infos must be freed
- `testAnEntryIsMarkedExpiredAtItsExpirationDate` checks the original and a copy through KVO on `isExpired`
- `testAnEntryThatNoLongerExpiresIsNotMarkedExpired`
- `testAPastDateMarksAnEntryExpiredAtOnceAndALaterOneUnmarksIt`

On a1 `scripts/build-local.sh test` under gui-run ran 40 tests. The 9 of MPTestDocument and the 4 new ones passed.
The failures, none of them new:

- MPDatabaseLoading testLoadVersion1 and testVersion1WrongPassword
- MPDatabaseSearch testSearch
- MPTestAutotypeDelay testDelayExecution
- MPTestPluginVersion testVersionCompare
- MPTestKeyMapper testKeyMapper - not in the earlier notes: the test maps ﬂ and the Apple logo through the current
  keyboard layout, and the one on a1 is Russian at the moment

In a scratch copy on a1 in /tmp/mp-cmp outside ~/cloud the replacement was switched off by an environment variable:

- `testCopiesOfAnExpiringEntryAreFreed` failed for all 10 time infos. `testAnEntryIsMarkedExpiredAtItsExpirationDate`
  raised an NSRangeException inside Foundation in `-[__NSArrayM removeObjectsInRange:]` when two expiring time infos
  fired together
- A benchmark not committed: a tree of 700 entries with 9 history items each, 7000 nodes in all, 30 of the entries
  expiring a year ahead, copied again and again in the Debug build. Without the fix each copy left 300 more timers
  and took about 0.47 s longer than the one before.

| copy | without the fix | with it |
|------|-----------------|---------|
| 1    | 2887 ms         | 296 ms  |
| 5    | 4750 ms         |         |
| 10   | 7091 ms         |         |
| 15   | 9440 ms         |         |
| 20   |                 | 290 ms  |
| 40   |                 | 291 ms  |
| 60   |                 | 291 ms  |

## Not done here

Auto-Type was not tried in Chrome on a3 because the owner was using the Mac and dictating at the time. The 0.8.3.6
running on a3 keeps its timers until it quits.
