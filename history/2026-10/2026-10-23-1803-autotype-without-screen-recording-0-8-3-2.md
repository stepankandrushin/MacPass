# Auto-Type without Screen Recording, released as 0.8.3.2

On 2026-10-23, release 0.8.3.1 on a3 played the no-match sound on every global Auto-Type: MacPass found the target
window through CGWindowListCopyWindowInfo, only among windows with a kCGWindowName, and macOS hides those names from
apps without Screen Recording (infra history/2026-10/2026-10-23-1733-a3-macpass-autotype-needs-screen-recording.md).

Upstream asked for Screen Recording because it read window titles only from the window server. The fork already took
the title and URL from Accessibility (04eed5af), but only after a named window was found. Commit c59dc53b:

- `mp_infoDictionary` (NSRunningApplication+MPAdditions.m) takes the front app's topmost layer-0 window by z-order,
  which the window server gives without Screen Recording, keeps its number for the candidate preview, and takes the
  title and URL from Accessibility; the window server's name is the fallback title. It fails only when neither gives a
  title.
- The Autotype Doctor checks Accessibility only; its Screen Recording section, the request button and the
  checks behind them are gone (xib and the localized .strings of that view). Accessibility's explanation now says it
  also reads the front window's title and URL (Base and ru).
- The window-title list of the association editor (MPWindowTitleComboBoxDelegate.m) reads the windows of regular
  apps through Accessibility instead of kCGWindowName.
- The candidate preview shows the app icon when the window cannot be captured, instead of crashing on
  CFRelease(NULL).
- The unused copy of the lookup, `_infoDictionaryForApplication:` in MPAutotypeEnvironment.m, is removed.

Test on a1 with the notarized 0.8.3.2 build from `scripts/release.sh --no-publish`, run from /tmp, with Accessibility
granted and Screen Recording not: a local form at http://localhost:8765/login in Chrome, an entry with URL
http://localhost:8765/login and a different title, "Include Entry URL" off and "Include Entry URL Host for matches"
on. ⌃⌥M (the default hotkey; the settings comment says Cmd) typed the username and password and submitted the form.
macOS asked once for MacPass to control Chrome (Automation), as upstream does. The window-title list of the
association editor was not tried by hand.

Published with `scripts/release.sh` as https://github.com/stepankandrushin/MacPass/releases/tag/0.8.3.2 (build
26990); the first run failed on Apple's timestamp server three times, the second went through. a3 gets it through
Sparkle. On a1 the fork's bundle ID keeps the Accessibility and Chrome Automation grants of that test; its defaults
were deleted.
