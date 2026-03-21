local builtin = require('telescope.builtin')
local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local conf = require('telescope.config').values

require('telescope').setup({
  defaults = {
    previewer = false,
    layout_config = {
      height = 0.4,
    },
  },
})

-- MRU tab tracking
local tab_mru = {}

local tab_mru_group = vim.api.nvim_create_augroup('telescope_tab_mru', { clear = true })
vim.api.nvim_create_autocmd('TabEnter', {
  group = tab_mru_group,
  callback = function()
    tab_mru[vim.api.nvim_get_current_tabpage()] = vim.loop.now()
  end,
})
vim.api.nvim_create_autocmd('TabClosed', {
  group = tab_mru_group,
  callback = function()
    -- Clean up stale entries
    local valid = {}
    for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
      valid[tp] = true
    end
    for tp, _ in pairs(tab_mru) do
      if not valid[tp] then
        tab_mru[tp] = nil
      end
    end
  end,
})

-- Switch tabs picker (sorted by MRU, showing pwd)
local function switch_tab(opts)
  opts = opts or {}
  local tabs = {}
  for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
    local tabnr = vim.api.nvim_tabpage_get_number(tp)
    local cwd = vim.fn.getcwd(-1, tabnr)
    local name = vim.fn.fnamemodify(cwd, ':t')
    local path = vim.fn.fnamemodify(cwd, ':p:~')
    local mru_time = tab_mru[tp] or 0
    table.insert(tabs, { tp = tp, tabnr = tabnr, name = name, path = path, mru_time = mru_time })
  end

  -- Sort by MRU, with current tab moved to the end so the
  -- second-most-recent tab is pre-selected (quick alt-tab behavior)
  table.sort(tabs, function(a, b) return a.mru_time > b.mru_time end)
  local current_tp = vim.api.nvim_get_current_tabpage()
  local current_idx = nil
  for i, tab in ipairs(tabs) do
    if tab.tp == current_tp then
      current_idx = i
      break
    end
  end
  if current_idx then
    local current = table.remove(tabs, current_idx)
    table.insert(tabs, current)
  end

  pickers.new(opts, {
    prompt_title = 'Tabs',
    finder = finders.new_table({
      results = tabs,
      entry_maker = function(tab)
        local display = string.format('[%d] %s  %s', tab.tabnr, tab.name, tab.path)
        return {
          value = tab,
          display = display,
          ordinal = tab.name .. ' ' .. tab.path,
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        vim.cmd(entry.value.tabnr .. 'tabnext')
      end)
      return true
    end,
  }):find()
end

-- Switch project picker (scans workspace dirs for git repos)
local function switch_project(workspaces, max_depth)
  max_depth = max_depth or 3

  local function find_projects(dirs, depth)
    if #dirs == 0 then return {} end
    local projects = {}
    local non_projects = {}
    for _, dir in ipairs(dirs) do
      local entries = vim.fn.globpath(dir, '*/', true, true)
      for _, entry in ipairs(entries) do
        -- Remove trailing slash
        entry = entry:gsub('/$', '')
        local has_git = vim.fn.isdirectory(entry .. '/.git') == 1
            or vim.fn.filereadable(entry .. '/.git') == 1
        if has_git or depth >= max_depth then
          table.insert(projects, entry)
        else
          table.insert(non_projects, entry)
        end
      end
    end
    local sub_projects = find_projects(non_projects, depth + 1)
    for _, p in ipairs(sub_projects) do
      table.insert(projects, p)
    end
    return projects
  end

  -- Expand ~ in workspace paths
  local expanded = {}
  for _, ws in ipairs(workspaces) do
    table.insert(expanded, vim.fn.expand(ws))
  end

  local projects = find_projects(expanded, 1)

  pickers.new({}, {
    prompt_title = 'Switch Project',
    finder = finders.new_table({
      results = projects,
      entry_maker = function(project)
        local name = vim.fn.fnamemodify(project, ':t')
        local path = vim.fn.fnamemodify(project, ':p:~')
        return {
          value = project,
          display = name .. '  ' .. path,
          ordinal = name .. ' ' .. path,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        vim.cmd('tabnew')
        vim.cmd('tcd ' .. vim.fn.fnameescape(entry.value))
        vim.cmd('CreateGitTerminalBuffer')
        vim.cmd('vsp')
        vim.cmd('CreateClaudeTerminalBuffer')
      end)
      return true
    end,
  }):find()
end

-- Keymaps
vim.keymap.set('n', '<leader>f', builtin.git_files, {})
vim.keymap.set('n', '<leader>tt', builtin.find_files, {})
vim.keymap.set('n', '<leader>bb', function()
  builtin.buffers({
    sort_mru = true,
    ignore_current_buffer = true,
    entry_maker = function(entry)
      local bufnr = entry.bufnr
      local display
      if vim.bo[bufnr].buftype == 'terminal' then
        local display_name = vim.b[bufnr].display_name or ''
        local term_title = vim.b[bufnr].term_title or ''
        if display_name ~= '' then
          display = '[' .. display_name .. '] ' .. term_title
        else
          display = term_title
        end
      else
        local name = vim.api.nvim_buf_get_name(bufnr)
        if name == '' then
          display = '[No Name]'
        else
          display = vim.fn.fnamemodify(name, ':~:.')
        end
      end

      return {
        value = entry,
        ordinal = display,
        display = display,
        bufnr = bufnr,
        filename = vim.api.nvim_buf_get_name(bufnr),
        lnum = entry.info and entry.info.lnum or 1,
      }
    end,
  })
end, {})
vim.keymap.set('n', '<leader>c', builtin.command_history, {})
vim.keymap.set('n', '<leader>gt', switch_tab, {})
vim.keymap.set('n', '<leader>gp', function() switch_project({ '~/worktrees' }, 3) end, {})
