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
- Supports Up/Down to navigate, Right Arrow to open nested details, Left Arrow
  to return, Enter to preview, Command/Control 1–9 to copy, `/` to focus search,
  and Command/Control-G to Google the typed phrase on desktop.
- Falls back to the last successful local cache when the Sheet is unavailable.

The browser cannot paste into another application. The web workflow is copy,
switch applications, and paste.

## Run locally

Serve the repository root with any static web server and open `/web/`. Service
workers and clipboard access require localhost or HTTPS; opening `index.html`
directly is not sufficient.

The first visit asks for a complete public Google Sheets link. Publish the
workbook using **File → Share → Publish to web** before connecting it.

## Search launchers

Add a `Search` Sheet tab. Headers are optional: columns A, B, and C mean service,
URL template, and optional alias. Recognized headers can be rearranged and are
`Service`/`Label`/`Name`, `URL Template`/`URL`/`Link`, and
`Alias`/`Nickname`. Every complete HTTP(S) row containing `{query}` becomes a
searchable service. Open one by clicking or tapping it, or select it and press Right Arrow.
Enter a query and submit to open the encoded URL; Left Arrow returns to the
results. On other tabs, recognized header pairs continue to identify this
layout for backward compatibility. Separate multiple
aliases with commas, semicolons, vertical bars, or line breaks.

## Hosting

Everything in this folder is static and can be hosted with Cloudflare Pages,
GitHub Pages, Netlify, or another HTTPS static host. The current deployment is
<https://trigger-search.pages.dev/>. Do not configure a private Sheet: the web
version intentionally uses public, no-sign-in endpoints.
