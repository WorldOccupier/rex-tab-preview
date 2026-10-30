-- Calls to a terminal block's methods, which fail once the block has gone.

local M = {}

M.FLAVOR = "com.superlogical.terminal"

-- The result of block's method, or nil if the call failed.
function M.call(block, method, params)
  if not block then return nil end
  params = params or {}
  params.block_id = block
  local ok, r = pcall(rex.block.call, M.FLAVOR, method, params)
  return ok and r or nil
end

return M
