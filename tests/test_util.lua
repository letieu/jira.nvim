local Helpers = dofile("tests/helpers.lua")

local child = Helpers.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    -- This will be executed before every (even nested) case
    pre_case = function()
      -- Restart child process with custom 'init.lua' script
      child.restart({ "-u", "scripts/minimal_init.lua" })
    end,
    -- This will be executed one after all tests from this set are finished
    post_once = child.stop,
  },
})

T["util"] = MiniTest.new_set()

T["util"]["format_time"] = MiniTest.new_set()

T["util"]["format_time"]["should return 0 for nil or <= 0"] = function()
  child.lua([[M = require("jira.common.util")]])
  MiniTest.expect.equality(child.lua_get([[M.format_time(nil)]]), "0")
  MiniTest.expect.equality(child.lua_get([[M.format_time(0)]]), "0")
  MiniTest.expect.equality(child.lua_get([[M.format_time(-10)]]), "0")
end

T["util"]["format_time"]["should format seconds to hours"] = function()
  child.lua([[M = require("jira.common.util")]])
  MiniTest.expect.equality(child.lua_get([[M.format_time(3600)]]), "1")
  MiniTest.expect.equality(child.lua_get([[M.format_time(7200)]]), "2")
end

T["util"]["format_time"]["should show one decimal place for non-integers"] = function()
  child.lua([[M = require("jira.common.util")]])
  MiniTest.expect.equality(child.lua_get([[M.format_time(1800)]]), "0.5")
  MiniTest.expect.equality(child.lua_get([[M.format_time(5400)]]), "1.5")
end

T["util"]["strim"] = function()
  child.lua([[M = require("jira.common.util")]])
  MiniTest.expect.equality(child.lua_get([[M.strim("  hello  ")]]), "hello")
  MiniTest.expect.equality(child.lua_get([[M.strim("\n hello world \t")]]), "hello world")
end

T["util"]["markdown_to_adf"] = MiniTest.new_set()

T["util"]["markdown_to_adf"]["should convert simple text to ADF"] = function()
  child.lua([[M = require("jira.common.util")]])
  child.lua([[adf = M.markdown_to_adf("hello world")]])
  MiniTest.expect.equality(child.lua_get([[adf.type]]), "doc")
  MiniTest.expect.equality(child.lua_get([[#adf.content]]), 1)
  MiniTest.expect.equality(child.lua_get([[adf.content[1].type]]), "paragraph")
  MiniTest.expect.equality(child.lua_get([[adf.content[1].content[1].text]]), "hello world")
end

T["util"]["markdown_to_adf"]["should handle bold text"] = function()
  child.lua([[M = require("jira.common.util")]])
  child.lua([[adf = M.markdown_to_adf("hello **world**")]])
  child.lua([[content = adf.content[1].content]])
  MiniTest.expect.equality(child.lua_get([[content[1].text]]), "hello ")
  MiniTest.expect.equality(child.lua_get([[content[2].text]]), "world")
  MiniTest.expect.equality(child.lua_get([[content[2].marks[1].type]]), "strong")
end

T["util"]["markdown_to_adf"]["should handle links"] = function()
  child.lua([[M = require("jira.common.util")]])
  child.lua([[adf = M.markdown_to_adf("[Google](https://google.com)")]])
  child.lua([[content = adf.content[1].content]])
  MiniTest.expect.equality(child.lua_get([[content[1].text]]), "Google")
  MiniTest.expect.equality(child.lua_get([[content[1].marks[1].type]]), "link")
  MiniTest.expect.equality(child.lua_get([[content[1].marks[1].attrs.href]]), "https://google.com")
end

T["util"]["markdown_to_adf"]["should handle multiple paragraphs"] = function()
  child.lua([[M = require("jira.common.util")]])
  child.lua([[adf = M.markdown_to_adf("p1\n\np2")]])
  MiniTest.expect.equality(child.lua_get([[#adf.content]]), 2)
  MiniTest.expect.equality(child.lua_get([[adf.content[1].content[1].text]]), "p1")
  MiniTest.expect.equality(child.lua_get([[adf.content[2].content[1].text]]), "p2")
end

T["util"]["build_issue_tree"] = MiniTest.new_set()

T["util"]["build_issue_tree"]["should handle flat list"] = function()
  child.lua([[M = require("jira.common.util")]])
  child.lua([[
    issues = {
      { key = "JIRA-1", summary = "Issue 1" },
      { key = "JIRA-2", summary = "Issue 2" },
    }
    tree = M.build_issue_tree(issues)
  ]])
  MiniTest.expect.equality(child.lua_get([[#tree]]), 2)
  MiniTest.expect.equality(child.lua_get([[tree[1].key]]), "JIRA-1")
  MiniTest.expect.equality(child.lua_get([[tree[2].key]]), "JIRA-2")
  MiniTest.expect.equality(child.lua_get([[#tree[1].children]]), 0)
  MiniTest.expect.equality(child.lua_get([[tree[1].expanded]]), true)
end

T["util"]["build_issue_tree"]["should handle parent-child relationship"] = function()
  child.lua([[M = require("jira.common.util")]])
  child.lua([[
    issues = {
      { key = "JIRA-1", summary = "Parent" },
      { key = "JIRA-2", summary = "Child", parent = "JIRA-1" },
    }
    tree = M.build_issue_tree(issues)
  ]])
  MiniTest.expect.equality(child.lua_get([[#tree]]), 1)
  MiniTest.expect.equality(child.lua_get([[tree[1].key]]), "JIRA-1")
  MiniTest.expect.equality(child.lua_get([[#tree[1].children]]), 1)
  MiniTest.expect.equality(child.lua_get([[tree[1].children[1].key]]), "JIRA-2")
end

T["util"]["build_issue_tree"]["should handle deep nesting"] = function()
  child.lua([[M = require("jira.common.util")]])
  child.lua([[
    issues = {
      { key = "JIRA-1", summary = "Grandparent" },
      { key = "JIRA-2", summary = "Parent", parent = "JIRA-1" },
      { key = "JIRA-3", summary = "Child", parent = "JIRA-2" },
    }
    tree = M.build_issue_tree(issues)
  ]])
  MiniTest.expect.equality(child.lua_get([[#tree]]), 1)
  MiniTest.expect.equality(child.lua_get([[tree[1].key]]), "JIRA-1")
  MiniTest.expect.equality(child.lua_get([[#tree[1].children]]), 1)
  MiniTest.expect.equality(child.lua_get([[tree[1].children[1].key]]), "JIRA-2")
  MiniTest.expect.equality(child.lua_get([[#tree[1].children[1].children]]), 1)
  MiniTest.expect.equality(child.lua_get([[tree[1].children[1].children[1].key]]), "JIRA-3")
end

T["util"]["build_issue_tree"]["should handle missing parent in list as root"] = function()
  child.lua([[M = require("jira.common.util")]])
  child.lua([[
    issues = {
      { key = "JIRA-2", summary = "Child with missing parent", parent = "JIRA-1" },
    }
    tree = M.build_issue_tree(issues)
  ]])
  MiniTest.expect.equality(child.lua_get([[#tree]]), 1)
  MiniTest.expect.equality(child.lua_get([[tree[1].key]]), "JIRA-2")
end

return T
