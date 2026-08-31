local Helpers = dofile("tests/helpers.lua")

local child = Helpers.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
    end,
    post_once = child.stop,
  },
})

T["version"] = MiniTest.new_set()

T["version"]["get_api_version"] = MiniTest.new_set()

T["version"]["get_api_version"]["should default to '3' when config is not set"] = function()
  child.lua([[
    local config = require("jira.common.config")
    config.setup({})
    local version = require("jira.jira-api.version")
    _G.ver = version.get_api_version()
    _G.is_v2 = version.is_v2()
  ]])
  MiniTest.expect.equality(child.lua_get([[_G.ver]]), "3")
  MiniTest.expect.equality(child.lua_get([[_G.is_v2]]), false)
end

T["version"]["get_api_version"]["should support string '2', integer 2, and 'v2'"] = function()
  child.lua([[
    local config = require("jira.common.config")
    local version = require("jira.jira-api.version")

    config.setup({ jira = { api_version = "2" } })
    _G.res_str = version.get_api_version()
    _G.is_v2_str = version.is_v2()

    config.setup({ jira = { api_version = 2 } })
    _G.res_num = version.get_api_version()
    _G.is_v2_num = version.is_v2()

    config.setup({ jira = { api_version = "v2" } })
    _G.res_v = version.get_api_version()
    _G.is_v2_v = version.is_v2()
  ]])
  MiniTest.expect.equality(child.lua_get([[_G.res_str]]), "2")
  MiniTest.expect.equality(child.lua_get([[_G.is_v2_str]]), true)
  MiniTest.expect.equality(child.lua_get([[_G.res_num]]), "2")
  MiniTest.expect.equality(child.lua_get([[_G.is_v2_num]]), true)
  MiniTest.expect.equality(child.lua_get([[_G.res_v]]), "2")
  MiniTest.expect.equality(child.lua_get([[_G.is_v2_v]]), true)
end

T["version"]["get_api_version"]["should support string '3', integer 3, and 'v3'"] = function()
  child.lua([[
    local config = require("jira.common.config")
    local version = require("jira.jira-api.version")

    config.setup({ jira = { api_version = "3" } })
    _G.res_str = version.get_api_version()
    _G.is_v2_str = version.is_v2()

    config.setup({ jira = { api_version = 3 } })
    _G.res_num = version.get_api_version()
    _G.is_v2_num = version.is_v2()

    config.setup({ jira = { api_version = "v3" } })
    _G.res_v = version.get_api_version()
    _G.is_v2_v = version.is_v2()
  ]])
  MiniTest.expect.equality(child.lua_get([[_G.res_str]]), "3")
  MiniTest.expect.equality(child.lua_get([[_G.is_v2_str]]), false)
  MiniTest.expect.equality(child.lua_get([[_G.res_num]]), "3")
  MiniTest.expect.equality(child.lua_get([[_G.is_v2_num]]), false)
  MiniTest.expect.equality(child.lua_get([[_G.res_v]]), "3")
  MiniTest.expect.equality(child.lua_get([[_G.is_v2_v]]), false)
end
T["version"]["get_api_version"]["should support JIRA_API_VERSION env variable"] = function()
  child.lua([[
    local config = require("jira.common.config")
    local version = require("jira.jira-api.version")
    local auth = require("jira.common.auth")

    auth.logout()
    config.setup({})
    vim.fn.setenv("JIRA_API_VERSION", "2")
    _G.res_env = version.get_api_version()
    _G.is_v2_env = version.is_v2()
    vim.fn.setenv("JIRA_API_VERSION", nil)
  ]])
  MiniTest.expect.equality(child.lua_get([[_G.res_env]]), "2")
  MiniTest.expect.equality(child.lua_get([[_G.is_v2_env]]), true)
end

T["version"]["endpoints"] = MiniTest.new_set()

T["version"]["endpoints"]["should return correct api path and search endpoint"] = function()
  child.lua([[
    local config = require("jira.common.config")
    local version = require("jira.jira-api.version")

    config.setup({ jira = { api_version = "2" } })
    _G.path_v2 = version.get_api_path()
    _G.search_v2 = version.get_search_endpoint()

    config.setup({ jira = { api_version = "3" } })
    _G.path_v3 = version.get_api_path()
    _G.search_v3 = version.get_search_endpoint()
  ]])
  MiniTest.expect.equality(child.lua_get([[_G.path_v2]]), "/rest/api/2")
  MiniTest.expect.equality(child.lua_get([[_G.search_v2]]), "/rest/api/2/search")
  MiniTest.expect.equality(child.lua_get([[_G.path_v3]]), "/rest/api/3")
  MiniTest.expect.equality(child.lua_get([[_G.search_v3]]), "/rest/api/3/search/jql")
