"use strict";

const state = {
  sheetId: localStorage.getItem("triggerSearch.sheetId") || "",
  items: [], categories: [], categoryGids: {}, categorySheetIds: {}, activeCategory: "",
  query: "", selectedIndex: 0,
};

const ui = {
  search: document.querySelector("#search"),
  clearSearch: document.querySelector("#clear-search"),
  status: document.querySelector("#status"), results: document.querySelector("#results"),
  template: document.querySelector("#result-template"), toast: document.querySelector("#toast"),
  settings: document.querySelector("#settings-dialog"), sheetUrl: document.querySelector("#sheet-url"),
  details: document.querySelector("#details-dialog"), detailsTitle: document.querySelector("#details-title"),
  detailsList: document.querySelector("#details-list"),
  searchService: document.querySelector("#search-service-dialog"),
  searchServiceTitle: document.querySelector("#search-service-title"),
  serviceQuery: document.querySelector("#service-query"),
  actions: document.querySelector("#actions-dialog"),
  actionsTitle: document.querySelector("#actions-title"),
  actionsList: document.querySelector("#actions-list"),
  preview: document.querySelector("#preview-dialog"),
  previewTitle: document.querySelector("#preview-title"),
  previewBody: document.querySelector("#preview-body"),
  previewActions: document.querySelector("#preview-actions"),
};

const trim = value => String(value ?? "").trim();
const normalize = value => trim(value).toLowerCase();
const tabKey = value => normalize(value).replace(/[\s_&-]+/g, "");
const skippedTabs = new Set(["settings", "settingshelp", "readme", "blanktemplate", "autohotkey"]);
const mobileViewport = window.matchMedia("(max-width: 640px)");

function isMobileView() { return mobileViewport.matches; }
function isTouchDevice() {
  return navigator.maxTouchPoints > 0 || window.matchMedia("(pointer: coarse)").matches;
}

function anyDialogOpen() {
  return ui.settings.open || ui.details.open || ui.searchService.open
    || ui.actions.open || ui.preview.open;
}

function focusSearchNow() {
  if (anyDialogOpen()) return;
  try { ui.search.focus({ preventScroll: true }); }
  catch { ui.search.focus(); }
}

function focusSearchSoon() {
  requestAnimationFrame(focusSearchNow);
  setTimeout(focusSearchNow, 120);
}

function syncClearSearch() {
  if (!ui.clearSearch) return;
  ui.clearSearch.hidden = ui.search.value.length === 0;
}

function clearMainSearch() {
  ui.search.value = "";
  state.query = "";
  state.selectedIndex = 0;
  syncClearSearch();
  renderResults();
  focusSearchSoon();
}

function focusServiceQuerySoon() {
  const focus = () => {
    if (!ui.searchService.open) return;
    try { ui.serviceQuery.focus({ preventScroll: true }); }
    catch { ui.serviceQuery.focus(); }
  };
  requestAnimationFrame(focus);
  setTimeout(focus, 120);
}

function parseSheetId(value) {
  const match = trim(value).match(/\/spreadsheets\/d\/([A-Za-z0-9_-]+)/);
  if (match) return match[1];
  return /^[A-Za-z0-9_-]{20,}$/.test(trim(value)) ? trim(value) : "";
}

function sheetShareUrl(sheetId = state.sheetId) {
  const url = new URL(window.location.href);
  url.search = ""; url.hash = "";
  if (sheetId) url.searchParams.set("sheet", sheetId);
  return url.toString();
}

function syncSheetUrl(sheetId = state.sheetId) {
  history.replaceState({}, "", sheetShareUrl(sheetId));
}

const sharedSheetId = parseSheetId(new URLSearchParams(window.location.search).get("sheet") || "");
if (sharedSheetId) {
  state.sheetId = sharedSheetId;
  localStorage.setItem("triggerSearch.sheetId", sharedSheetId);
  syncSheetUrl(sharedSheetId);
} else if (state.sheetId) syncSheetUrl(state.sheetId);

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

