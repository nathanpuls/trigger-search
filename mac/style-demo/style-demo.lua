-- Standalone visual sampler for hs.chooser.
-- It does not load, edit, or replace the working autocomplete configuration.

local demo = {}

local colors = {
  graphite = { hex = "#2F3437" },
  muted = { hex = "#7A8288" },
  teal = { hex = "#087E8B" },
  blue = { hex = "#1769E0" },
  purple = { hex = "#7656B5" },
  rust = { hex = "#A1492D" },
}

local function styled(value, fontName, size, color)
  return hs.styledtext.new(value, {
    font = { name = fontName, size = size },
    color = color,
  })
end

local function icon(name)
  local image = hs.image.imageFromName(name)
  if image then image:setSize({ w = 26, h = 26 }) end
  return image
end

local choices = {
  {
    text = styled("Atomoxetine   ›", "Avenir Next Medium", 16, colors.graphite),
    subText = styled("A restrained system-style row • 6 details", "Avenir Next", 11,
      colors.muted),
    image = icon("NSActionTemplate"),
    styleName = "System arrow",
  },
  {
    text = styled("Atomoxetine   ›", "Avenir Next Demi Bold", 17, colors.teal),
    subText = styled("Teal title • slightly larger and heavier", "Avenir Next", 11,
      colors.muted),
    image = icon("NSInfo"),
    styleName = "Teal + information icon",
  },
  {
    text = styled("Medication details", "Avenir Next Demi Bold", 17, colors.purple),
    subText = styled("Purple heading • folder-style icon", "Avenir Next", 11,
      colors.muted),
    image = icon("NSFolder"),
    styleName = "Purple + folder",
  },
  {
    text = styled("SIG", "Menlo Bold", 15, colors.blue),
    subText = styled("Monospaced label • Take 1 capsule each morning…", "Menlo", 10,
      colors.muted),
    image = icon("NSQuickLookTemplate"),
    styleName = "Monospaced clinical detail",
  },
  {
    text = styled("Personal", "Georgia Bold", 17, colors.rust),
    subText = styled("A warmer serif treatment for a category", "Georgia Italic", 11,
      colors.muted),
    image = icon("NSUserAccounts"),
    styleName = "Warm serif + people",
  },
  {
    text = styled("Default arrow — no custom image", "Avenir Next", 16, colors.graphite),
    subText = styled("Hammerspoon restores its arrow when image is omitted", "Avenir Next", 11,
      colors.muted),
    styleName = "Default Hammerspoon arrow",
  },
  {
    text = styled("Larger, high-contrast title", "Avenir Next Heavy", 19,
      colors.graphite),
    subText = styled("Useful if the current labels feel too quiet", "Avenir Next Medium", 12,
      colors.teal),
    image = icon("NSAdvanced"),
    styleName = "High contrast",
  },
}

demo.chooser = hs.chooser.new(function(choice)
  if choice then hs.alert.show("Style sample: " .. choice.styleName) end
end)
  :placeholderText("Visual samples only — nothing here will paste")
  :choices(choices)
  :rows(7)
  :width(48)
  :bgDark(false)

function demo.show()
  demo.chooser:show()
  return demo
end

_G.macAutocompleteStyleDemo = demo
return demo.show()
