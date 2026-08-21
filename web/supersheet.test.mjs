import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(new URL("./app.js", import.meta.url), "utf8");
const helpers = `
const trim = value => String(value ?? "").trim();
const normalize = value => trim(value).toLowerCase();
const tabKey = value => normalize(value).replace(/[\\s_&-]+/g, "");
${source.slice(
  source.indexOf("function modeOverrideKey"),
  source.indexOf("function focusServiceQuerySoon"),
)}
${source.slice(
  source.indexOf("function parseCsv"),
  source.indexOf("function parseIncludedSheets"),
)}
${source.slice(
  source.indexOf("function cacheKey"),
  source.indexOf("function categorySheetUrl"),
)}`;

const tests = `
  const labeled = parseSuperSheetTab(
    'Name,URL,Notes\\nAlice,https://example.com,Follow up', 'Contacts', '777');
  assert.equal(labeled.length, 3);
  assert.equal(labeled[0].isRowRepresentative, true);
  assert.deepEqual(labeled[1].context, ['Alice', 'URL', 'Contacts']);
  assert.equal(labeled[1].column, 2);

  const unlabeled = parseSuperSheetTab(
    ',,\\nFirst useful,Right value', 'Plain', '778');
  assert.equal(unlabeled.length, 2);
  assert.equal(unlabeled[1].columnLabel, '');

  const template = parseSuperSheetTab(
    'Name,Search\\nDocs,https://example.com/find?q=$', 'Tools', '779');
  assert.equal(template[1].type, 'search-service');
  assert.equal(template[1].urlTemplate, 'https://example.com/find?q=$');

  assert.equal(parseMode('Setting,Value\\nMode,SuperSheet'), 'supersheet');
  assert.equal(parseMode('Setting,Value\\nMode,Trigger Search'), 'triggersearch');
  assert.equal(parseSettings('Setting,Value\\nInbox Sheet,Capture').inboxSheet, 'Capture');

  state.workbookData = [{
    csv: 'Name,Content\\nAlice,Hello', category: 'Contacts', gid: '1', sheetId: 'sheet-1'
  }];
  assert.equal(installWorkbookData(state.workbookData), true);
  assert.equal(state.mode, 'triggersearch');
  assert.equal(state.items.length, 1);
  toggleMode();
  assert.equal(state.mode, 'supersheet');
  assert.equal(state.items.length, 2);
  assert.equal(localStorage.getItem(modeOverrideKey()), 'supersheet');
  resetModeOverride();
  assert.equal(state.mode, 'triggersearch');
  assert.equal(localStorage.getItem(modeOverrideKey()), null);

  state.inboxSheet = 'Inbox';
  state.items = [
    ...parseTab('Name,Content\\nNewest,Latest text\\nOlder,Old text', 'Inbox', '2'),
    ...parseTab('Name,Content\\nOther,Elsewhere', 'Notes', '3'),
  ];
  localStorage.setItem(recentKey(), JSON.stringify([state.items[2].key, state.items[0].key]));
  assert.equal(homeItems()[0].label, 'Newest');
  assert.equal(homeItems()[0].isPinnedInbox, true);
  assert.deepEqual(homeItems().map(item => item.label), ['Newest', 'Other']);
`;

const storage = new Map();
const state = {
  sheetId: "sheet-1", mode: "triggersearch", sheetMode: "triggersearch",
  inboxSheet: "Inbox",
  workbookData: [], items: [], categories: [], categoryGids: {}, categorySheetIds: {},
  activeCategory: "", activeRow: null, query: "", selectedIndex: 0,
};
const ui = { search: { value: "", placeholder: "" } };
const localStorage = {
  getItem: key => storage.has(key) ? storage.get(key) : null,
  setItem: (key, value) => storage.set(key, String(value)),
  removeItem: key => storage.delete(key),
};
const noop = () => {};
vm.runInNewContext(`
  function syncClearSearch() {}
  function syncModeUi() {}
  function renderResults() {}
  function updateModeSettings() {}
  function focusSearchSoon() {}
  function showToast() {}
  function isMobileView() { return false; }
  ${helpers}\n${tests}
`, { assert, localStorage, state, ui, console, setTimeout, requestAnimationFrame: noop });
console.log("SuperSheet web parser tests passed");