function normalizeSearchTemplate(value) {
  const template = trim(value);
  if (!template.includes("$")) return "";
  if (/^https?:\/\/\S+$/i.test(template)) return template;
  if (/^(?:[a-z0-9-]+\.)+[a-z]{2,}\S*$/i.test(template)) return `https://${template}`;
  return "";
}

function parseTab(csv, category, gid) {
  const rows = parseCsv(csv).filter(row => row.some(cell => trim(cell) !== ""));
  if (!rows.length) return [];
  const headers = rows[0].map(cell => {
    const header = normalize(cell.replace(/^\uFEFF/, ""));
    return header;
  });
  const normalizedCategory = normalize(category);
  const isSearchTab = normalizedCategory === "search" || normalizedCategory.endsWith(" · search");
  const serviceIndex = headers.indexOf("name");
  const templateIndex = headers.indexOf("content");
  const serviceAliasIndex = headers.indexOf("alias");
  if (isSearchTab && serviceIndex >= 0 && serviceAliasIndex >= 0 && templateIndex >= 0) {
    return rows.slice(1).map((row, offset) => ({ row, offset })).filter(({ row }) => {
      const service = trim(row[serviceIndex]), template = normalizeSearchTemplate(row[templateIndex]);
      return service && template;
    }).map(({ row, offset }) => ({
      key: `${category}:${offset + 2}`, type: "search-service",
      label: trim(row[serviceIndex]), content: "",
      aliases: serviceAliasIndex >= 0 ? trim(row[serviceAliasIndex]).split(/[,;|\n]/).map(trim).filter(Boolean) : [],
      category, gid,
      row: offset + 2, details: [], aiPrompt: "",
      urlTemplate: normalizeSearchTemplate(row[templateIndex]),
    }));
  }
  if (isSearchTab) return [];

  let nameIndex = headers.indexOf("name");
  let contentIndex = headers.indexOf("content");
  let aliasIndex = headers.indexOf("alias");
  const hasHeaders = nameIndex >= 0 || contentIndex >= 0 || aliasIndex >= 0;
  if (hasHeaders && contentIndex < 0) return [];
  if (!hasHeaders) {
    const rightmost = rows.reduce((maximum, row) => Math.max(maximum,
      row.reduce((last, value, index) => trim(value) ? index + 1 : last, 0)), 0);
    if (rightmost > 3) return [];
    if (rightmost === 1) { nameIndex = -1; aliasIndex = -1; contentIndex = 0; }
    if (rightmost === 2) { nameIndex = 0; aliasIndex = -1; contentIndex = 1; }
    if (rightmost === 3) { nameIndex = 0; aliasIndex = 1; contentIndex = 2; }
  }
  const firstDataRow = hasHeaders ? 1 : 0;
  const displayHeaders = rows[0];
  const aiPrompts = new Map();

  if (hasHeaders) rows.slice(firstDataRow).forEach(row => {
    const name = nameIndex >= 0 ? trim(row[nameIndex]) : "";
    if (tabKey(name) === "aiprompt") row.forEach((value, index) => { if (trim(value)) aiPrompts.set(index, value); });
  });

  const items = [];
  rows.slice(firstDataRow).forEach((row, offset) => {
    const sheetRow = offset + firstDataRow + 1;
    const rawName = nameIndex >= 0 ? trim(row[nameIndex]) : "";
    const rawContent = contentIndex >= 0 ? row[contentIndex] || "" : "";
    if (tabKey(rawName) === "aiprompt") return;
    const contentName = trim(rawContent).replace(/\s+/g, " ");
    const label = rawName || (contentName.length > 60 ? `${contentName.slice(0, 57)}...` : contentName);
    if (!label) return;
    const aliases = aliasIndex >= 0 ? trim(row[aliasIndex]).split(/[,;|\n]/).map(trim).filter(Boolean) : [];
    const details = [];
    if (hasHeaders) headers.forEach((header, index) => {
      if (!header || index === nameIndex || index === contentIndex || index === aliasIndex) return;
      const content = row[index] || "", aiPrompt = aiPrompts.get(index) || "";
      if (!trim(content) && !trim(aiPrompt)) return;
      details.push({ label: trim(displayHeaders[index]), content, aiPrompt });
    });
    const aiPrompt = contentIndex >= 0 ? aiPrompts.get(contentIndex) || "" : "";
    if (!trim(rawContent) && !details.length && !trim(aiPrompt)) return;
    items.push({
      key: `${category}:${sheetRow}`, label, content: rawContent,
      aliases, category, gid, row: sheetRow, details,
      aiPrompt,
    });
  });
  return items;
}

