local M = {}
local sessions = {}
local defaults = { hijack = true, layout = 'horizontal', autosave = true }
local config = vim.deepcopy(defaults)
local setup_done = false
local saving = {}
local pending = {}

local function qf_window(win)
  if not vim.api.nvim_win_is_valid(win) then return false end
  local buf = vim.api.nvim_win_get_buf(win)
  return vim.bo[buf].buftype == 'quickfix'
end

local function open_window(buf, layout, replace_win)
  if replace_win and vim.api.nvim_win_is_valid(replace_win) then
    vim.api.nvim_win_set_buf(replace_win, buf)
    return replace_win
  end
  if layout == 'vertical' then
    vim.cmd('botright vsplit')
    vim.api.nvim_win_set_buf(0, buf)
  elseif layout == 'float' then
    local width = math.max(20, math.floor(vim.o.columns * 0.75))
    local height = math.max(3, math.floor(vim.o.lines * 0.6))
    local win = vim.api.nvim_open_win(buf, true, {
      relative = 'editor', style = 'minimal', border = 'rounded',
      width = width, height = height,
      row = math.max(0, math.floor((vim.o.lines - height) / 2)),
      col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    })
    return win
  else
    vim.cmd('botright split')
    vim.api.nvim_win_set_buf(0, buf)
  end
  return vim.api.nvim_get_current_win()
end

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

local function save(buf, quiet)
  local session = sessions[buf]
  if not session then return fail('unknown editor buffer') end
  if saving[buf] then return end
  if not vim.bo[buf].modified then return true end
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
  saving[buf] = true
  local result = vim.fn.setqflist({}, 'r', properties)
  saving[buf] = nil
  if result ~= 0 then return fail('failed to update the quickfix list') end

  local refreshed = current(session.id)
  if refreshed.id ~= session.id then return fail('quickfix list disappeared after saving') end
  session.tick = refreshed.changedtick
  session.items = vim.deepcopy(refreshed.items)
  session.lines = saved_lines
  vim.bo[buf].modified = false
  if not quiet then
    vim.notify(('qfedit: saved %d entries'):format(#output))
  end
  return true
end

local function queue_save(buf)
  if not config.autosave or pending[buf] or saving[buf] then return end
  pending[buf] = true
  vim.schedule(function()
    pending[buf] = nil
    if not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].modified then return end
    -- InsertLeave is emitted when typing stops; TextChanged captures dd, p,
    -- :sort, etc. Never write while the user is actively inserting text.
    local mode = vim.api.nvim_get_mode().mode
    if mode:sub(1, 1) == 'i' or mode:sub(1, 1) == 'R' then return end
    save(buf, true)
  end)
end

function M.open(opts)
  opts = opts or {}
  local layout = opts.layout or config.layout
  local replace_win = opts.replace_win
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
    open_window(existing, layout, replace_win)
    return existing
  end

  local buf = vim.api.nvim_create_buf(false, false)
  open_window(buf, layout, replace_win)
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
    callback = function() save(buf, false) end,
  })
  vim.api.nvim_create_autocmd({ 'TextChanged', 'InsertLeave' }, {
    buffer = buf,
    group = group,
    callback = function() queue_save(buf) end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    group = group,
    callback = function() sessions[buf] = nil; pending[buf] = nil end,
  })

  vim.keymap.set('n', '<CR>', function()
    local line = vim.api.nvim_get_current_line()
    if vim.trim(line) == '' then return end
    local item = parse(line)
    if not item then return end
    local target = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_get_config(target).relative ~= '' then
      vim.api.nvim_win_close(target, true)
    else
      vim.cmd('wincmd p')
    end
    vim.cmd('edit ' .. vim.fn.fnameescape(item.filename))
    local nlines = vim.api.nvim_buf_line_count(0)
    local row = math.max(1, math.min(item.lnum, nlines))
    local text = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ''
    local col = math.max(0, math.min(item.col - 1, #text))
    vim.api.nvim_win_set_cursor(0, { row, col })
  end, { buffer = buf, desc = 'Open quickfix entry' })
  return buf
end

function M.setup(opts)
  opts = opts or {}
  local merged = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts)
  assert(type(merged.hijack) == 'boolean', 'qfedit: hijack must be boolean')
  assert(type(merged.autosave) == 'boolean', 'qfedit: autosave must be boolean')
  assert(vim.tbl_contains({ 'horizontal', 'vertical', 'float' }, merged.layout),
    'qfedit: layout must be horizontal, vertical, or float')
  config = merged
  if setup_done then return end
  setup_done = true

  vim.api.nvim_create_user_command('QfEdit', function()
    M.open()
  end, { desc = 'Edit quickfix entries as a buffer' })

  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'qf',
    callback = function(args)
      if not config.hijack then return end
      local qf_buf = args.buf
      vim.schedule(function()
        if not config.hijack then return end
        -- Replace native :copen's window, rather than opening another split.
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_buf(win) == qf_buf and qf_window(win) then
            vim.api.nvim_win_call(win, function()
              M.open({ replace_win = win })
            end)
          end
        end
      end)
    end,
  })
end

return M
