# rex-tab-preview

Press `Cmd+P`, then a window number (1–9), to preview that window's screen in
a small read-only floating layer next to the tab list. Press Enter to switch
to that window, or Escape to close it. Nothing beyond Rex and macOS is needed.

## Install

Clone the repo anywhere; this uses `~/.config/rex/rex-tab-preview`:

```sh
git clone https://github.com/WorldOccupier/rex-tab-preview ~/.config/rex/rex-tab-preview
```

Then add to `~/.config/rex/init.lua`:

```lua
package.path = os.getenv("HOME") .. "/.config/rex/rex-tab-preview/?.lua;" .. package.path
require("preview").setup()        -- or setup("cmd+shift+p")
```

Then run `rex config reload`.

Rex has no tab-hover event and no layer styling API, so the preview is
key-triggered, its border is drawn with box characters, and its size is held
fixed by snapping it back if it's moved or resized. Closing a preview runs
the "Tab Preview Closed (internal)" action, which shows up in the command
palette; it does nothing when run by hand.

## Files

- `preview.lua`: keys, actions, and the preview's layer.
- `render.lua`: runs in the layer and draws the previewed window.
- `frame.lua`: the border, and fitting lines to the preview's width.
- `screen.lua`: captures the window and holds the layer in place.
- `terminal.lua`: calls to a terminal block's methods.
- `tabs.lua`: tab names, and the ◉ marker on the previewed tab.
- `sound.lua`: the pop played on Enter.

## Tests

```sh
rex do scripts/test_frame.lua
scripts/verify_events.sh
scripts/verify_missing_window.sh
```

The scripts use throwaway sessions and need the Rex server running.

## License

MIT. See `LICENSE`.
