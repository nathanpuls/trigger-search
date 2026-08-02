"use strict";

const state = {
  sheetId: localStorage.getItem("triggerSearch.sheetId") || "",
  items: [], categories: [], activeCategory: "All", query: "", selectedIndex: 0,
};

const ui = {
  search: document.querySelector("#search"), tabs: document.querySelector("#tabs"),
  status: document.querySelector("#status"), results: document.querySelector("#results"),
  template: document.querySelector("#result-template"), toast: document.querySelector("#toast"),
  settings: document.querySelector("#settings-dialog"), sheetUrl: document.querySelector("#sheet-url"),
  details: document.querySelector("#details-dialog"), detailsTitle: document.querySelector("#details-title"),
  detailsList: document.querySelector("#details-list"),
};

const trim = value => String(value ?? "").trim();
const normalize = value => trim(value).toLowerCase();
const tabKey = value => normalize(value).replace(/[\s_&-]+/g, "");
const skippedTabs = new Set(["settings", "settingshelp", "readme", "blanktemplate", "autohotkey"]);

function parseSheetId(value) {
  const match = trim(value).match(/\/spreadsheets\/d\/([A-Za-z0-9_-]+)/);
  if (match) return match[1];
  return /^[A-Za-z0-9_-]{20,}$/.test(trim(value)) ? trim(value) : "";
}

