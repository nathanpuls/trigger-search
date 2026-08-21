export const trim = value => String(value ?? "").trim();
export const normalize = value => trim(value).toLowerCase();
export const tabKey = value => normalize(value).replace(/[\s_&-]+/g, "");

export function parseSheetId(value) {
  const text = trim(value);
  const match = text.match(/\/spreadsheets\/d\/([A-Za-z0-9_-]+)/);
  const candidate = match ? match[1] : text;
  return /^[A-Za-z0-9_-]{20,}$/.test(candidate) ? candidate : "";
}

export function parseCsv(text) {
  const rows = [];
  let row = [], field = "", quoted = false;
  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    if (quoted) {
      if (character === '"' && text[index + 1] === '"') { field += '"'; index += 1; }
      else if (character === '"') quoted = false;
      else field += character;
    } else if (character === '"') quoted = true;
    else if (character === ",") { row.push(field); field = ""; }
    else if (character === "\n") { row.push(field.replace(/\r$/, "")); rows.push(row); row = []; field = ""; }
    else field += character;
  }
  if (field !== "" || row.length) { row.push(field.replace(/\r$/, "")); rows.push(row); }
  return rows;
}

export function normalizeSearchTemplate(value) {
  const template = trim(value);
  if (!template.includes("$")) return "";
  if (/^https?:\/\/\S+$/i.test(template)) return template;
  if (/^(?:[a-z0-9-]+\.)+[a-z]{2,}\S*$/i.test(template)) return `https://${template}`;
  return "";
}

export function parseTab(csv, category, gid, sheetId) {
  let rows = parseCsv(csv).filter(row => row.some(cell => trim(cell)));
  if (!rows.length) return [];
  // A capture Shortcut can accidentally append its first value to the Content
  // header cell. Recover that visible top item instead of discarding the whole
  // tab as a malformed header.
  const firstName = normalize(rows[0][0]).replace(/^\uFEFF/, "");
  const firstContent = trim(rows[0][1]);
  if (firstName === "name" && /^content\s+\S/i.test(firstContent)) {
    const repaired = [...rows[0]];
    repaired[0] = "";
    repaired[1] = firstContent.replace(/^content\s+/i, "");
    const headers = rows[0].map(() => "");
    headers[0] = "Name";
    headers[1] = "Content";
    rows = [headers, repaired, ...rows.slice(1)];
  }
  const headers = rows[0].map(cell => normalize(cell.replace(/^\uFEFF/, "")));
  const isSearchTab = tabKey(category.split(" · ").at(-1)) === "search";
  let nameIndex = headers.indexOf("name");
  let contentIndex = headers.indexOf("content");
  let aliasIndex = headers.indexOf("alias");
  const hasHeaders = nameIndex >= 0 || contentIndex >= 0 || aliasIndex >= 0;

  if (isSearchTab) {
    if (nameIndex < 0 || contentIndex < 0 || aliasIndex < 0) return [];
    return rows.slice(1).map((row, offset) => {
      const label = trim(row[nameIndex]);
      const template = normalizeSearchTemplate(row[contentIndex]);
      if (!label || !template) return null;
      return {
        key: `${category}:${offset + 2}`, type: "search-service", label,
        aliases: trim(row[aliasIndex]).split(/[,;|\n]/).map(trim).filter(Boolean),
        content: "", urlTemplate: template, category, gid, sheetId,
        row: offset + 2, details: [],
      };
    }).filter(Boolean);
  }

  if (hasHeaders && contentIndex < 0) return [];
  if (!hasHeaders) {
    const rightmost = rows.reduce((maximum, row) => Math.max(maximum,
      row.reduce((last, cell, index) => trim(cell) ? index + 1 : last, 0)), 0);
    if (rightmost > 3) return [];
    if (rightmost === 1) { nameIndex = -1; aliasIndex = -1; contentIndex = 0; }
    else if (rightmost === 2) { nameIndex = 0; aliasIndex = -1; contentIndex = 1; }
    else if (rightmost === 3) { nameIndex = 0; aliasIndex = 1; contentIndex = 2; }
  }

  const firstDataRow = hasHeaders ? 1 : 0;
  const displayHeaders = rows[0];
  const items = [];
  rows.slice(firstDataRow).forEach((row, offset) => {
    const sheetRow = firstDataRow + offset + 1;
    const rawName = nameIndex >= 0 ? trim(row[nameIndex]) : "";
    const content = contentIndex >= 0 ? row[contentIndex] || "" : "";
    if (tabKey(rawName) === "aiprompt") return;
    const preview = trim(content).replace(/\s+/g, " ");
    const label = rawName || (preview.length > 68 ? `${preview.slice(0, 65)}…` : preview);
    if (!label) return;
    const aliases = aliasIndex >= 0
      ? trim(row[aliasIndex]).split(/[,;|\n]/).map(trim).filter(Boolean) : [];
    const details = [];
    if (hasHeaders) headers.forEach((header, index) => {
      if (!header || index === nameIndex || index === aliasIndex || index === contentIndex) return;
      if (trim(row[index])) details.push({ label: trim(displayHeaders[index]), content: row[index] });
    });
    if (!trim(content) && !details.length) return;
    items.push({
      key: `${category}:${sheetRow}`, type: "snippet", label, content, aliases,
      category, gid, sheetId, row: sheetRow, details,
    });
  });
  return items;
}

