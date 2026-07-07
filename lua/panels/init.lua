local Panels = {}

local events = { "BufWinEnter", "FileType", "TermOpen", "TabEnter", "WinNew" }

local edges = {
  bottom = { command = "J", resize = "resize " },
  top = { command = "K", resize = "resize " },
  left = { command = "H", resize = "vertical resize ", vertical = true },
  right = { command = "L", resize = "vertical resize ", vertical = true },
}

local edge_order = { "bottom", "top", "left", "right" }

local default_config = {
  defaults = { focus = true, wait = 3000 },
  layers = edge_order,
  positions = {
    left = 0.25,
    right = 0.25,
    bottom = 12,
    top = 10,
  },
  panels = {},
}

local state = {
  config = {},
  items = {},
  layer_ranks = {},
  panels = {},
  waiting = {},
}

local function is_normal_win(win)
  return win ~= 0 and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == ""
end

local function winbar_title(title)
  return "%<" .. title:gsub("%%", "%%%%")
end

local function configured_size(item)
  local size = item.spec.size or state.config.positions[item.spec.position]

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

local function resize(win, item, size)
  if size then
    vim.api.nvim_win_call(win, function()
      vim.cmd(item.edge.resize .. size)
    end)
  end
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
  end)

  resize(win, item, size)
  vim.w[win].panels_id = item.id
  apply_options(win, item)
end

local function place_group(group, configured)
  local anchor = group[1]
  local sizes = {}

  for index, entry in ipairs(group) do
    sizes[index] = panel_size(entry.win, entry.item, configured)
  end

  place(anchor.win, anchor.item, configured)

  for index = 2, #group do
    local entry = group[index]

    vim.fn.win_splitmove(entry.win, anchor.win, {
      rightbelow = true,
      vertical = not entry.item.edge.vertical,
    })

    vim.w[entry.win].panels_id = entry.item.id
    apply_options(entry.win, entry.item)
  end

  for index, entry in ipairs(group) do
    resize(entry.win, entry.item, sizes[index])
  end
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
  local groups = {}
  local positions = {}

  for _, item in ipairs(state.items) do
    for _, win in ipairs(wins) do
      if matches(win, item) then
        local position = item.spec.position

        if not groups[position] then
          groups[position] = {}
          positions[#positions + 1] = position
        end

        table.insert(groups[position], { item = item, win = win })
      end
    end
  end

  for _, position in ipairs(positions) do
    place_group(groups[position], configured)
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

local function build_layer_ranks(layers)
  local ranks = {}
  local rank = 0

  for _, position in ipairs(layers) do
    if not edges[position] then
      error("invalid panel layer: " .. tostring(position))
    end

    if not ranks[position] then
      rank = rank + 1
      ranks[position] = rank
    end
  end

  for _, position in ipairs(edge_order) do
    if not ranks[position] then
      rank = rank + 1
      ranks[position] = rank
    end
  end

  return ranks
end

local function build_registry(panels)
  state.items = {}
  state.panels = {}

  for id, spec in pairs(panels) do
    local edge = edges[spec.position]

    if not edge then
      error("invalid panel position for " .. id .. ": " .. tostring(spec.position))
    end

    local item = { edge = edge, id = id, rank = state.layer_ranks[spec.position], spec = spec }

    state.items[#state.items + 1] = item
    state.panels[id] = item
  end

  table.sort(state.items, function(a, b)
    if a.rank == b.rank then
      return a.id < b.id
    end

    return a.rank < b.rank
  end)
end

function Panels.setup(config)
  state.config = vim.tbl_deep_extend("force", default_config, config or {})

  state.layer_ranks = build_layer_ranks(state.config.layers)
  state.waiting = {}
  build_registry(state.config.panels)

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

  opts = vim.tbl_extend("force", state.config.defaults, opts or {})

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
