# Mac autocomplete style demo

This is a standalone visual sampler. It does not modify or load the working
autocomplete, its cache, or `~/.hammerspoon/init.lua`.

It demonstrates:

- replacement system icons
- Hammerspoon's default arrow when no replacement image is supplied
- different font families, sizes, and weights
- per-row title and secondary-text colors
- a light chooser background
- a different chooser width and row count

Copy the repository locally and run it while Hammerspoon is open. From the
repository root:

```sh
hs -c 'dofile("'"$(pwd)"'/mac/style-demo/style-demo.lua")'
```

Close it with Escape. Selecting a sample only displays the sample's name; it
does not paste anything.

The native chooser does not expose arbitrary window background colors,
alternating row colors, row separators, row padding, or selection-highlight
colors. Those would require replacing `hs.chooser` with a custom interface.

## Focused monochrome test

`monochrome-command-test.lua` demonstrates the proposed restrained treatment:

- no visible leading icon
- black labels and gray context
- a disclosure mark only for rows with nested details
- purple applied only to the `⌘E` edit shortcut
- native right-aligned `⌘1` through `⌘5` shortcuts
