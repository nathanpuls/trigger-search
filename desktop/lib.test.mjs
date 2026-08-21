import test from "node:test";
import assert from "node:assert/strict";
import { homeItems, normalizeSearchTemplate, parseSettings, parseTab, rankedItems } from "./lib.mjs";

test("headered and headerless Trigger Search rows parse", () => {
  const headered = parseTab('"Name","Alias","Content"\n"Apple","a","red apple"', "Snips", "1", "sheet");
  assert.equal(headered[0].label, "Apple");
  assert.deepEqual(headered[0].aliases, ["a"]);
  const headerless = parseTab("Apple,a,red apple\nBanana,b,yellow banana", "Snips", "1", "sheet");
  assert.deepEqual(headerless.map(item => item.label), ["Apple", "Banana"]);
  assert.deepEqual(headerless[0].aliases, ["a"]);
});

test("an Inbox capture appended to the Content header is recovered", () => {
  const items = parseTab('"Name ","Content Latest captured note"\n"","Older note"', "Inbox", "1", "sheet");
  assert.equal(items[0].content, "Latest captured note");
  assert.equal(items[1].content, "Older note");
});

test("equal search matches retain Sheet order", () => {
  const items = [
    { label: "Zulu note", aliases: [], content: "match", details: [] },
    { label: "Alpha note", aliases: [], content: "match", details: [] },
  ];
  assert.deepEqual(rankedItems(items, "match").map(item => item.label), ["Zulu note", "Alpha note"]);
});

test("latest Inbox row is pinned without duplication", () => {
  const items = [
    { key: "new", label: "Newest", category: "Inbox" },
    { key: "old", label: "Older", category: "Inbox" },
  ];
  assert.deepEqual(homeItems(items, [items[0], items[1]], "Inbox").map(item => item.key), ["new", "old"]);
});

test("settings and search templates reuse Trigger Search conventions", () => {
  const csv = 'Setting,Value\nInbox Sheet,Capture\n\nIncluded Sheet Name,Google Sheet URL';
  assert.equal(parseSettings(csv).inboxSheet, "Capture");
  assert.equal(normalizeSearchTemplate("example.com/search?q=$"), "https://example.com/search?q=$");
});
