"use strict";

const { app, BrowserWindow, clipboard, globalShortcut, ipcMain, Menu, nativeImage, shell, systemPreferences, Tray } = require("electron");
const { execFile } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const { promisify } = require("node:util");

const execFileAsync = promisify(execFile);
const shortcut = "CommandOrControl+Shift+Space";
const sheetIdPattern = /^[A-Za-z0-9_-]{20,}$/;
let launcherWindow;
let tray;
let quitting = false;
let previousBundleId = "";

function settingsPath() {
  return path.join(app.getPath("userData"), "settings.json");
}

function readSettings() {
  try { return JSON.parse(fs.readFileSync(settingsPath(), "utf8")); }
  catch { return {}; }
}

function writeSettings(settings) {
  fs.mkdirSync(path.dirname(settingsPath()), { recursive: true });
  fs.writeFileSync(settingsPath(), JSON.stringify(settings, null, 2));
}

function parseSheetId(value) {
  const text = String(value || "").trim();
  const match = text.match(/\/spreadsheets\/d\/([A-Za-z0-9_-]+)/);
  const candidate = match ? match[1] : text;
  return sheetIdPattern.test(candidate) ? candidate : "";
}

function decodeJsString(value) {
  return String(value || "")
    .replace(/\\x([0-9a-f]{2})/gi, (_, hex) => String.fromCharCode(Number.parseInt(hex, 16)))
    .replace(/\\"/g, '"')
    .replace(/\\\\/g, "\\");
}

function discoverSheets(html) {
  const sheets = [];
  const seen = new Set();
  const pattern = /items\.push\(\{name:\s*"(.*?)"[\s\S]*?gid:\s*"(-?\d+)"/g;
  for (const match of String(html).matchAll(pattern)) {
    const name = decodeJsString(match[1]);
    if (name && !seen.has(name)) {
      seen.add(name);
      sheets.push({ name, gid: match[2] });
    }
  }
  return sheets;
}

async function fetchText(url) {
  const response = await fetch(url, {
    headers: { "Cache-Control": "no-cache", "User-Agent": "TriggerSearchDesktop" },
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw new Error(`Google Sheets returned HTTP ${response.status}`);
  return response.text();
}

async function fetchWorkbook(sheetId, sourceName = "") {
  if (!sheetIdPattern.test(sheetId)) throw new Error("Invalid Google Sheet ID.");
  const base = `https://docs.google.com/spreadsheets/d/${encodeURIComponent(sheetId)}`;
  const cacheBust = Date.now();
  const html = await fetchText(`${base}/htmlview?cacheBust=${cacheBust}`);
  const discovered = discoverSheets(html);
  if (!discovered.length) throw new Error("No published Sheet tabs were found.");
  return Promise.all(discovered.map(async sheet => {
    const csv = await fetchText(`${base}/gviz/tq?tqx=out:csv&sheet=${encodeURIComponent(sheet.name)}&cacheBust=${cacheBust}`);
    return {
      ...sheet,
      sheetId,
      category: sourceName ? `${sourceName} · ${sheet.name}` : sheet.name,
      csv,
    };
  }));
}

async function runAppleScript(lines, timeout = 3000) {
  return execFileAsync("/usr/bin/osascript", lines.flatMap(line => ["-e", line]), { timeout });
}

async function frontmostBundle() {
  if (process.platform !== "darwin") return "";
  try {
    const result = await runAppleScript([
      'tell application "System Events"',
      "set frontProcess to first application process whose frontmost is true",
      "return bundle identifier of frontProcess",
      "end tell",
    ], 900);
    const value = result.stdout.trim();
    return /^[A-Za-z0-9.-]+$/.test(value) ? value : "";
  } catch { return ""; }
}

async function showLauncher() {
  if (!launcherWindow) return;
  const bundle = await frontmostBundle();
  if (bundle && bundle !== "com.github.Electron") previousBundleId = bundle;
  launcherWindow.show();
  launcherWindow.focus();
  launcherWindow.webContents.send("launcher:shown");
}

function hideLauncher() {
  launcherWindow?.hide();
  if (process.platform === "darwin") app.hide();
}

function expandPasteText(value, priorClipboard) {
  let text = String(value || "").replace(/\{clipboard\}/gi, priorClipboard || "");
  const marker = text.toLowerCase().indexOf("{cursor}");
  let cursorLeft = 0;
  if (marker >= 0) {
    text = text.slice(0, marker) + text.slice(marker + 8);
    cursorLeft = text.length - marker;
  }
  return { text, cursorLeft };
}

async function pasteIntoPreviousApp(value) {
  const priorClipboard = clipboard.readText();
  const expanded = expandPasteText(value, priorClipboard);
  clipboard.writeText(expanded.text);
  hideLauncher();

  if (process.platform !== "darwin") return { ok: false, copied: true, error: "Automatic paste is implemented for macOS in this experiment." };
  if (!systemPreferences.isTrustedAccessibilityClient(false)) {
    systemPreferences.isTrustedAccessibilityClient(true);
  }

  const activation = previousBundleId
    ? `try\ntell application id "${previousBundleId}" to activate\nend try`
    : "";
  const moveCursor = expanded.cursorLeft > 0
    ? `repeat ${expanded.cursorLeft} times\nkey code 123\nend repeat`
    : "";
  try {
    await runAppleScript([
      activation,
      "delay 0.14",
      'tell application "System Events"',
      'keystroke "v" using command down',
      moveCursor,
      "end tell",
    ].filter(Boolean));
    setTimeout(() => {
      if (clipboard.readText() === expanded.text) clipboard.writeText(priorClipboard);
    }, 800);
    return { ok: true };
  } catch (error) {
    launcherWindow?.show();
    launcherWindow?.focus();
    return { ok: false, copied: true, error: "Copied, but macOS blocked automatic paste. Allow Trigger Search in Accessibility settings." };
  }
}

function createWindow() {
  launcherWindow = new BrowserWindow({
    width: 760,
    height: 560,
    minWidth: 620,
    minHeight: 420,
    show: false,
    frame: false,
    transparent: false,
    resizable: true,
    alwaysOnTop: true,
    skipTaskbar: true,
    backgroundColor: "#f5f5f3",
    vibrancy: process.platform === "darwin" ? "popover" : undefined,
    visualEffectState: "active",
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  launcherWindow.loadFile(path.join(__dirname, "index.html"));
  launcherWindow.on("close", event => {
    if (!quitting) { event.preventDefault(); hideLauncher(); }
  });
}

function createTray() {
  const iconPath = app.isPackaged
    ? path.join(process.resourcesPath, "trigger-search-menuTemplate.png")
    : path.join(__dirname, "..", "mac", "trigger-search-menuTemplate.png");
  const icon = nativeImage.createFromPath(iconPath);
  icon.setTemplateImage(true);
  tray = new Tray(icon.resize({ width: 18, height: 18 }));
  tray.setToolTip("Trigger Search Experimental");
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: "Open Trigger Search", click: showLauncher },
    { label: `Shortcut: ${shortcut.replace("CommandOrControl", "⌘")}`, enabled: false },
    { type: "separator" },
    { label: "Quit", click: () => { quitting = true; app.quit(); } },
  ]));
  tray.on("click", showLauncher);
}

function registerIpc() {
  ipcMain.handle("config:get", () => ({ ...readSettings(), shortcut }));
  ipcMain.handle("config:set-sheet", (_event, value) => {
    const sheetId = parseSheetId(value);
    if (!sheetId) throw new Error("That does not look like a Google Sheets link.");
    const settings = readSettings();
    settings.sheetId = sheetId;
    writeSettings(settings);
    return { sheetId };
  });
  ipcMain.handle("workbook:fetch", (_event, sheetId, sourceName) => fetchWorkbook(sheetId, sourceName));
  ipcMain.handle("action:paste", (_event, value) => pasteIntoPreviousApp(value));
  ipcMain.handle("action:copy", (_event, value) => { clipboard.writeText(String(value || "")); return true; });
  ipcMain.handle("action:open", (_event, value) => {
    const url = String(value || "");
    if (!/^https?:\/\//i.test(url)) throw new Error("Only HTTP links can be opened.");
    shell.openExternal(url);
    hideLauncher();
    return true;
  });
  ipcMain.on("launcher:hide", hideLauncher);
  ipcMain.on("launcher:show", showLauncher);
}

if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on("second-instance", showLauncher);
  app.whenReady().then(() => {
    app.setName("Trigger Search Experimental");
    if (process.platform === "darwin") app.dock.hide();
    registerIpc();
    createWindow();
    createTray();
    globalShortcut.register(shortcut, showLauncher);
    showLauncher();
  });
  app.on("will-quit", () => globalShortcut.unregisterAll());
}