end

T["version"]["transform_search_data"] = MiniTest.new_set()

T["version"]["transform_search_data"]["should build startAt for v2 and nextPageToken for v3"] = function()
  child.lua([[
    local config = require("jira.common.config")
    local version = require("jira.jira-api.version")

    config.setup({ jira = { api_version = "2" } })
    _G.data_v2 = version.transform_search_data("project = FOO", "50", 100, { "summary" })
    _G.data_v2_empty = version.transform_search_data("project = FOO", nil, nil, { "summary" })

    config.setup({ jira = { api_version = "3" } })
    _G.data_v3 = version.transform_search_data("project = FOO", "token123", 100, { "summary" })
  ]])
  MiniTest.expect.equality(child.lua_get([[_G.data_v2.startAt]]), 50)
  MiniTest.expect.equality(child.lua_get([[_G.data_v2.maxResults]]), 100)
  MiniTest.expect.equality(child.lua_get([[_G.data_v2_empty.startAt]]), 0)
  MiniTest.expect.equality(child.lua_get([[_G.data_v2_empty.maxResults]]), 100)
  MiniTest.expect.equality(child.lua_get([[_G.data_v3.nextPageToken]]), "token123")
  MiniTest.expect.equality(child.lua_get([[_G.data_v3.maxResults]]), 100)
end

T["version"]["transform_search_response"] = MiniTest.new_set()

T["version"]["transform_search_response"]["should calculate nextPageToken for v2 when more results exist"] = function()
  child.lua([[
    local config = require("jira.common.config")
    local version = require("jira.jira-api.version")
    config.setup({ jira = { api_version = "2" } })

    local res = {
      startAt = 0,
      maxResults = 50,
      total = 120,
      issues = { { key = "PROJ-1" }, { key = "PROJ-2" } },
    }
    _G.transformed = version.transform_search_response(res)
  ]])
  MiniTest.expect.equality(child.lua_get([[_G.transformed.nextPageToken]]), "50")
  MiniTest.expect.equality(child.lua_get([[#_G.transformed.issues]]), 2)
end

T["version"]["transform_search_response"]["should set nextPageToken to nil when on last page in v2"] = function()
  child.lua([[
    local config = require("jira.common.config")
    local version = require("jira.jira-api.version")
    config.setup({ jira = { api_version = "2" } })

    local res = {
      startAt = 100,
      maxResults = 50,
      total = 120,
      issues = { { key = "PROJ-101" } },
    }
    _G.transformed = version.transform_search_response(res)
  ]])
  MiniTest.expect.equality(child.lua_get([[_G.transformed.nextPageToken == nil]]), true)
  MiniTest.expect.equality(child.lua_get([[#_G.transformed.issues]]), 1)
end

T["version"]["transform_search_response"]["should safely handle nil startAt/maxResults/total without arithmetic error"] = function()
  child.lua([[
    local config = require("jira.common.config")
    local version = require("jira.jira-api.version")
    config.setup({ jira = { api_version = "2" } })

    -- Error response from Jira
    local error_res = {
      errorMessages = { "The value 'openSprints()' does not exist for the field 'sprint'." },
      errors = {},
    }
    _G.transformed_err = version.transform_search_response(error_res)

    -- Nil / unexpected input
    _G.transformed_nil = version.transform_search_response(nil)
    _G.transformed_empty = version.transform_search_response({})
  ]])
  MiniTest.expect.equality(child.lua_get([[_G.transformed_err.nextPageToken == nil]]), true)
  MiniTest.expect.equality(child.lua_get([[#_G.transformed_err.issues]]), 0)
  MiniTest.expect.equality(child.lua_get([[_G.transformed_nil.nextPageToken == nil]]), true)
  MiniTest.expect.equality(child.lua_get([[#_G.transformed_nil.issues]]), 0)
  MiniTest.expect.equality(child.lua_get([[_G.transformed_empty.nextPageToken == nil]]), true)
  MiniTest.expect.equality(child.lua_get([[#_G.transformed_empty.issues]]), 0)
end

T["version"]["transform_comment_data"] = MiniTest.new_set()

T["version"]["transform_comment_data"]["should return plain text for v2 and ADF for v3"] = function()
  child.lua([[
    local config = require("jira.common.config")
    local version = require("jira.jira-api.version")

    config.setup({ jira = { api_version = "2" } })
    _G.comment_v2 = version.transform_comment_data("hello world")

    config.setup({ jira = { api_version = "3" } })
    _G.comment_v3 = version.transform_comment_data("hello world")
  ]])
  MiniTest.expect.equality(child.lua_get([[_G.comment_v2.body]]), "hello world")
  MiniTest.expect.equality(child.lua_get([[_G.comment_v3.body.type]]), "doc")
end

return T
