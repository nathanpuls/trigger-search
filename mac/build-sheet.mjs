import fs from "node:fs/promises";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const outputDir = new URL("./outputs/", import.meta.url).pathname;
await fs.mkdir(outputDir, { recursive: true });

const workbook = Workbook.create();
const sheet = workbook.worksheets.add("Snippets");

sheet.getRange("A1:D5").values = [
  ["Shortcut", "Title", "Content", "Category"],
  ["email", "Email address", "me@example.com", "Personal"],
  ["sig", "Short signature", "Thanks,\nNathan", "Writing"],
  ["addr", "Mailing address", "123 Example Street\nChicago, IL 60601", "Personal"],
  ["meet", "Meeting link", "https://meet.google.com/your-meeting", "Work"],
];

sheet.getRange("A1:D1").format = {
  fill: "#F1F3F4",
  font: { bold: true, color: "#202124" },
  borders: { bottom: { style: "thin", color: "#DADCE0" } },
  verticalAlignment: "center",
};

sheet.getRange("A2:D5").format = {
  font: { color: "#202124" },
  verticalAlignment: "top",
};

sheet.getRange("C2:C5").format.wrapText = true;
sheet.getRange("A1:A5").format.columnWidth = 16;
sheet.getRange("B1:B5").format.columnWidth = 24;
sheet.getRange("C1:C5").format.columnWidth = 48;
sheet.getRange("D1:D5").format.columnWidth = 18;
sheet.getRange("1:1").format.rowHeight = 24;
sheet.getRange("2:5").format.rowHeight = 34;
sheet.freezePanes.freezeRows(1);

const inspection = await workbook.inspect({
  kind: "table",
  range: "Snippets!A1:D5",
  include: "values,formulas",
  tableMaxRows: 10,
  tableMaxCols: 6,
});
console.log(inspection.ndjson);

const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 50 },
  summary: "final formula error scan",
});
console.log(errors.ndjson);

const preview = await workbook.render({
  sheetName: "Snippets",
  range: "A1:D5",
  scale: 2,
  format: "png",
});
await fs.writeFile(
  `${outputDir}/mac-autocomplete-snippets-preview.png`,
  new Uint8Array(await preview.arrayBuffer()),
);

const xlsx = await SpreadsheetFile.exportXlsx(workbook);
await xlsx.save(`${outputDir}/mac-autocomplete-snippets.xlsx`);
