import {
  homeItems, normalize, normalizeSearchTemplate, parseSettings, parseTab,
  rankedItems, standaloneUrl, tabKey, trim,
} from "./lib.mjs";

const skippedTabs = new Set(["settings", "settingshelp", "readme", "blanktemplate", "autohotkey"]);
const state = {
  sheetId: "", items: [], categories: [], query: "", selected: 0,
  inboxSheet: "Inbox", category: "", detailParent: null, searchService: null,
  loading: false,
};

const ui = {
  search: document.querySelector("#search"),
  results: document.querySelector("#results"),
  status: document.querySelector("#status"),
  back: document.querySelector("#back"),
  refresh: document.querySelector("#refresh"),
  settings: document.querySelector("#settings"),
  settingsDialog: document.querySelector("#settings-dialog"),
  settingsForm: document.querySelector("#settings-form"),
  sheetUrl: document.querySelector("#sheet-url"),
  permissionDialog: document.querySelector("#permission-dialog"),
  shortcut: document.querySelector("#shortcut"),
};

function cacheKey() { return `trigger-search-desktop-cache:${state.sheetId}`; }
function recentKey() { return `trigger-search-desktop-recents:${state.sheetId}`; }

function recents() {
  const keys = JSON.parse(localStorage.getItem(recentKey()) || "[]");
  return keys.map(key => state.items.find(item => item.key === key)).filter(Boolean);
}

function recordRecent(item) {
  if (!item?.key || item.type === "category") return;
  const keys = JSON.parse(localStorage.getItem(recentKey()) || "[]").filter(key => key !== item.key);
  localStorage.setItem(recentKey(), JSON.stringify([item.key, ...keys].slice(0, 9)));
}

function categoryChoices(query) {
  const needle = normalize(query);
  if (!needle) return [];
  return state.categories.map((category, index) => {
    const name = normalize(category);
    const initials = name.split(/[^a-z0-9]+/).filter(Boolean).map(word => word[0]).join("");
    let rank = 99;
    if (name === needle) rank = 0;
    else if (initials === needle) rank = 1;
    else if (name.startsWith(needle)) rank = 2;
    else if (name.includes(needle)) rank = 4;
    return { key: `category:${category}`, type: "category", label: category, category, rank, sourceOrder: index };
  }).filter(item => item.rank < 99);
}

function visibleItems() {
  if (state.searchService) {
    const query = trim(state.query);
    return query ? [{
      key: `query:${state.searchService.key}`, type: "search-query",
      label: `Search ${state.searchService.label} for “${query}”`,
      category: state.searchService.category, query, service: state.searchService,
    }] : [];
  }
  if (state.detailParent) {
    return state.detailParent.details.map((detail, index) => ({
      key: `${state.detailParent.key}:detail:${index}`, type: "detail",
      label: detail.label, content: detail.content, category: state.detailParent.label,
    }));
  }
  const source = state.category
    ? state.items.filter(item => item.category === state.category)
    : state.items;
  if (!state.query && !state.category) return homeItems(source, recents(), state.inboxSheet);
  if (!state.query) return [...source];
  const matches = rankedItems(source, state.query);
  if (!state.category) {
    const categories = categoryChoices(state.query).sort((a, b) => a.rank - b.rank || a.sourceOrder - b.sourceOrder);
    return [...categories, ...matches].slice(0, 40);
  }
  return matches.slice(0, 40);
}

function resultMeta(item) {
  if (item.type === "category") return "Google Sheet · Return to browse";
  if (item.type === "search-query") return "Return to open in your browser";
  const content = trim(item.content).replace(/\s+/g, " ");
  const context = content && normalize(content) !== normalize(item.label) ? ` · ${content}` : "";
  return `${item.pinned ? "Pinned latest · " : ""}${item.category || ""}${context}`;
}

function render() {
  const items = visibleItems();
  state.selected = Math.max(0, Math.min(state.selected, Math.max(0, items.length - 1)));
  ui.results.replaceChildren();
  ui.back.hidden = !(state.category || state.detailParent || state.searchService);
  ui.search.placeholder = state.searchService ? `Search ${state.searchService.label}`
    : state.detailParent ? `Search ${state.detailParent.label}`
      : state.category ? `Search ${state.category}` : "Search";
  if (!items.length) {
    const empty = document.createElement("div");
    empty.className = "empty";
    empty.textContent = state.loading ? "Refreshing…" : state.query ? "No matches" : "Start typing to search your Sheet";
    ui.results.append(empty);
    return;
  }
  items.forEach((item, index) => {
    const row = document.createElement("button");
    row.type = "button";
    row.className = `result${index === state.selected ? " selected" : ""}`;
    row.innerHTML = `<span><div class="result-title"></div><div class="result-meta"></div></span><span class="result-key"></span>`;
    row.querySelector(".result-title").textContent = item.label;
    row.querySelector(".result-meta").textContent = resultMeta(item);
    row.querySelector(".result-key").textContent = index < 9 ? `⌘${index + 1}` : "";
    row.addEventListener("mouseenter", () => { state.selected = index; render(); });
    row.addEventListener("click", () => act(item));
    ui.results.append(row);
  });
  ui.results.querySelector(".selected")?.scrollIntoView({ block: "nearest" });
}

function goBack() {
  if (state.searchService) state.searchService = null;
  else if (state.detailParent) state.detailParent = null;
  else if (state.category) state.category = "";
  else return false;
  state.query = "";
  state.selected = 0;
  ui.search.value = "";
  render();
  ui.search.focus();
  return true;
}

