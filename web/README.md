# Trigger Search Web

A small responsive companion for the Mac and Windows launchers. It reads the
same public Google Sheet, caches the latest successful workbook locally, and
works as an installable Progressive Web App.

## What it does

- Searches every visible Sheet tab together while keeping each tab name as
  result context.
- Opens arbitrary nested detail columns.
- Opens configurable search and AI services and accepts their queries in a small
  second-step dialog.
- Opens saved text in a readable preview by default and provides a dedicated
  Phosphor copy button.
- Opens a result immediately when its complete saved value is one recognizable
  link. A single link inside ordinary text remains available through the open
  icon, while tapping the row previews the text.
- Shows recent Sheet items when the search is empty.
- Keeps the empty mobile view minimal: branding and search only. The search
  field is focused on load, and tapping unused page space focuses it again.
  Recent Sheet items remain available on desktop but are hidden on mobile.
- Shows a clear button while Search contains text. When a phrase has no Sheet
  result, submitting Search opens that phrase in Google.
- Includes Sheet tabs as folder-like ordinary search results. Enter or Right
  Arrow browses a tab as a vertical list; Command/Control-E opens the tab in
  Google Sheets, and Left Arrow returns one level. Tabs, rows, columns, and
  equally relevant search matches retain their Google Sheets order.
- Supports Up/Down to navigate, Right Arrow to open nested details, Left Arrow
  to return, Enter to preview, Command/Control 1–9 to copy, and
  Command/Control-G to Google the typed phrase on desktop.
- Falls back to the last successful local cache when the Sheet is unavailable.
- Pins the first usable row from the tab named by `Inbox Sheet` (default
  `Inbox`) on the blank home screen. Desktop follows it with Recents; mobile
  shows the pin without Recents. Returning to the visible web app refreshes the
  Sheet so an iPhone Shortcut capture is immediately available.
- Shows contextual actions from each result's `•••` button. On desktop,
  Command-K or Control-K opens the same menu for the selected result; its
  displayed single-key shortcuts work while the menu is open.

The browser cannot paste into another application. The web workflow is copy,
switch applications, and paste.

The primary workbook may also list public shared collections in its
`Settings & Help` tab using `Included Sheet Name`, `Google Sheet URL`, and
optional `Enabled` columns. Included results retain source context and their
edit links point to the correct workbook. Blank Enabled cells count as enabled;
FALSE, No, 0, and Off disable a row.
Add a tab name to the `Hidden Tab` column on the same settings tab to omit it
without renaming or deleting it. A plain name hides matching tabs everywhere;
use `Included Sheet Name · Tab Name` to target only one included collection.

## Run locally

Serve the repository root with any static web server and open `/web/`. Service
workers and clipboard access require localhost or HTTPS; opening `index.html`
directly is not sufficient.

The first visit asks for a complete public Google Sheets link. Publish the
workbook using **File → Share → Publish to web** before connecting it. Once
connected, the address contains `?sheet=YOUR_SHEET_ID`; copying that address or
using **Settings → Share link** gives someone else the same Sheet-backed web
launcher. Opening a shared address also remembers that Sheet in the recipient's
browser for later visits.

## Search launchers

Add a tab named exactly `Search` with `Name`, `Alias`, and `Content` headers.
Content holds the URL template; keep all three headers even when Alias is blank.
Every valid row containing `$` becomes a searchable service. Trigger Search
replaces `$` with the URL-encoded query. HTTP(S) protocols are accepted but optional; recognizable bare domains
automatically use HTTPS. Open one by clicking or tapping it, or select it and
press Right Arrow.
Enter a query and submit to open the encoded URL; Left Arrow returns to the
results. Other tabs use the ordinary snippet rules. Separate multiple
aliases with commas, semicolons, vertical bars, or line breaks.

Ordinary headerless tabs support one column as Content, two as Name/Content,
or three as Name/Alias/Content. Four or more columns and all nested fields
require a header row.

## Hosting

Everything in this folder is static and can be hosted with Cloudflare Pages,
GitHub Pages, Netlify, or another HTTPS static host. The current deployment is
<https://trigger-search.pages.dev/>. Do not configure a private Sheet: the web
version intentionally uses public, no-sign-in endpoints.

## Brand assets

The website header uses `menu-icon.svg`, the same plain lightning-bolt mark as
the Mac menu bar. `icon.svg` and `icon-180.png` retain the square treatment for
the browser favicon and installed home-screen/PWA icon.
