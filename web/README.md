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
- Opens the one recognizable link in a result, including a link inside ordinary
  text, and launches saved AI prompts in ChatGPT.
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

Add a `Search` Sheet tab with `Service`, `URL Template`, and optional `Alias`
headers. Every complete HTTP(S) row containing `{query}` becomes a searchable
service. Open one by clicking or tapping it, or select it and press Right Arrow.
Enter a query and submit to open the encoded URL; Left Arrow returns to the
results. The shorter `URL` header is accepted for existing Sheets. The layout
is recognized by its headers rather than its tab name. Separate multiple
aliases with commas, semicolons, vertical bars, or line breaks.

## Hosting

Everything in this folder is static and can be hosted with Cloudflare Pages,
GitHub Pages, Netlify, or another HTTPS static host. The current deployment is
<https://trigger-search.pages.dev/>. Do not configure a private Sheet: the web
version intentionally uses public, no-sign-in endpoints.
