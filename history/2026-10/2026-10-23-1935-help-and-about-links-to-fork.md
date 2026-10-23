# Help and About links point at the fork (not released)

The owner on 2026-10-23: Help → MacPass Help still opened the upstream repository; links to the old repositories
should go to ours. Inside the app only two places linked upstream:

- `MPHelpURL` in MacPass-Info.plist (Help → MacPass Help) now is https://github.com/stepankandrushin/MacPass.
- Credits.rtf (the About box): "Project Website" is github.com/stepankandrushin/MacPass, followed by "A fork of
  MacPass by Michael Starke and the MacPass contributors", MacPass linking to github.com/MacPass/MacPass.

Left as they are: the copyright lines, the credits of translators and libraries, the plugin repository
(macpass.app/data/plugins.json and its plugins under github.com/MacPass, which the fork has no copy of), the README's
upstream links (they credit upstream on purpose), and docs/index.md (not served: the fork's Pages come from gh-pages).

Checked on a1 with the Debug build: Help → MacPass Help opened github.com/stepankandrushin/MacPass in Chrome, and the
About box shows the new lines. The repository's About on GitHub still lists macpass.app as its website; that is a
GitHub setting, not in the code, and was left for the owner.
