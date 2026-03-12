<!-- ALL-CONTRIBUTORS-BADGE:START - Do not remove or modify this section -->
[![All Contributors](https://img.shields.io/badge/all_contributors-3-orange.svg?style=flat-square)](#contributors-)
<!-- ALL-CONTRIBUTORS-BADGE:END -->

> [!CAUTION]
> **Still in early development, will have breaking changes!**

# jira.nvim

A Neovim plugin for managing JIRA tasks with a beautiful UI.

<img width="3090" height="2102" alt="image" src="https://github.com/user-attachments/assets/e6e6c705-9d56-4963-95da-0aedec1ea76b" />


> [!NOTE]
> Disucssion: How do you want to create, edit the jira ticket in this plugin?
> https://github.com/letieu/jira.nvim/discussions/1

## Features

- 📋 View active sprint tasks
- 👥 Query tasks by custom JQL
- 📝 Read task as markdown
- 🔄 Change task status
- ⏱️ Log time on tasks
- 👤 Assign tasks
- 🎨 Git integration
- 🎨 Comment
- 🎨 Create, edit task
- ⏱️ Work report

---

## Install

### `lazy.nvim`

```lua
{
  "letieu/jira.nvim",
  opts = {
    -- Your setup options...
    jira = {
      limit = 200,                                -- Global limit of tasks per view (default: 200)
    },
  },
}
```

---

## Authentication

The plugin uses a command-based authentication system. Run the following command to log in:

```vim
:Jira auth login
```

You will be prompted for:
1. **Jira Base URL**: (e.g., `https://your-domain.atlassian.net`)
2. **Auth Type**: `basic` (default) or `pat`
3. **Email**: (Required for `basic`)
4. **API Token / PAT**: Your Jira API token or Personal Access Token

Credentials are securely stored in your Neovim data directory (`:Jira auth info` to see the exact path).

Other auth commands:
- `:Jira auth info`: Show current authentication status and file location.
- `:Jira auth logout`: Remove stored credentials.

---

## Configuration

```lua
require('jira').setup({
  -- Jira settings
  jira = {
    api_version = "3",                          -- API version: "2" or "3" (default: "3")
    limit = 200,                                -- Global limit of tasks per view (default: 200)
  },

  active_sprint_query = "project = '%s' AND sprint in openSprints() ORDER BY Rank ASC",

  -- Saved JQL queries for the JQL tab
  -- Use %s as a placeholder for the project key
  queries = {
    ["Next sprint"] = "project = '%s' AND sprint in futureSprints() ORDER BY Rank ASC",
    ["Backlog"] = "project = '%s' AND (issuetype IN standardIssueTypes() OR issuetype = Sub-task) AND (sprint IS EMPTY OR sprint NOT IN openSprints()) AND statusCategory != Done ORDER BY Rank ASC",
    ["My Tasks"] = "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC",
  },

  -- Project-specific overrides
  -- Still think about this config, maybe not good enough
  projects = {
    ["DEV"] = {
      story_point_field = "customfield_10035",      -- Custom field ID for story points
      custom_fields = { -- Custom field to display in markdown view
        { key = "customfield_10016", label = "Acceptance Criteria" }
      },
    }
  }
})
```

---

## Usage

Run the following command to open the Jira board:

```vim
" Authentication
:Jira auth login
:Jira auth info
:Jira auth logout

" Open board
:Jira <PROJECT_KEY>

" Open one task view (info)
:Jira info ISSUE_KEY

" Create new issue
:Jira create [PROJECT_KEY]

" Edit existing issue
:Jira edit ISSUE_KEY
```

If you don't provide a project key, you will be prompted to enter one.

### Keybindings

#### Help
- `H` — Show help

#### Navigation & View
- `<Tab>` — Toggle node (Expand / Collapse)
- `S`, `J`, `H` — Switch view (Sprint, JQL, Help)
- `q` — Close board
- `r` — Refresh current view

#### Issue Actions (In board)
- `i` — Create issue / sub-task (under cursor)
- `K` — Quick issue details (popup)
- `gd` — Read task as info
- `ge` — Edit task
- `gx` — Open task in browser
- `gs` — Update status
- `ga` — Change assignee
- `gw` — Add time
- `gb` — Checkout / create branch
- `go` — Show child issues (sub-tasks)

---

## Tips

- How to get custom field list -> go to `https://your-domain.atlassian.net/rest/api/3/field`

---

## Development

### Running Tests

```bash
make test
```

---

## TODO
- [x] Jira sprint board
- [x] Config
- [x] Expand, Collapse
- [x] Read task (Markdown)
- [x] Format time
- [x] Backlog (via JQL Dashboard)
- [x] Custom JQL & Saved Queries
- [x] Change status
- [x] Change assignee
- [x] Log time
- [x] Comment
- [x] Create, Edit task
- [ ] Bulk actions
- [ ] Update UI when terminal size change
...

---

## Thanks

Big thanks for `gemini` CLI free tier.

---

## License

MIT © Tieu Le

## Contributors ✨

Thanks goes to these wonderful people ([emoji key](https://allcontributors.org/docs/en/emoji-key)):

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://codeberg.org/DrKJeff16"><img src="https://avatars.githubusercontent.com/u/72052712?v=4?s=100" width="100px;" alt="Guennadi Maximov C"/><br /><sub><b>Guennadi Maximov C</b></sub></a><br /><a href="https://github.com/letieu/jira.nvim/commits?author=DrKJeff16" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://elsesiy.com"><img src="https://avatars.githubusercontent.com/u/7075075?v=4?s=100" width="100px;" alt="Jonas-Taha El Sesiy"/><br /><sub><b>Jonas-Taha El Sesiy</b></sub></a><br /><a href="https://github.com/letieu/jira.nvim/commits?author=elsesiy" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/bhedavivek"><img src="https://avatars.githubusercontent.com/u/12003668?v=4?s=100" width="100px;" alt="Vivek Bheda"/><br /><sub><b>Vivek Bheda</b></sub></a><br /><a href="https://github.com/letieu/jira.nvim/commits?author=bhedavivek" title="Code">💻</a></td>
    </tr>
  </tbody>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->

This project follows the [all-contributors](https://github.com/all-contributors/all-contributors) specification. Contributions of any kind welcome!
