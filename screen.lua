-- What the preview shows and where it sits: window N's screen, and the
-- preview's own layer, held at its bounds.

local terminal = require("terminal")

local M = {}

local function own_layer(view, block)
  for _, w in ipairs(view.windows or {}) do
    for _, layer in ipairs(w.layers or {}) do
      for _, b in ipairs(layer.blocks or {}) do
        if b.block_id == block then return layer end
      end
    end
  end
end

-- Rex can't lock a floating layer's size, so a move or resize is undone.
function M.pin(view, block, bounds)
  local layer = own_layer(view, block)
  if not layer then return end
  for i, v in ipairs(bounds) do
    if math.abs(layer.bounds[i] - v) > 1e-4 then
      rex.session.resize_layer{ layer_id = layer.layer_id, bounds = bounds }
      return
    end
  end
end

-- Window n's screen as escape sequences, or "" if it has gone.
function M.capture(view, n)
  local w = (view.windows or {})[n]
  if not (w and w.focused_block_id) then return "" end
  local r = terminal.call(w.focused_block_id, "format", { format = "vt", trim = true })
  return r and r.content or ""
end

-- The size of block's terminal in columns and rows.
function M.size(block)
  local r = terminal.call(block, "size")
  if not r then return 80, 24 end
  return r.columns, r.rows
end

return M