function parseIncludedSheets(csv, primarySheetId) {
  const rows = parseCsv(csv).filter(row => row.some(cell => trim(cell) !== ""));
  if (!rows.length) return [];
  const headers = rows[0].map(cell => normalize(cell.replace(/^\uFEFF/, "")));
  const first = names => names.map(name => headers.indexOf(name)).find(index => index >= 0) ?? -1;
  const nameIndex = first(["included sheet name", "source name"]);
  const urlIndex = first(["google sheet url", "sheet url"]);
  const enabledIndex = first(["enabled", "include"]);
  if (nameIndex < 0 || urlIndex < 0) return [];
  const seen = new Set([primarySheetId]);
  return rows.slice(1).map(row => {
    const name = trim(row[nameIndex]);
    const sheetId = parseSheetId(row[urlIndex]);
    const enabled = enabledIndex < 0 || !/^(?:false|no|0|off)$/i.test(trim(row[enabledIndex]));
    if (!name || !sheetId || !enabled || seen.has(sheetId)) return null;
    seen.add(sheetId);
    return { name, sheetId };
  }).filter(Boolean);
}

function parseHiddenTabs(csv) {
  const rows = parseCsv(csv).filter(row => row.some(cell => trim(cell) !== ""));
  if (!rows.length) return new Set();
  const headers = rows[0].map(cell => normalize(cell.replace(/^\uFEFF/, "")));
  const hiddenIndex = ["hidden tab", "excluded tab", "hide tab"]
    .map(name => headers.indexOf(name)).find(index => index >= 0) ?? -1;
  if (hiddenIndex < 0) return new Set();
  return new Set(rows.slice(1).map(row => tabKey(row[hiddenIndex])).filter(Boolean));
}

function cacheKey() { return `triggerSearch.cache.${state.sheetId}`; }
function recentKey() { return `triggerSearch.recents.${state.sheetId}`; }

async function loadWorkbook() {
  if (!state.sheetId) { openSettings(true); return; }
  ui.status.textContent = "Refreshing…";
  try {
    const fetchWorkbook = async (sheetId, sourceName = "") => {
      const base = `https://docs.google.com/spreadsheets/d/${encodeURIComponent(sheetId)}`;
      const html = await fetch(`${base}/htmlview?cacheBust=${Date.now()}`).then(response => {
        if (!response.ok) throw new Error(`Google returned ${response.status}`);
        return response.text();
      });
      const sheets = discoverSheets(html);
      const data = await Promise.all(sheets.map(async sheet => {
        const url = `${base}/gviz/tq?tqx=out:csv&sheet=${encodeURIComponent(sheet.name)}&cacheBust=${Date.now()}`;
        const csv = await fetch(url).then(response => { if (!response.ok) throw new Error(`${sheet.name}: ${response.status}`); return response.text(); });
        const category = sourceName ? `${sourceName} · ${sheet.name}` : sheet.name;
        return { ...sheet, category, sheetId, csv };
      }));
      return data;
    };

    const primaryData = await fetchWorkbook(state.sheetId);
    const settings = primaryData.find(sheet => tabKey(sheet.name) === "settingshelp" || tabKey(sheet.name) === "settings");
    const included = settings ? parseIncludedSheets(settings.csv, state.sheetId) : [];
    const hiddenTabs = settings ? parseHiddenTabs(settings.csv) : new Set();
    const includedData = (await Promise.all(included.map(async source => {
      try { return await fetchWorkbook(source.sheetId, source.name); }
      catch (error) { console.warn(`Included Sheet ${source.name} was skipped:`, error); return []; }
    }))).flat();
    const data = [...primaryData, ...includedData].filter(sheet =>
      !skippedTabs.has(tabKey(sheet.name))
      && !hiddenTabs.has(tabKey(sheet.name))
      && !hiddenTabs.has(tabKey(sheet.category)));
    if (!data.length) throw new Error("No visible autocomplete tabs were found");
    state.items = data.flatMap(sheet => parseTab(sheet.csv, sheet.category, sheet.gid));
    state.categories = data.map(sheet => sheet.category);
    state.categoryGids = Object.fromEntries(data.map(sheet => [sheet.category, sheet.gid]));
    state.categorySheetIds = Object.fromEntries(data.map(sheet => [sheet.category, sheet.sheetId]));
    localStorage.setItem(cacheKey(), JSON.stringify({ items: state.items, categories: state.categories, categoryGids: state.categoryGids, categorySheetIds: state.categorySheetIds, savedAt: Date.now() }));
    ui.status.textContent = "";
  } catch (error) {
    const cached = JSON.parse(localStorage.getItem(cacheKey()) || "null");
    if (!cached) { ui.status.textContent = error.message; openSettings(false); return; }
    state.items = cached.items || []; state.categories = cached.categories || [];
    state.categoryGids = cached.categoryGids || {};
    state.categorySheetIds = cached.categorySheetIds || {};
    ui.status.textContent = `Offline copy · ${state.items.length} items`;
  }
  renderResults();
}