function decodeJsString(value) {
  try { return JSON.parse(`"${value.replace(/\"/g, '\\"')}"`); }
  catch { return value.replace(/\\x([0-9a-f]{2})/gi, (_, hex) => String.fromCharCode(parseInt(hex, 16))).replace(/\\"/g, '"').replace(/\\\\/g, "\\"); }
}

function discoverSheets(html) {
  const found = [], seen = new Set();
  const pattern = /items\.push\(\{name:\s*"(.*?)"[\s\S]*?gid:\s*"(-?\d+)"/g;
  for (const match of html.matchAll(pattern)) {
    const name = decodeJsString(match[1]);
    if (!seen.has(name)) { seen.add(name); found.push({ name, gid: match[2] }); }
  }
  return found;
}

function parseCsv(text) {
  const rows = []; let row = [], field = "", quoted = false;
  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    if (quoted) {
      if (char === '"' && text[index + 1] === '"') { field += '"'; index += 1; }
      else if (char === '"') quoted = false;
      else field += char;
    } else if (char === '"') quoted = true;
    else if (char === ",") { row.push(field); field = ""; }
    else if (char === "\n") { row.push(field.replace(/\r$/, "")); rows.push(row); row = []; field = ""; }
    else field += char;
  }
  if (field !== "" || row.length) { row.push(field.replace(/\r$/, "")); rows.push(row); }
  return rows;
}

function parseTab(csv, category, gid) {
  const rows = parseCsv(csv).filter(row => row.some(cell => trim(cell) !== ""));
  if (!rows.length) return [];
  const headers = rows[0].map(cell => normalize(cell.replace(/^\uFEFF/, "")));
  const labelIndex = headers.indexOf("label"), contentIndex = headers.indexOf("content"), aliasIndex = headers.indexOf("alias");
  const hasHeaders = labelIndex >= 0 || contentIndex >= 0;
  const firstDataRow = hasHeaders ? 1 : 0;
  const aiPrompts = new Map();

  if (hasHeaders) rows.slice(1).forEach(row => {
    const label = labelIndex >= 0 ? trim(row[labelIndex]) : "";
    if (tabKey(label) === "aiprompt") row.forEach((value, index) => { if (trim(value)) aiPrompts.set(index, value); });
  });

  const items = [];
  rows.slice(firstDataRow).forEach((row, offset) => {
    const sheetRow = offset + firstDataRow + 1;
    const rawLabel = hasHeaders ? (labelIndex >= 0 ? trim(row[labelIndex]) : "") : trim(row[0]);
    const rawContent = hasHeaders ? (contentIndex >= 0 ? row[contentIndex] || "" : "") : (row.length > 1 ? row[1] || "" : row[0] || "");
    if (tabKey(rawLabel) === "aiprompt") return;
    const label = rawLabel || trim(rawContent);
    if (!label) return;
    const aliases = hasHeaders && aliasIndex >= 0 ? trim(row[aliasIndex]).split(/[,;|\n]/).map(trim).filter(Boolean) : [];
    const details = [];
    if (hasHeaders) headers.forEach((header, index) => {
      if (!header || index === labelIndex || index === contentIndex || index === aliasIndex) return;
      const content = row[index] || "", aiPrompt = aiPrompts.get(index) || "";
      if (!trim(content) && !trim(aiPrompt)) return;
      details.push({ label: trim(rows[0][index]), content, aiPrompt });
    });
    items.push({
      key: `${category}:${sheetRow}`, label, content: trim(rawContent) ? rawContent : label,
      aliases, category, gid, row: sheetRow, details,
      aiPrompt: contentIndex >= 0 ? aiPrompts.get(contentIndex) || "" : "",
    });
  });
  return items;
}

function cacheKey() { return `triggerSearch.cache.${state.sheetId}`; }
function recentKey() { return `triggerSearch.recents.${state.sheetId}`; }

async function loadWorkbook() {
  if (!state.sheetId) { openSettings(true); return; }
  ui.status.textContent = "Refreshing…";
  try {
    const base = `https://docs.google.com/spreadsheets/d/${encodeURIComponent(state.sheetId)}`;
    const html = await fetch(`${base}/htmlview?cacheBust=${Date.now()}`).then(response => {
      if (!response.ok) throw new Error(`Google returned ${response.status}`);
      return response.text();
    });
    const sheets = discoverSheets(html).filter(sheet => !skippedTabs.has(tabKey(sheet.name)));
    if (!sheets.length) throw new Error("No visible autocomplete tabs were found");
    const data = await Promise.all(sheets.map(async sheet => {
      const url = `${base}/gviz/tq?tqx=out:csv&sheet=${encodeURIComponent(sheet.name)}&cacheBust=${Date.now()}`;
      const csv = await fetch(url).then(response => { if (!response.ok) throw new Error(`${sheet.name}: ${response.status}`); return response.text(); });
      return { ...sheet, csv };
    }));
    state.items = data.flatMap(sheet => parseTab(sheet.csv, sheet.name, sheet.gid));
    state.categories = data.map(sheet => sheet.name);
    localStorage.setItem(cacheKey(), JSON.stringify({ items: state.items, categories: state.categories, savedAt: Date.now() }));
    ui.status.textContent = `${state.items.length} items`;
  } catch (error) {
    const cached = JSON.parse(localStorage.getItem(cacheKey()) || "null");
    if (!cached) { ui.status.textContent = error.message; openSettings(false); return; }
    state.items = cached.items || []; state.categories = cached.categories || [];
    ui.status.textContent = `Offline copy · ${state.items.length} items`;
  }
  if (state.activeCategory !== "All" && !state.categories.includes(state.activeCategory)) state.activeCategory = "All";
  renderTabs(); renderResults();
}

function recentItems() {
  const keys = JSON.parse(localStorage.getItem(recentKey()) || "[]");
  return keys.map(key => state.items.find(item => item.key === key)).filter(Boolean).slice(0, 9);
}

function recordRecent(item) {
  const keys = JSON.parse(localStorage.getItem(recentKey()) || "[]").filter(key => key !== item.key);
  localStorage.setItem(recentKey(), JSON.stringify([item.key, ...keys].slice(0, 9)));
}

function rankedItems() {
  const query = normalize(state.query);
  const source = state.activeCategory === "All" ? state.items : state.items.filter(item => item.category === state.activeCategory);
  if (!query) return recentItems().filter(item => state.activeCategory === "All" || item.category === state.activeCategory);
  return source.map(item => {
    const label = normalize(item.label), aliases = item.aliases.map(normalize), content = normalize(item.content);
    let rank = 99;
    if (aliases.includes(query)) rank = 0;
    else if (label === query) rank = 1;
    else if (aliases.some(alias => alias.startsWith(query))) rank = 2;
    else if (label.startsWith(query)) rank = 3;
    else if (aliases.some(alias => alias.includes(query))) rank = 4;
    else if (label.includes(query)) rank = 5;
    else if (content.includes(query)) rank = 6;
    else if (item.details.some(detail => normalize(`${detail.label} ${detail.content}`).includes(query))) rank = 7;
    return { item, rank };
  }).filter(match => match.rank < 99).sort((a, b) => a.rank - b.rank || a.item.label.localeCompare(b.item.label)).map(match => match.item);
}

function renderTabs() {
  ui.tabs.replaceChildren();
  ["All", ...state.categories].forEach(category => {
    const button = document.createElement("button");
    button.type = "button"; button.className = "tab"; button.textContent = category;
    button.setAttribute("aria-selected", String(category === state.activeCategory));
    button.addEventListener("click", () => { state.activeCategory = category; state.selectedIndex = 0; renderTabs(); renderResults(); });
    ui.tabs.append(button);
  });
}

function standaloneUrl(value) {
  const text = trim(value);
  return /^(https?:\/\/|www\.)[^\s]+$/i.test(text) ? (text.startsWith("www.") ? `https://${text}` : text) : "";
}

function makeButton(label, title, handler) {
  const button = document.createElement("button");
  button.type = "button"; button.className = "action-button"; button.textContent = label; button.title = title;
  button.addEventListener("click", event => { event.stopPropagation(); handler(); });
  return button;
}

function openExternal(url) {
  const opened = window.open(url, "_blank", "noopener,noreferrer");
  if (!opened) location.href = url;
}

function renderResults() {
  const items = rankedItems();
  state.selectedIndex = Math.min(state.selectedIndex, Math.max(0, items.length - 1));
  ui.results.replaceChildren();
  if (!items.length) {
    const empty = document.createElement("div"); empty.className = "empty-state";
    empty.textContent = state.query ? "No Sheet matches. Press ⌘G or Ctrl+G to search Google." : "Your recently used items will appear here.";
    ui.results.append(empty); return;
  }
  items.slice(0, 30).forEach((item, index) => {
    const node = ui.template.content.firstElementChild.cloneNode(true);
    node.dataset.key = item.key; node.dataset.selected = String(index === state.selectedIndex);
    const title = node.querySelector(".result-title"); title.textContent = item.label;
    if (item.details.length) { const arrow = document.createElement("span"); arrow.className = "arrow"; arrow.textContent = "→"; title.append(arrow); }
    node.querySelector(".result-meta").textContent = `${item.category}${trim(item.content) !== item.label ? ` · ${item.content.replace(/\s+/g, " ")}` : ""}`;
    const actions = node.querySelector(".result-actions");
    actions.append(makeButton("Copy", "Copy", () => copyItem(item)));
    const url = standaloneUrl(item.content); if (url) actions.append(makeButton("Open", "Open link", () => { recordRecent(item); openExternal(url); }));
    node.querySelector(".result-main").addEventListener("click", () => item.details.length ? openDetails(item) : copyItem(item));
    node.addEventListener("focus", () => { state.selectedIndex = index; document.querySelectorAll(".result").forEach((row, rowIndex) => row.dataset.selected = String(rowIndex === index)); });
    ui.results.append(node);
  });
}

async function copyText(text, item) {
  try { await navigator.clipboard.writeText(text); }
  catch {
    const area = document.createElement("textarea"); area.value = text; document.body.append(area); area.select(); document.execCommand("copy"); area.remove();
  }
  if (item) recordRecent(item);
  showToast("Copied"); renderResults();
}

function copyItem(item) { return copyText(item.content, item); }
function showToast(message) { ui.toast.textContent = message; ui.toast.classList.add("visible"); clearTimeout(showToast.timer); showToast.timer = setTimeout(() => ui.toast.classList.remove("visible"), 1300); }

function buildAiPrompt(template, item) {
  const replaced = template.replace(/\{(?:medication|item|label)\}/gi, item.label);
  return replaced === template ? `${template}\n\nItem: ${item.label}` : replaced;
}

function askAi(prompt, item) {
  recordRecent(item);
  openExternal(`https://chatgpt.com/?q=${encodeURIComponent(prompt)}`);
}

function openDetails(item) {
  ui.detailsTitle.textContent = item.label; ui.detailsList.replaceChildren();
  item.details.forEach(detail => {
    const block = document.createElement("section"); block.className = "detail";
    const heading = document.createElement("h3"); heading.textContent = detail.label; block.append(heading);
    const text = document.createElement("p"); text.className = "detail-text"; text.textContent = detail.content || "Ask AI"; block.append(text);
    const actions = document.createElement("div"); actions.className = "detail-actions";
    if (trim(detail.content)) actions.append(makeButton("Copy", "Copy", () => copyText(detail.content, item)));
    const url = standaloneUrl(detail.content); if (url) actions.append(makeButton("Open", "Open link", () => { recordRecent(item); openExternal(url); }));
    if (trim(detail.aiPrompt)) actions.append(makeButton("Ask AI", "Ask ChatGPT", () => askAi(buildAiPrompt(detail.aiPrompt, item), item)));
    block.append(actions); ui.detailsList.append(block);
  });
  ui.details.showModal();
}

function openSettings(firstRun) {
  ui.sheetUrl.value = state.sheetId ? `https://docs.google.com/spreadsheets/d/${state.sheetId}/edit` : "";
  document.querySelector("#disconnect-button").hidden = firstRun || !state.sheetId;
  if (!ui.settings.open) ui.settings.showModal();
}

document.querySelector("#settings-button").addEventListener("click", () => openSettings(false));
document.querySelector("#details-back").addEventListener("click", () => ui.details.close());
document.querySelectorAll("[data-close]").forEach(button => button.addEventListener("click", () => document.querySelector(`#${button.dataset.close}`).close()));
document.querySelector("#disconnect-button").addEventListener("click", () => { localStorage.removeItem("triggerSearch.sheetId"); state.sheetId = ""; state.items = []; state.categories = []; ui.settings.close(); renderTabs(); renderResults(); openSettings(true); });
document.querySelector("#settings-form").addEventListener("submit", event => {
  event.preventDefault(); const id = parseSheetId(ui.sheetUrl.value);
  if (!id) { showToast("That does not look like a Google Sheets link"); return; }
  state.sheetId = id; localStorage.setItem("triggerSearch.sheetId", id); ui.settings.close(); loadWorkbook();
});

ui.search.addEventListener("input", () => { state.query = ui.search.value; state.selectedIndex = 0; renderResults(); });
document.addEventListener("keydown", event => {
  if (ui.settings.open || ui.details.open) {
    if (event.key === "Escape" || (ui.details.open && event.key === "ArrowLeft")) {
      event.preventDefault();
      ui.settings.open ? ui.settings.close() : ui.details.close();
      if (!ui.settings.open) ui.search.focus();
    }
    return;
  }
  const items = rankedItems();
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") { event.preventDefault(); ui.search.focus(); return; }
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "g" && trim(ui.search.value)) { event.preventDefault(); openExternal(`https://www.google.com/search?q=${encodeURIComponent(trim(ui.search.value))}`); return; }
  if ((event.metaKey || event.ctrlKey) && /^[1-9]$/.test(event.key)) { const item = items[Number(event.key) - 1]; if (item) { event.preventDefault(); copyItem(item); } return; }
  if (event.key === "ArrowDown" || event.key === "ArrowUp") { event.preventDefault(); const delta = event.key === "ArrowDown" ? 1 : -1; state.selectedIndex = Math.max(0, Math.min(items.length - 1, state.selectedIndex + delta)); renderResults(); document.querySelectorAll(".result")[state.selectedIndex]?.focus(); return; }
  if (event.key === "ArrowRight") { const item = items[state.selectedIndex]; if (item?.details.length) { event.preventDefault(); openDetails(item); } return; }
  if (event.key === "Enter" && document.activeElement === ui.search) { const item = items[state.selectedIndex]; if (item) { event.preventDefault(); item.details.length ? openDetails(item) : copyItem(item); } }
  if (event.key === "Escape") { ui.search.value = ""; state.query = ""; renderResults(); }
});

if ("serviceWorker" in navigator) window.addEventListener("load", () => navigator.serviceWorker.register("service-worker.js"));
renderTabs(); renderResults(); loadWorkbook();
