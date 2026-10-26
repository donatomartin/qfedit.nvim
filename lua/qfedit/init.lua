local M = {}
local sessions = {}

local function fail(message)
  vim.notify('qfedit: ' .. message, vim.log.levels.ERROR)
end

local function path_for(item)
  if not item.bufnr or item.bufnr == 0 then return '' end
  local name = vim.api.nvim_buf_get_name(item.bufnr)
  if name == '' then return '' end
  return vim.fn.fnamemodify(name, ':p')
end

local function render(item)
  local path = path_for(item)
  local pos = ''
  if (item.lnum or 0) > 0 then
    pos = ':' .. item.lnum
    if (item.col or 0) > 0 then pos = pos .. ':' .. item.col end
  end
  local message = (item.text or ''):gsub('[\r\n]+', ' ')
  if message ~= '' then return path .. pos .. ' | ' .. message end
  return path .. pos
end

local function parse(line)
  local lhs, message = line:match('^(.-) | (.*)$')
  if not lhs then lhs, message = line, '' end
  lhs = vim.trim(lhs)
  local path, lnum, col = lhs:match('^(.*):(%d+):(%d+)$')
  if not path then path, lnum = lhs:match('^(.*):(%d+)$') end
  if not path then path = lhs end
  if path == '' then return nil, 'missing filename: ' .. line end
  return {
    filename = path,
    lnum = tonumber(lnum) or 1,
    col = tonumber(col) or 1,
    text = message,
    valid = 1,
  }
end

local function current(id)
  return vim.fn.getqflist({ id = id, items = 1, changedtick = 1, title = 1, idx = 1 })
end

local function save(buf)
  local session = sessions[buf]
  if not session then return fail('unknown editor buffer') end
  local list = current(session.id)
  if list.id ~= session.id then return fail('the original quickfix list no longer exists') end
  if list.changedtick ~= session.tick then
    return fail('quickfix list changed externally; use :QfEdit to reopen it (your edits were NOT overwritten)')
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local pools = {}
  for i, original in ipairs(session.lines) do
    pools[original] = pools[original] or {}
    table.insert(pools[original], vim.deepcopy(session.items[i]))
  end

  local output = {}
  local saved_lines = {}
  for _, line in ipairs(lines) do
    if vim.trim(line) ~= '' then
      local pool = pools[line]
      local item
      if pool and #pool > 0 then
        item = table.remove(pool, 1)
      else
        local err
        item, err = parse(line)
        if not item then return fail(err) end
      end
      table.insert(output, item)
      table.insert(saved_lines, line)
    end
  end

  -- Replace the ORIGINAL quickfix list by ID rather than implicitly changing
  -- whichever list happens to be active after opening this buffer.
  local properties = { id = session.id, items = output, title = list.title }
  if #output > 0 then properties.idx = math.max(1, math.min(list.idx, #output)) end
  local result = vim.fn.setqflist({}, 'r', properties)
  if result ~= 0 then return fail('failed to update the quickfix list') end

  local refreshed = current(session.id)
  if refreshed.id ~= session.id then return fail('quickfix list disappeared after saving') end
  session.tick = refreshed.changedtick
  session.items = vim.deepcopy(refreshed.items)
  session.lines = saved_lines
  vim.bo[buf].modified = false
  vim.notify(('qfedit: saved %d entries'):format(#output))
end

function M.open()
  local qf = vim.fn.getqflist({ id = 0, items = 1, changedtick = 1, title = 1 })
  if not qf.id or qf.id == 0 then return fail('no current quickfix list') end

  local existing
  for buf, session in pairs(sessions) do
    if session.id == qf.id and vim.api.nvim_buf_is_valid(buf) then
      existing = buf
      break
    end
  end
  if existing then
    vim.cmd('botright split')
    vim.api.nvim_win_set_buf(0, existing)
    return
  end

  vim.cmd('botright new')
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'qfedit'
  vim.api.nvim_buf_set_name(buf, ('qfedit://%d'):format(qf.id))

  local lines = {}
  for _, item in ipairs(qf.items) do table.insert(lines, render(item)) end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false

  sessions[buf] = {
    id = qf.id,
    tick = qf.changedtick,
    items = vim.deepcopy(qf.items),
    lines = vim.deepcopy(lines),
  }

  local group = vim.api.nvim_create_augroup('QfEdit_' .. buf, { clear = true })
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    group = group,
    callback = function() save(buf) end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    group = group,
    callback = function() sessions[buf] = nil end,
  })

  vim.keymap.set('n', '<CR>', function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local line = vim.api.nvim_get_current_line()
    if vim.trim(line) == '' then return end
    local path, lnum, col = line:match('^(.*):(%d+):(%d+)')
    if not path then path, lnum = line:match('^(.*):(%d+)') end
    if not path then path = line:match('^(.-) | ') or line end
    path = vim.trim(path)
    if path == '' then return end
    vim.cmd('wincmd p')
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
    vim.api.nvim_win_set_cursor(0, { tonumber(lnum) or 1, math.max(0, (tonumber(col) or 1) - 1) })
  end, { buffer = buf, desc = 'Open quickfix entry' })
end

function M.setup()
  vim.api.nvim_create_user_command('QfEdit', M.open, { desc = 'Edit quickfix entries as a buffer' })
end

return M
