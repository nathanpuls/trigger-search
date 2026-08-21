"use strict";

const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("triggerSearch", {
  getConfig: () => ipcRenderer.invoke("config:get"),
  setSheet: value => ipcRenderer.invoke("config:set-sheet", value),
  fetchWorkbook: (sheetId, sourceName = "") => ipcRenderer.invoke("workbook:fetch", sheetId, sourceName),
  paste: value => ipcRenderer.invoke("action:paste", value),
  copy: value => ipcRenderer.invoke("action:copy", value),
  open: url => ipcRenderer.invoke("action:open", url),
  hide: () => ipcRenderer.send("launcher:hide"),
  onShown: callback => ipcRenderer.on("launcher:shown", callback),
});
