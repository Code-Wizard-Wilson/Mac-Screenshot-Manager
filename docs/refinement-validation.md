# macOS interface refinement

The library, settings, menu panel and annotation editor share System / Light / Dark appearance. Select it in Settings → General → Appearance. Warm neutral surfaces, muted taupe accents and subdued controls reduce glare in both themes. Native glass panels respect Reduce Transparency; transitions respect Reduce Motion. Window closing keeps the app running, and the app remains available in the Dock and Cmd-Tab independently of the menu bar item.

Save and Copy have full rectangular hit areas, hover/press feedback, stable widths while exporting and contrasting foregrounds in both themes. Export failures appear in the editor. Keyboard monitoring is scoped to each editor session and leaves text input alone. Cancelling the editor cancels pending export work.

Other fixes include source-resolution crop rendering on Retina displays, duplicate shortcut rejection, Escape to cancel shortcut recording, stale library-refresh protection, thumbnail invalidation after edits and copy feedback in the library.

## Verification

Run `bash scripts/test-regressions.sh` with Swift 6 and the macOS SDK. This compiles the actual application sources with a separate test entry point and verifies window lifecycle policy, appearance modes, conflicting shortcuts, isolated clipboard PNG writes, unique saved files, latest-refresh selection, 1× and 2× crop resolution and cancellation without clipboard writes. Fixtures use a temporary folder and an isolated pasteboard.

Set `SNAPSHOT_DIR=/private/tmp/screenshot-manager-previews` to additionally render the library, settings and editor offscreen in both themes. These images validate layout, not live desktop vibrancy or pointer interactions.

Run `bash scripts/build-local-app.sh` to build a complete optimized app with Command Line Tools. It compiles the executable, generates the icon from repository assets, includes current device resources and validates the code signature. It uses the local development identity when available and ad-hoc signing otherwise. The printed output path can be passed to `bash scripts/install-local-app.sh '/path/to/Screenshot Manager.app'` after quitting the running app. Installation backs up the previous app, replaces `/Applications/Screenshot Manager.app` and registers it with LaunchServices. The scripts do not require an existing installation as an asset source and never touch the screenshot library.

On this machine, the optimized Apple Silicon executable was built using Swift 6.1.2 with a macOS 14 deployment target. Full Xcode is not installed. Existing CoreGraphics capture fallbacks produce two deprecation warnings; they were not migrated in this change.

Live end-to-end mouse/capture testing remains outstanding: Computer Use access to Screenshot Manager was denied. In particular, manually check edge clicks on Save/Copy, an inactive editor's first click, capture after closing the library, theme changes with an editor open, and multiple displays. Automated checks do not establish that every application bug is fixed.