export function parseSettings(csv) {
  const rows = parseCsv(csv).filter(row => row.some(cell => trim(cell)));
  const settings = { inboxSheet: "Inbox", included: [], hidden: new Set() };
  if (!rows.length) return settings;
  const headers = rows[0].map(cell => normalize(cell.replace(/^\uFEFF/, "")));
  const settingIndex = headers.indexOf("setting");
  const valueIndex = headers.indexOf("value");
  if (settingIndex >= 0 && valueIndex >= 0) rows.slice(1).forEach(row => {
    if (tabKey(row[settingIndex]) === "inboxsheet") settings.inboxSheet = trim(row[valueIndex]) || "Inbox";
  });
  const hiddenIndex = ["hidden tab", "excluded tab", "hide tab"]
    .map(name => headers.indexOf(name)).find(index => index >= 0) ?? -1;
  if (hiddenIndex >= 0) settings.hidden = new Set(rows.slice(1).map(row => tabKey(row[hiddenIndex])).filter(Boolean));
  const nameIndex = ["included sheet name", "source name"]
    .map(name => headers.indexOf(name)).find(index => index >= 0) ?? -1;
  const urlIndex = ["google sheet url", "sheet url"]
    .map(name => headers.indexOf(name)).find(index => index >= 0) ?? -1;
  const enabledIndex = ["enabled", "include"]
    .map(name => headers.indexOf(name)).find(index => index >= 0) ?? -1;
  if (nameIndex >= 0 && urlIndex >= 0) settings.included = rows.slice(1).map(row => {
    const name = trim(row[nameIndex]), sheetId = parseSheetId(row[urlIndex]);
    const enabled = enabledIndex < 0 || !/^(?:false|no|0|off)$/i.test(trim(row[enabledIndex]));
    return name && sheetId && enabled ? { name, sheetId } : null;
  }).filter(Boolean);
  return settings;
}

export function standaloneUrl(value) {
  const text = trim(value);
  if (/^https?:\/\/\S+$/i.test(text)) return text;
  if (/^(?:[a-z0-9-]+\.)+[a-z]{2,}\S*$/i.test(text)) return `https://${text}`;
  return "";
}

export function isInboxCategory(category, inboxSheet = "Inbox") {
  const target = tabKey(inboxSheet || "Inbox");
  const parts = String(category || "").split(" · ");
  return tabKey(category) === target || tabKey(parts.at(-1)) === target;
}

export function homeItems(items, recents, inboxSheet = "Inbox", limit = 9) {
  const pinned = items.find(item => isInboxCategory(item.category, inboxSheet));
  return [pinned ? { ...pinned, pinned: true } : null,
    ...recents.filter(item => !pinned || item.key !== pinned.key)]
    .filter(Boolean).slice(0, limit);
}

export function rankedItems(items, query) {
  const needle = normalize(query);
  if (!needle) return [...items];
  return items.map((item, sourceOrder) => {
    const label = normalize(item.label);
    const aliases = (item.aliases || []).map(normalize);
    const content = normalize(item.content);
    let rank = 99;
    if (aliases.includes(needle)) rank = 0;
    else if (label === needle) rank = 1;
    else if (aliases.some(alias => alias.startsWith(needle))) rank = 2;
    else if (label.startsWith(needle)) rank = 3;
    else if (aliases.some(alias => alias.includes(needle))) rank = 4;
    else if (label.includes(needle)) rank = 5;
    else if (content.includes(needle)) rank = 6;
    else if ((item.details || []).some(detail => normalize(`${detail.label} ${detail.content}`).includes(needle))) rank = 7;
    return { item, rank, sourceOrder };
  }).filter(entry => entry.rank < 99)
    .sort((a, b) => a.rank - b.rank || a.sourceOrder - b.sourceOrder)
    .map(entry => entry.item);
}
