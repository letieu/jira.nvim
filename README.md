# jira.nvim

A Neovim plugin for managing JIRA tasks with a beautiful UI powered by [volt](https://github.com/nvzone/volt).

## Features

- 📋 View active sprint tasks
- 👥 See who is assigned to each task
- ✅ Expand/collapse parent tasks to view subtasks
- 📝 View acceptance criteria
- 🔄 Change task status
- ⏱️  Log time on tasks
- 👤 Assign tasks to yourself
- 🎨 Beautiful UI with syntax highlighting

## Screenshots

*(MVP version with fake data for UI development)*

## Installation

**Requirements:**
- Neovim >= 0.9.0
- [volt](https://github.com/nvzone/volt) plugin

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "yourusername/jira.nvim",
  dependencies = "nvzone/volt",
  opts = {},
  cmd = { "Jira" },
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "yourusername/jira.nvim",
  requires = { "nvzone/volt" },
  config = function()
    require("jira").setup()
  end
}
```

## Configuration

```lua
require("jira").setup({
  auto_expand = true,          -- Auto expand first task on open
  show_story_points = true,    -- Show story points in task list
  highlight_my_tasks = true,   -- Highlight tasks assigned to you
  my_username = "john.doe",    -- Your JIRA username (for highlighting)
})
```

## Usage

### Commands

- `:Jira` - Open the JIRA sprint board
- `:JiraClose` - Close the JIRA window

### Keymaps (in JIRA window)

#### Navigation
- `j/k` - Move up/down
- `gg` - Go to top
- `G` - Go to bottom

#### Actions
- `<Enter>` - Toggle task expansion (sprint view) / Back to sprint (detail view)
- `d` - Show task detail with acceptance criteria
- `b` - Back to sprint view
- `s` - Change task status
- `t` - Log time on task
- `a` - Assign task to yourself
- `q` or `<Esc>` - Close window

### Workflow Example

1. Open JIRA board: `:Jira`
2. Navigate to a task with `j/k`
3. Press `<Enter>` to expand and see subtasks
4. Press `d` to view full task details and acceptance criteria
5. Press `s` to change status
6. Press `t` to log time
7. Press `a` to assign to yourself
8. Press `q` to close

## UI Components

### Sprint Board View
- Header showing sprint information
- Expandable task list with:
  - Task key and summary
  - Status badge (To Do, In Progress, In Review, Done)
  - Priority indicator
  - Story points
  - Assignee
  - Subtasks with indentation

### Task Detail View
- Task header with key and summary
- Status and assignee information
- Priority and story points
- Time spent
- Acceptance criteria list
- Subtasks overview

## Development

This is currently an MVP version using fake data for UI development. 

### File Structure

```
jira.nvim/
├── lua/
│   └── jira/
│       ├── init.lua           # Main entry point
│       ├── state.lua          # State management
│       ├── actions.lua        # User actions/interactions
│       ├── data/
│       │   └── fake.lua       # Fake data for MVP
│       └── ui/
│           ├── init.lua       # UI components
│           ├── layout.lua     # Layout definitions
│           └── hl.lua         # Highlight groups
├── plugin/
│   └── jira.lua              # Plugin commands
└── README.md
```

### Next Steps

- [ ] Integrate with JIRA API
- [ ] Add authentication
- [ ] Real-time data fetching
- [ ] Task creation/editing
- [ ] Comment viewing/adding
- [ ] Sprint selection
- [ ] Custom JQL queries
- [ ] Caching mechanism

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT

## Acknowledgements

- [volt](https://github.com/nvzone/volt) - Amazing UI library for Neovim
- [typr](https://github.com/nvzone/typr) - Reference for volt usage patterns