function recentItems() {
  const keys = JSON.parse(localStorage.getItem(recentKey()) || "[]");
  return keys.map(key => state.items.find(item => item.key === key)).filter(Boolean).slice(0, 9);
}

function recordRecent(item) {
  const keys = JSON.parse(localStorage.getItem(recentKey()) || "[]").filter(key => key !== item.key);
  localStorage.setItem(recentKey(), JSON.stringify([item.key, ...keys].slice(0, 9)));
}

function categorySheetUrl(category, row = "") {
  const gid = state.categoryGids[category] ?? state.items.find(item => item.category === category)?.gid;
  const sheetId = state.categorySheetIds[category] || state.sheetId;
  if (!sheetId || gid == null) return "";
  const range = row ? `&range=A${row}:ZZ${row}` : "";
  return `https://docs.google.com/spreadsheets/d/${encodeURIComponent(sheetId)}/edit#gid=${encodeURIComponent(gid)}${range}`;
}

function categoryChoices(query) {
  const needle = normalize(query);
  if (!needle) return [];
  return state.categories.map(category => {
    const name = normalize(category);
    const initials = name.split(/[^a-z0-9]+/).filter(Boolean).map(word => word[0]).join("");
    let searchRank = 99;
    if (name === needle) searchRank = 0;
    else if (initials === needle) searchRank = 1;
    else if (name.startsWith(needle)) searchRank = 2;
    else if (name.includes(needle)) searchRank = 4;
    return {
      key: `tab:browse:${category}`, type: "category-browser", label: category,
      aliases: [], category: "Google Sheet", content: "", gid: state.categoryGids[category],
      row: 0, details: [], aiPrompt: "", tabName: category, searchRank,
    };
  }).filter(item => item.searchRank < 99);
}

function enterCategory(category) {
  state.activeCategory = category;
  state.query = ""; state.selectedIndex = 0; ui.search.value = "";
  ui.search.placeholder = `Search ${category}`;
  syncClearSearch(); renderResults(); focusSearchSoon();
}

function leaveCategory() {
  if (!state.activeCategory) return false;
  state.activeCategory = "";
  state.query = ""; state.selectedIndex = 0; ui.search.value = "";
  ui.search.placeholder = "Search";
  syncClearSearch(); renderResults(); focusSearchSoon();
  return true;
}

function rankedItems() {
  const query = normalize(state.query);
  if (!query && !state.activeCategory) return isMobileView() ? [] : recentItems();
  const source = state.activeCategory
    ? state.items.filter(item => item.category === state.activeCategory)
    : state.items;
  if (!query) return [...source].sort((a, b) => a.label.localeCompare(b.label));
  const matches = source.map(item => {
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
  }).filter(match => match.rank < 99);
  if (!state.activeCategory) {
    categoryChoices(state.query).forEach(item => matches.push({ item, rank: item.searchRank }));
  }
  return matches.sort((a, b) => a.rank - b.rank || a.item.label.localeCompare(b.item.label)).map(match => match.item);
}

