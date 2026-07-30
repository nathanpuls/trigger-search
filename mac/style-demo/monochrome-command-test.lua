-- Focused style test: no visible leading icon, monochrome content,
-- and a muted purple accent used only for the Command-E edit shortcut.
-- This is visual-only and does not load or change the working autocomplete.

local demo = {}

local colors = {
  primary = { hex = "#2F3437" },
  secondary = { hex = "#7A8288" },
  command = { hex = "#7656B5" },
}

local primaryFont = { name = "Avenir Next Medium", size = 16 }
local secondaryFont = { name = "Avenir Next", size = 11 }
local commandFont = { name = "Avenir Next Demi Bold", size = 11 }

local function title(value)
  return hs.styledtext.new(value, {
    font = primaryFont,
    color = colors.primary,
  })
end

local function details(value)
  local result = hs.styledtext.new(value, {
    font = secondaryFont,
    color = colors.secondary,
  })
  local starts, ends = result:find("⌘E", 1, true)
  if starts then
    result = result:setStyle({
      font = commandFont,
      color = colors.command,
    }, starts, ends)
  end
  return result
end

-- Render Hammerspoon's native circular action arrow at reduced opacity. The
-- snapshot remains gray when selected rather than taking the bright blue tint.
local sourceIcon = hs.image.imageFromName("NSFollowLinkFreestandingTemplate")
local iconCanvas = hs.canvas.new({ x = 0, y = 0, w = 26, h = 26 })
iconCanvas[1] = {
  type = "image",
  image = sourceIcon,
  imageAlpha = 0.42,
  imageScaling = "scaleProportionally",
  frame = { x = 0, y = 0, w = 26, h = 26 },
}
local mutedActionIcon = iconCanvas:imageFromCanvas():template(false)
iconCanvas:delete()

local function choice(label, subText)
  return {
    text = title(label),
    subText = details(subText),
    image = mutedActionIcon,
    styleName = label,
  }
end

local choices = {
  choice("Atomoxetine  ›",
    "Psychiatric Medications  •  6 details  •  ⌘E Edit"),
  choice("Hydroxyzine  ›",
    "Psychiatric Medications  •  1 detail  •  ⌘E Edit"),
  choice("Sertraline  ›",
    "Psychiatric Medications  •  1 detail  •  ⌘E Edit"),
  choice("Mailing address",
    "Personal  •  2507 Pine Bend Dr, Kingwood, TX 77339  •  ⌘E Edit"),
  choice("Meeting link",
    "Personal  •  meet.google.com  •  ⌘E Edit"),
}

demo.chooser = hs.chooser.new(function(selected)
  if selected then hs.alert.show("Visual test only: " .. selected.styleName) end
end)
  :placeholderText("Monochrome with purple edit commands — visual test only")
  :choices(choices)
  :rows(5)
  :width(46)
  :bgDark(false)

function demo.show()
  demo.chooser:show()
  return demo
end

_G.macAutocompleteMonochromeDemo = demo
return demo.show()
