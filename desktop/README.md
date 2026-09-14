# Trigger Search desktop experiment

This is a deliberately small Electron proof of concept for turning Trigger
Search into a Mac app while keeping a future Windows path open.

## Try it on Mac

```sh
cd desktop
npm install
npm start
```

On first launch, connect the same published Google Sheet used by Trigger
Search. Press **Command-Shift-Space** from another application to open the
launcher. Return or clicking a result pastes ordinary content, opens a complete
URL, enters a `$` search template, or browses a Sheet tab. Escape closes the
launcher. Command-R refreshes the Sheet.

The first automatic paste prompts for macOS Accessibility permission. If it is
not yet allowed, Trigger Search leaves the selected value on the clipboard so
it is not lost.

Build an unpacked `.app` and a downloadable `.zip` with:

```sh
npm run build:mac
```

The builds appear under `desktop/dist/`.

This experiment intentionally omits AI actions and the full actions/preview
menus. It already covers the product loop that matters for deciding whether a
desktop app feels right: launch, search, browse, paste/open, refresh, and cache.
