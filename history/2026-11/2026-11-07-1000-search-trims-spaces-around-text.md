# Search trims spaces, tabs and line breaks around the text

The owner asked the search field in the toolbar to drop spaces, tabs, line breaks and the like
at the start and end of the text, so that `  Dynadot ` finds the entries `Dynadot` finds.

The change: `-[MPDocument updateSearch:]` (MacPass/MPDocument+Search.m) now trims the field's
`stringValue` with `NSCharacterSet.whitespaceAndNewlineCharacterSet` before setting the
search context's `searchString`. That set is Unicode's space separators (no-break space
included), tab, line feed, vertical tab, form feed, carriage return and U+0085. Spaces
inside the text stay: `Dyna dot` still searches for `Dyna dot`.

- This is the only place the toolbar field's text becomes a search string. The Reference Builder's
  search field (MPReferenceBuilderViewController) builds `{REF:…}` text, not a search, so it is
  unchanged.
- The field keeps what was typed. Only the search, and the context stored in
  `EntrySearchFilterContext`, get the trimmed text.
- Text that is only spaces now searches for the empty string, which finds nothing, the same as
  an empty field. Before, it searched for those spaces.
- The README lists this under "What's different in this fork".

## Verified on a1

The Debug build (`xcodebuild` with run.sh's flags and
`XCODE_XCCONFIG_FILE=build/deployment-target.xcconfig`) succeeded. A copy got its own bundle ID
(`io.github.stepankandrushin.MacPass.trimtest`) and AllowScreenshots in its own domain, and opened a
copy of MacPassTests/Databases/Test_Password_1234.kdbx in /tmp. The owner's release (0.8.3.5,
/Applications) kept running and was not touched.

- The search field got two spaces, `Entry`, a tab (Option-Tab types one into a text field), a space
  and Return. Its AXValue read back `"  Entry\t "`. The list showed the database's one entry,
  `Entry`, and the stored context held the search string `Entry`.
- Three spaces and Return gave an empty list.

Afterwards the copy was quit by PID, and the copy, its defaults domain and its LaunchServices
registration were removed. Not released: a1 still runs 0.8.3.5 from /Applications.