function extractSingleUrl(value) {
  const text = String(value || ""), found = new Set();
  const clean = candidate => candidate.replace(/[)\]}.,;:!?]+$/, "");
  for (const match of text.matchAll(/https?:\/\/[^\s<>"']+/gi)) found.add(clean(match[0]));
  for (const match of text.matchAll(/(?:^|[^\w@])([\w-]+\.[a-z]{2,}[\w._~:/?#[\]@!$&'()*+,;=%-]*)/gi)) {
    const candidate = clean(match[1]);
    if (![...found].some(url => url.includes(candidate))) found.add(`https://${candidate}`);
  }
  return found.size === 1 ? [...found][0] : "";
}

function standaloneUrl(value) {
  const original = trim(value), url = extractSingleUrl(original);
  return url && (original === url || `https://${original}` === url) ? url : "";
}

function makeButton(label, title, handler) {
  const button = document.createElement("button");
  button.type = "button"; button.className = "action-button"; button.textContent = label; button.title = title;
  button.addEventListener("click", event => { event.stopPropagation(); handler(); });
  return button;
}

function makeIconButton(icon, title, handler) {
  const button = makeButton("", title, handler);
  button.classList.add("icon-action");
  button.setAttribute("aria-label", title);
  const image = document.createElement("img");
  image.src = `icons/${icon}.svg`; image.alt = "";
  button.append(image);
  return button;
}

function openExternal(url) {
  window.open(url, "_blank", "noopener,noreferrer");
}

function performPrimaryAction(item) {
  if (item.type === "category-browser") { enterCategory(item.tabName); return; }
  if (item.type === "search-service") { openSearchService(item); return; }
  if (item.details.length) { openDetails(item); return; }
  const url = standaloneUrl(item.content);
  if (url) { recordRecent(item); openExternal(url); return; }
  openPreview(item);
}

function renderResults() {
  const items = rankedItems();
  state.selectedIndex = Math.min(state.selectedIndex, Math.max(0, items.length - 1));
  ui.results.replaceChildren();
  if (!items.length) {
    if (!state.query && isMobileView()) return;
    const empty = document.createElement("div"); empty.className = "empty-state";
    empty.textContent = state.query
      ? (isMobileView() ? "No Sheet matches." : "No Sheet matches. Press Enter to search Google.")
      : "Your recently used items will appear here.";
    ui.results.append(empty); return;
  }
  items.slice(0, 30).forEach((item, index) => {
    const node = ui.template.content.firstElementChild.cloneNode(true);
    node.dataset.key = item.key; node.dataset.selected = String(index === state.selectedIndex);
    const title = node.querySelector(".result-title"); title.textContent = item.label;
    if (item.type === "search-service" || item.type === "category-browser" || item.details.length) { const arrow = document.createElement("span"); arrow.className = "arrow"; arrow.textContent = "→"; title.append(arrow); }
    const summary = trim(item.content);
    node.querySelector(".result-meta").textContent = `${item.category}${summary && summary !== item.label ? ` · ${summary.replace(/\s+/g, " ")}` : ""}`;
    const actions = node.querySelector(".result-actions");
    if (item.type === "category-browser") {
      const browseButton = makeButton("Browse", "Browse tab", () => enterCategory(item.tabName));
      browseButton.classList.add("search-action"); actions.append(browseButton);
    }
    else if (item.type === "search-service") {
      const searchButton = makeButton("Search", "Enter a query", () => openSearchService(item));
      searchButton.classList.add("search-action"); actions.append(searchButton);
    }
    else actions.append(makeIconButton("copy", "Copy", () => copyItem(item)));
    const url = extractSingleUrl(item.content); if (url) actions.append(makeIconButton("arrow-square-out", "Open link", () => { recordRecent(item); openExternal(url); }));
    const actionsButton = makeButton("•••", "Actions", () => openActions(item));
    actionsButton.classList.add("more-action");
    actionsButton.setAttribute("aria-label", `Actions for ${item.label}`);
    actions.append(actionsButton);
    node.querySelector(".result-main").addEventListener("click", () => performPrimaryAction(item));
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
function showToast(message) {
  ui.toast.textContent = message; ui.toast.classList.add("visible");
  if (ui.toast.showPopover && !ui.toast.matches(":popover-open")) ui.toast.showPopover();
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => {
    ui.toast.classList.remove("visible");
    if (ui.toast.hidePopover && ui.toast.matches(":popover-open")) ui.toast.hidePopover();
  }, 1300);
}

function buildAiPrompt(template, item) {
  const replaced = template.replace(/\{(?:medication|item|label)\}/gi, item.label);
  return replaced === template ? `${template}\n\nItem: ${item.label}` : replaced;
}

function askAi(prompt, item) {
  recordRecent(item);
  openExternal(`https://chatgpt.com/?q=${encodeURIComponent(prompt)}`);
}

function openPreview(item, content = item.content, title = item.label) {
  state.previewItem = item;
  ui.previewTitle.textContent = title;
  ui.previewBody.textContent = content;
  ui.previewActions.replaceChildren();
  ui.previewActions.append(makeIconButton("copy", "Copy", () => copyText(content, item)));
  const url = extractSingleUrl(content);
  if (url) ui.previewActions.append(makeIconButton("arrow-square-out", "Open link", () => { recordRecent(item); openExternal(url); }));
  recordRecent(item);
  ui.preview.showModal();
}

function openSearchService(item) {
  state.searchServiceItem = item;
  ui.searchServiceTitle.textContent = item.label;
  ui.serviceQuery.value = "";
  ui.searchService.showModal();
  focusServiceQuerySoon();
}

function launchSearchService() {
  const item = state.searchServiceItem, query = trim(ui.serviceQuery.value);
  if (!item || !query || !item.urlTemplate?.includes("$")) return;
  const url = item.urlTemplate.split("$").join(encodeURIComponent(query));
  if (!/^https?:\/\//i.test(url)) return;
  recordRecent(item); ui.searchService.close(); openExternal(url);
}

function openDetails(item) {
  ui.detailsTitle.textContent = item.label; ui.detailsList.replaceChildren();
  item.details.forEach(detail => {
    const block = document.createElement("section"); block.className = "detail";
    const heading = document.createElement("h3"); heading.textContent = detail.label; block.append(heading);
    if (trim(detail.content)) {
      const text = document.createElement("p"); text.className = "detail-text"; text.textContent = detail.content; block.append(text);
    }
    const actions = document.createElement("div"); actions.className = "detail-actions";
    if (trim(detail.content)) actions.append(makeIconButton("copy", "Copy", () => copyText(detail.content, item)));
    const url = extractSingleUrl(detail.content); if (url) actions.append(makeIconButton("arrow-square-out", "Open link", () => { recordRecent(item); openExternal(url); }));
    if (trim(detail.aiPrompt)) actions.append(makeButton("Ask AI", "Ask ChatGPT", () => askAi(buildAiPrompt(detail.aiPrompt, item), item)));
    if (trim(detail.content)) block.addEventListener("click", event => {
      if (event.target.closest("button")) return;
      const directUrl = standaloneUrl(detail.content);
      if (directUrl) { recordRecent(item); openExternal(directUrl); }
      else openPreview(item, detail.content, `${item.label} — ${detail.label}`);
    });
    block.append(actions); ui.detailsList.append(block);
  });
  ui.details.showModal();
}

function openActions(item) {
  state.actionsItem = item;
  ui.actionsTitle.textContent = `Actions · ${item.label}`;
  ui.actionsList.replaceChildren();
  const add = (label, shortcut, handler) => {
    const button = document.createElement("button");
    button.type = "button"; button.className = "action-row"; button.dataset.shortcut = shortcut.toLowerCase();
    const text = document.createElement("span"); text.textContent = label;
    const key = document.createElement("kbd"); key.textContent = shortcut;
    button.append(text, key);
    button.addEventListener("click", () => { ui.actions.close(); handler(); });
    ui.actionsList.append(button);
  };
  if (item.type === "category-browser") {
    add("Browse entries", "↵", () => enterCategory(item.tabName));
    const url = categorySheetUrl(item.tabName);
    if (url) add("Open in Google Sheets", "E", () => openExternal(url));
  }
  else if (item.type === "search-service") add("Search", "↵", () => openSearchService(item));
  else if (item.details.length) add("View details", "→", () => openDetails(item));
  if (trim(item.content)) {
    add("Preview", "P", () => openPreview(item));
    add("Copy", "C", () => copyItem(item));
  }
  const url = extractSingleUrl(item.content);
  if (url) add("Open link", "O", () => { recordRecent(item); openExternal(url); });
  if (trim(item.aiPrompt)) add("Ask AI", "A", () => askAi(buildAiPrompt(item.aiPrompt, item), item));
  if (!item.type?.startsWith("category-") && item.row) {
    const editUrl = categorySheetUrl(item.category, item.row);
    if (editUrl) add("Edit in Google Sheets", "E", () => openExternal(editUrl));
  }
  ui.actions.showModal();
}

function openSettings(firstRun) {
  ui.sheetUrl.value = state.sheetId ? `https://docs.google.com/spreadsheets/d/${state.sheetId}/edit` : "";
  document.querySelector("#disconnect-button").hidden = firstRun || !state.sheetId;
  document.querySelector("#share-button").hidden = !state.sheetId;
  if (!ui.settings.open) ui.settings.showModal();
}

async function shareCurrentSheet() {
  if (!state.sheetId) return;
  const url = sheetShareUrl();
  if (navigator.share) {
    try { await navigator.share({ title: "Trigger Search", url }); return; }
    catch (error) { if (error?.name === "AbortError") return; }
  }
  await copyText(url);
  showToast("Share link copied");
}

document.querySelector("#settings-button").addEventListener("click", () => openSettings(false));
document.querySelector("#share-button").addEventListener("click", shareCurrentSheet);
document.querySelector("#details-back").addEventListener("click", () => ui.details.close());
document.querySelector("#actions-back").addEventListener("click", () => ui.actions.close());
document.querySelector("#preview-back").addEventListener("click", () => ui.preview.close());
ui.preview.addEventListener("click", event => {
  if (event.target === ui.preview) { ui.preview.close(); ui.search.focus(); }
});
document.querySelector("#search-service-back").addEventListener("click", () => { ui.searchService.close(); ui.search.focus(); });
document.querySelector("#search-service-form").addEventListener("submit", event => { event.preventDefault(); launchSearchService(); });
ui.searchService.addEventListener("click", event => {
  if (event.target === ui.searchService) {
    ui.searchService.close();
    focusSearchSoon();
    return;
  }
  if (!isMobileView()) return;
  const target = event.target instanceof Element ? event.target : null;
  if (target?.closest("button, input, textarea, a")) return;
  focusServiceQuerySoon();
});
document.querySelectorAll("[data-close]").forEach(button => button.addEventListener("click", () => document.querySelector(`#${button.dataset.close}`).close()));
document.querySelector("#disconnect-button").addEventListener("click", () => { localStorage.removeItem("triggerSearch.sheetId"); state.sheetId = ""; syncSheetUrl(""); state.items = []; state.categories = []; state.categoryGids = {}; state.activeCategory = ""; ui.status.textContent = ""; ui.settings.close(); renderResults(); openSettings(true); });
document.querySelector("#settings-form").addEventListener("submit", event => {
  event.preventDefault(); const id = parseSheetId(ui.sheetUrl.value);
  if (!id) { showToast("That does not look like a Google Sheets link"); return; }
  state.sheetId = id; localStorage.setItem("triggerSearch.sheetId", id); syncSheetUrl(id); ui.settings.close(); focusSearchSoon(); loadWorkbook();
});

ui.search.addEventListener("input", () => { state.query = ui.search.value; state.selectedIndex = 0; syncClearSearch(); renderResults(); });
ui.clearSearch?.addEventListener("click", clearMainSearch);
function focusSearchFromPageTap(event, immediate = false) {
  if ((!isMobileView() && !isTouchDevice()) || anyDialogOpen()
      || document.activeElement === ui.search) return;
  const target = event.target instanceof Element ? event.target : null;
  if (target?.closest("#search, #clear-search, #settings-button, .brand, button, input, textarea, a, .result")) return;
  if (immediate) focusSearchNow();
  else focusSearchSoon();
}

// Match the proven WYR.ES interaction: focus synchronously during the actual
// touch gesture so iOS opens the keyboard, without cancelling the tap.
document.addEventListener("touchstart", event => focusSearchFromPageTap(event, true),
  { passive: true });
document.addEventListener("click", event => focusSearchFromPageTap(event));

const handleViewportChange = () => {
  renderResults();
  if (isMobileView()) focusSearchSoon();
};
if (mobileViewport.addEventListener) mobileViewport.addEventListener("change", handleViewportChange);
else mobileViewport.addListener(handleViewportChange);

document.addEventListener("keydown", event => {
  if (ui.actions.open) {
    if (event.key === "Escape" || event.key === "ArrowLeft") {
      event.preventDefault(); ui.actions.close(); ui.search.focus(); return;
    }
    const shortcut = event.key === "Enter" ? "↵" : event.key === "ArrowRight" ? "→" : event.key.toLowerCase();
    const action = [...ui.actionsList.querySelectorAll(".action-row")]
      .find(button => button.dataset.shortcut === shortcut);
    if (action) { event.preventDefault(); action.click(); }
    return;
  }
  if (ui.settings.open || ui.details.open || ui.searchService.open || ui.preview.open) {
    if (event.key === "Escape" || ((ui.details.open || ui.searchService.open || ui.preview.open) && event.key === "ArrowLeft")) {
      event.preventDefault();
      if (ui.preview.open) ui.preview.close();
      else if (ui.searchService.open) ui.searchService.close();
      else if (ui.details.open) ui.details.close();
      else ui.settings.close();
      if (!ui.settings.open) ui.search.focus();
    }
    return;
  }
  const items = rankedItems();
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
    const item = items[state.selectedIndex];
    if (item) { event.preventDefault(); openActions(item); }
    return;
  }
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "g" && trim(ui.search.value)) { event.preventDefault(); openExternal(`https://www.google.com/search?q=${encodeURIComponent(trim(ui.search.value))}`); return; }
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "e") {
    const item = items[state.selectedIndex];
    const url = item?.type?.startsWith("category-") ? categorySheetUrl(item.tabName) : item ? categorySheetUrl(item.category, item.row) : "";
    if (url) { event.preventDefault(); openExternal(url); }
    return;
  }
  if ((event.metaKey || event.ctrlKey) && /^[1-9]$/.test(event.key)) { const item = items[Number(event.key) - 1]; if (item) { event.preventDefault(); copyItem(item); } return; }
  if (event.key === "ArrowDown" || event.key === "ArrowUp") { event.preventDefault(); const delta = event.key === "ArrowDown" ? 1 : -1; state.selectedIndex = Math.max(0, Math.min(items.length - 1, state.selectedIndex + delta)); renderResults(); document.querySelectorAll(".result")[state.selectedIndex]?.focus(); return; }
  if (event.key === "ArrowRight") { const item = items[state.selectedIndex]; if (item?.type === "category-browser" || item?.type === "search-service" || item?.details.length) { event.preventDefault(); item.type === "category-browser" ? enterCategory(item.tabName) : item.type === "search-service" ? openSearchService(item) : openDetails(item); } return; }
  if (event.key === "ArrowLeft" && leaveCategory()) { event.preventDefault(); return; }
  if (event.key === "Enter" && document.activeElement === ui.search) {
    const item = items[state.selectedIndex];
    if (item) { event.preventDefault(); performPrimaryAction(item); }
    else if (trim(ui.search.value)) {
      event.preventDefault();
      openExternal(`https://www.google.com/search?q=${encodeURIComponent(trim(ui.search.value))}`);
    }
  }
  if (event.key === "Escape") { if (!leaveCategory()) clearMainSearch(); }
});

if ("serviceWorker" in navigator) window.addEventListener("load", () => navigator.serviceWorker.register("service-worker.js"));
window.addEventListener("pageshow", focusSearchSoon);
syncClearSearch(); renderResults(); focusSearchSoon(); loadWorkbook();