async function act(item) {
  if (!item) return;
  if (item.type === "category") {
    state.category = item.category; state.query = ""; state.selected = 0; ui.search.value = ""; render(); return;
  }
  if (item.type === "search-service") {
    state.searchService = item; state.query = ""; state.selected = 0; ui.search.value = ""; render(); return;
  }
  if (item.type === "search-query") {
    const url = item.service.urlTemplate.split("$").join(encodeURIComponent(item.query));
    recordRecent(item.service); await window.triggerSearch.open(url); return;
  }
  const url = standaloneUrl(item.content);
  recordRecent(item);
  if (url) { await window.triggerSearch.open(url); return; }
  const result = await window.triggerSearch.paste(item.content);
  if (!result.ok && result.copied) ui.permissionDialog.showModal();
}

async function loadWorkbook(force = false) {
  if (!state.sheetId || state.loading) return;
  state.loading = true;
  ui.status.textContent = "Refreshing…";
  render();
  try {
    const primary = await window.triggerSearch.fetchWorkbook(state.sheetId);
    const settingsTab = primary.find(sheet => ["settings", "settingshelp"].includes(tabKey(sheet.name)));
    const settings = settingsTab ? parseSettings(settingsTab.csv) : parseSettings("");
    const included = (await Promise.all(settings.included.map(async source => {
      try { return await window.triggerSearch.fetchWorkbook(source.sheetId, source.name); }
      catch { return []; }
    }))).flat();
    const sheets = [...primary, ...included].filter(sheet =>
      !skippedTabs.has(tabKey(sheet.name))
      && !settings.hidden.has(tabKey(sheet.name))
      && !settings.hidden.has(tabKey(sheet.category)));
    state.items = sheets.flatMap(sheet => parseTab(sheet.csv, sheet.category, sheet.gid, sheet.sheetId));
    state.categories = sheets.map(sheet => sheet.category);
    state.inboxSheet = settings.inboxSheet;
    localStorage.setItem(cacheKey(), JSON.stringify({
      items: state.items, categories: state.categories, inboxSheet: state.inboxSheet,
    }));
    ui.status.textContent = `${state.items.length} items`;
  } catch (error) {
    const cached = JSON.parse(localStorage.getItem(cacheKey()) || "null");
    if (cached) {
      state.items = cached.items || [];
      state.categories = cached.categories || [];
      state.inboxSheet = cached.inboxSheet || "Inbox";
      ui.status.textContent = `Offline copy · ${state.items.length} items`;
    } else ui.status.textContent = error.message || "Could not load the Sheet";
  } finally {
    state.loading = false;
    render();
    ui.search.focus();
  }
}

async function openSettings() {
  ui.sheetUrl.value = state.sheetId ? `https://docs.google.com/spreadsheets/d/${state.sheetId}/edit` : "";
  ui.settingsDialog.showModal();
  ui.sheetUrl.focus();
}

ui.search.addEventListener("input", () => {
  state.query = ui.search.value; state.selected = 0; render();
});
ui.back.addEventListener("click", goBack);
ui.refresh.addEventListener("click", () => loadWorkbook(true));
ui.settings.addEventListener("click", openSettings);
document.querySelector("#cancel-settings").addEventListener("click", () => ui.settingsDialog.close());
document.querySelector("#permission-close").addEventListener("click", () => ui.permissionDialog.close());
ui.settingsForm.addEventListener("submit", async event => {
  event.preventDefault();
  try {
    const config = await window.triggerSearch.setSheet(ui.sheetUrl.value);
    state.sheetId = config.sheetId;
    ui.settingsDialog.close();
    await loadWorkbook(true);
  } catch (error) { ui.status.textContent = error.message; }
});

document.addEventListener("keydown", event => {
  if (ui.settingsDialog.open || ui.permissionDialog.open) {
    if (event.key === "Escape") { ui.settingsDialog.close(); ui.permissionDialog.close(); }
    return;
  }
  const items = visibleItems();
  if (event.key === "ArrowDown" || event.key === "ArrowUp") {
    event.preventDefault();
    state.selected = Math.max(0, Math.min(items.length - 1, state.selected + (event.key === "ArrowDown" ? 1 : -1)));
    render();
  } else if (event.key === "Enter") {
    event.preventDefault(); act(items[state.selected]);
  } else if (event.key === "ArrowRight") {
    const item = items[state.selected];
    if (item?.details?.length) {
      event.preventDefault(); state.detailParent = item; state.query = ""; state.selected = 0; ui.search.value = ""; render();
    } else if (item?.type === "category" || item?.type === "search-service") {
      event.preventDefault(); act(item);
    }
  } else if (event.key === "ArrowLeft") {
    if (goBack()) event.preventDefault();
  } else if (event.key === "Escape") {
    event.preventDefault();
    if (!goBack()) window.triggerSearch.hide();
  } else if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "r") {
    event.preventDefault(); loadWorkbook(true);
  } else if ((event.metaKey || event.ctrlKey) && /^[1-9]$/.test(event.key)) {
    const item = items[Number(event.key) - 1];
    if (item) { event.preventDefault(); act(item); }
  }
});

window.triggerSearch.onShown(() => {
  state.query = ""; state.selected = 0; state.category = ""; state.detailParent = null; state.searchService = null;
  ui.search.value = ""; render(); ui.search.focus(); loadWorkbook();
});

const config = await window.triggerSearch.getConfig();
state.sheetId = config.sheetId || "";
ui.shortcut.textContent = "⌘⇧Space";
if (!state.sheetId) openSettings();
else loadWorkbook();
render();
