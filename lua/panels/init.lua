local Panels = {}

local events = { "BufWinEnter", "FileType", "TermOpen", "TabEnter", "WinNew" }

local edges = {
  left = { command = "H", rank = 1, resize = "vertical resize ", vertical = true },
  right = { command = "L", rank = 2, resize = "vertical resize ", vertical = true },
  bottom = { command = "J", rank = 3, resize = "resize " },
  top = { command = "K", rank = 4, resize = "resize " },
}

local state = {
  defaults = { focus = true, wait = 3000 },
  items = {},
  panels = {},
  positions = {},
  waiting = {},
}

local function is_normal_win(win)
  return win ~= 0 and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == ""
end

local function winbar_title(title)
  return "%<" .. title:gsub("%%", "%%%%")
end

local function configured_size(item)
  local size = item.spec.size or state.positions[item.spec.position]

  if not size then
    return
  end

  if size > 0 and size < 1 then
    local total = item.edge.vertical and vim.o.columns or vim.o.lines
    return math.max(1, math.floor(total * size))
  end

  return math.max(1, math.floor(size))
end

local function current_size(win, item)
  if item.edge.vertical then
    return vim.api.nvim_win_get_width(win)
  end

  return vim.api.nvim_win_get_height(win)
end

local function panel_size(win, item, configured)
  if not configured and vim.w[win].panels_id == item.id then
    return current_size(win, item)
  end

  return configured_size(item)
end

local function apply_options(win, item)
  local spec = item.spec
  local wo = spec.wo or {}
  local winbar = wo.winbar

  if winbar == false then
    winbar = ""
  elseif winbar == nil and spec.title then
    winbar = winbar_title(spec.title)
  end

  if winbar ~= nil then
    vim.api.nvim_set_option_value("winbar", winbar, { win = win })
  end

  for name, value in pairs(wo) do
    if name ~= "winbar" then
      vim.api.nvim_set_option_value(name, value, { win = win })
    end
  end
end

local function place(win, item, configured)
  local size = panel_size(win, item, configured)

  vim.api.nvim_win_call(win, function()
    vim.cmd.wincmd(item.edge.command)

    if size then
      vim.cmd(item.edge.resize .. size)
    end
  end)

  vim.w[win].panels_id = item.id
  apply_options(win, item)
end

local function matches(win, item)
  if not is_normal_win(win) then
    return false
  end

  local buf = vim.api.nvim_win_get_buf(win)
  local spec = item.spec

  if spec.ft ~= nil and spec.ft ~= vim.bo[buf].filetype then
    return false
  end

  return spec.filter == nil or spec.filter(buf, win)
end

local function arrange(configured)
  local wins = vim.api.nvim_tabpage_list_wins(0)

  for _, item in ipairs(state.items) do
    for _, win in ipairs(wins) do
      if matches(win, item) then
        place(win, item, configured)
      end
    end
  end
end

local function find_win(id, tabpage)
  local item = state.panels[id]

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    if matches(win, item) then
      return win
    end
  end
end

local function check_waiting()
  for id, tabpage in pairs(state.waiting) do
    if not vim.api.nvim_tabpage_is_valid(tabpage) then
      state.waiting[id] = nil
    elseif vim.api.nvim_get_current_tabpage() == tabpage then
      local win = find_win(id, tabpage)

      if win then
        vim.api.nvim_set_current_win(win)
        state.waiting[id] = nil
      end
    end
  end
end

local function schedule()
  vim.schedule(function()
    arrange()
    check_waiting()
  end)
end

local function wait_for(id, tabpage, timeout)
  if timeout <= 0 then
    return
  end

  state.waiting[id] = tabpage

  vim.defer_fn(function()
    if state.waiting[id] == tabpage then
      state.waiting[id] = nil
    end
  end, timeout)

  schedule()
end

local function build_registry(panels)
  state.items = {}
  state.panels = {}

  for id, spec in pairs(panels) do
    local edge = edges[spec.position]

    if not edge then
      error("invalid panel position for " .. id .. ": " .. tostring(spec.position))
    end

    local item = { edge = edge, id = id, spec = spec }

    state.items[#state.items + 1] = item
    state.panels[id] = item
  end

  table.sort(state.items, function(a, b)
    if a.edge.rank == b.edge.rank then
      return a.id < b.id
    end

    return a.edge.rank < b.edge.rank
  end)
end

function Panels.setup(config)
  config = config or {}

  state.defaults = vim.tbl_extend("force", { focus = true, wait = 3000 }, config.defaults or {})
  state.positions = config.positions or {}
  state.waiting = {}
  build_registry(config.panels or {})

  vim.api.nvim_create_autocmd(events, {
    group = vim.api.nvim_create_augroup("PanelsNvim", { clear = true }),
    callback = schedule,
  })

  schedule()
end

function Panels.open(id, opener, opts, ...)
  local item = state.panels[id]

  if not item then
    error("unknown panel: " .. id)
  end

  opts = vim.tbl_extend("force", state.defaults, opts or {})

  local tabpage = vim.api.nvim_get_current_tabpage()
  local win = find_win(id, tabpage)

  if win then
    if opts.focus ~= false then
      vim.api.nvim_set_current_win(win)
    end

    return
  end

  local previous = vim.api.nvim_get_current_win()
  local result

  if type(opener) == "string" then
    result = vim.cmd(opener)
  else
    result = opener(...)
  end

  arrange()
  win = find_win(id, tabpage)

  if opts.focus == false then
    if vim.api.nvim_win_is_valid(previous) then
      vim.api.nvim_set_current_win(previous)
    end

    return result
  end

  if win then
    vim.api.nvim_set_current_win(win)
  else
    wait_for(id, tabpage, opts.wait)
  end

  return result
end

function Panels.equalize()
  vim.cmd.wincmd("=")
  arrange(true)
end

return Panels
