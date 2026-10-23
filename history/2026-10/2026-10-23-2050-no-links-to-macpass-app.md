# No links to upstream's website; plugin list from the fork's repository

The owner on 2026-10-23, after the About box got "A fork of MacPass" linking to github.com/MacPass/MacPass: credit
upstream's authors, but link only to our GitHub, never to their website. Upstream lost a website domain once
before and someone else bought it, so a link to their site is a malware risk.

- About box (Credits.rtf): "A fork of MacPass by Michael Starke and the MacPass contributors." is plain text now;
  the only project link is github.com/stepankandrushin/MacPass.
- The plugin list was downloaded at runtime from https://macpass.app/data/plugins.json (MPPluginRepositoryURL),
  the actual exposure: whoever holds that domain decides which plugin downloads MacPass offers. It now comes from
  https://raw.githubusercontent.com/stepankandrushin/MacPass/main/MacPass/Resources/plugins.json, the copy bundled
  in this repository (identical to the served one, checked). The plugins it lists still download from GitHub
  releases of github.com/MacPass/AutotypeURL and MacPassHTTP, which the fork has no copies of.
- scripts/update_plugin_repository.sh, which refreshed the bundled list from macpass.app, now only says to edit
  MacPass/Resources/plugins.json here.
- The texts that named macpass.app now name the fork: the permission alert (Localizable.strings, 10 languages) says
  the list is at https://github.com/stepankandrushin/MacPass, and the Plugins settings note (PluginPreferences xib
  and 10 .strings) says the connection goes to GitHub.

Checked on a1 with the Debug build: the About box shows the plain credit; Settings → Plugins shows "a remote
connection is established to GitHub". With AllowRemoteFetchOfPluginRepository switched on for the test and the
built app's bundled plugins.json emptied, Browse Available Plugins still listed AutotypeURL and MacPassHTTP, so the
list came from the new URL. Afterwards the bundled file was put back and the setting back to off, as it was.

Still pointing at macpass.app: nothing. The README's quoted upstream notice names it as plain text now, not a link; the GitHub
repository's About website is still http://macpass.app/ (a repo setting, left for the owner to decide).
