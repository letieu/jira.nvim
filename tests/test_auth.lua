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

T["auth"] = MiniTest.new_set()

T["auth"]["is_bearer"] = MiniTest.new_set()

T["auth"]["is_bearer"]["should return true for bearer, pat, and token case-insensitively"] = function()
  child.lua([[
    local auth = require("jira.common.auth")
    _G.is_pat = auth.is_bearer("pat")
    _G.is_PAT = auth.is_bearer("PAT")
    _G.is_bearer = auth.is_bearer("bearer")
    _G.is_Bearer = auth.is_bearer("Bearer")
    _G.is_BEARER = auth.is_bearer("BEARER")
    _G.is_token = auth.is_bearer("token")
    _G.is_basic = auth.is_bearer("basic")
    _G.is_BASIC = auth.is_bearer("BASIC")
    _G.is_nil = auth.is_bearer(nil)
    _G.is_empty = auth.is_bearer("")
  ]])
  MiniTest.expect.equality(child.lua_get([[_G.is_pat]]), true)
  MiniTest.expect.equality(child.lua_get([[_G.is_PAT]]), true)
  MiniTest.expect.equality(child.lua_get([[_G.is_bearer]]), true)
  MiniTest.expect.equality(child.lua_get([[_G.is_Bearer]]), true)
  MiniTest.expect.equality(child.lua_get([[_G.is_BEARER]]), true)
  MiniTest.expect.equality(child.lua_get([[_G.is_token]]), true)
  MiniTest.expect.equality(child.lua_get([[_G.is_basic]]), false)
  MiniTest.expect.equality(child.lua_get([[_G.is_BASIC]]), false)
  MiniTest.expect.equality(child.lua_get([[_G.is_nil]]), false)
  MiniTest.expect.equality(child.lua_get([[_G.is_empty]]), false)
end

T["auth"]["get_auth"] = MiniTest.new_set()

T["auth"]["get_auth"]["should fallback to config.options.jira when auth file does not exist"] = function()
  child.lua([[
    local config = require("jira.common.config")
    local auth = require("jira.common.auth")

    auth.logout()

    config.setup({
      jira = {
        base = "https://jira.local:8080/",
        type = "bearer",
        token = "test-bearer-token",
        api_version = "2",
      }
    })

    _G.res = auth.get_auth()
  ]])
  MiniTest.expect.equality(child.lua_get([[_G.res.base]]), "https://jira.local:8080")
  MiniTest.expect.equality(child.lua_get([[_G.res.type]]), "bearer")
  MiniTest.expect.equality(child.lua_get([[_G.res.token]]), "test-bearer-token")
  MiniTest.expect.equality(child.lua_get([[_G.res.api_version]]), "2")
end

T["auth"]["get_auth"]["should support auth_type alias and username in config"] = function()
  child.lua([[
    local config = require("jira.common.config")
    local auth = require("jira.common.auth")

    auth.logout()

    config.setup({
      jira = {
        base = "https://jira.selfhosted.com/",
        auth_type = "basic",
        username = "my_user",
        token = "my_password",
      }
    })

    _G.res = auth.get_auth()
  ]])
  MiniTest.expect.equality(child.lua_get([[_G.res.base]]), "https://jira.selfhosted.com")
  MiniTest.expect.equality(child.lua_get([[_G.res.type]]), "basic")
  MiniTest.expect.equality(child.lua_get([[_G.res.email]]), "my_user")
  MiniTest.expect.equality(child.lua_get([[_G.res.token]]), "my_password")
end

T["auth"]["get_auth"]["should fallback to environment variables when config is empty"] = function()
  child.lua([[
    local config = require("jira.common.config")
    local auth = require("jira.common.auth")

    auth.logout()
    config.setup({})

    vim.fn.setenv("JIRA_BASE_URL", "https://jira.env.org///")
    vim.fn.setenv("JIRA_AUTH_TYPE", "BEARER")
    vim.fn.setenv("JIRA_API_TOKEN", "env-secret-pat")
    vim.fn.setenv("JIRA_API_VERSION", "2")

    _G.res = auth.get_auth()

    -- Clean up env
    vim.fn.setenv("JIRA_BASE_URL", nil)
    vim.fn.setenv("JIRA_AUTH_TYPE", nil)
    vim.fn.setenv("JIRA_API_TOKEN", nil)
    vim.fn.setenv("JIRA_API_VERSION", nil)
  ]])
  MiniTest.expect.equality(child.lua_get([[_G.res.base]]), "https://jira.env.org")
  MiniTest.expect.equality(child.lua_get([[_G.res.type]]), "bearer")
  MiniTest.expect.equality(child.lua_get([[_G.res.token]]), "env-secret-pat")
  MiniTest.expect.equality(child.lua_get([[_G.res.api_version]]), "2")
end

T["auth"]["save_and_load"] = MiniTest.new_set()

T["auth"]["save_and_load"]["should save and load bearer credentials"] = function()
  child.lua([[
    local auth = require("jira.common.auth")
    auth.save({
      base = "https://jira.corp.internal/",
      token = "corp-pat-token-12345",
      type = "bearer",
    })

    _G.loaded = auth.load()
    _G.resolved = auth.get_auth()
    auth.logout()
  ]])
  MiniTest.expect.equality(child.lua_get([[_G.loaded.base]]), "https://jira.corp.internal/")
  MiniTest.expect.equality(child.lua_get([[_G.loaded.type]]), "bearer")
  MiniTest.expect.equality(child.lua_get([[_G.loaded.token]]), "corp-pat-token-12345")
  MiniTest.expect.equality(child.lua_get([[_G.resolved.base]]), "https://jira.corp.internal")
  MiniTest.expect.equality(child.lua_get([[_G.resolved.type]]), "bearer")
end

T["auth"]["show_info"] = MiniTest.new_set()

T["auth"]["show_info"]["should format and display auth info without error"] = function()
  child.lua([[
    local auth = require("jira.common.auth")
    local config = require("jira.common.config")
    auth.logout()

    config.setup({
      jira = {
        base = "https://jira.example.com",
        type = "bearer",
        token = "secret-token",
      }
    })

    _G.notified = {}
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(_G.notified, { msg = msg, level = level })
    end

    auth.show_info()
    vim.notify = orig_notify
  ]])
  MiniTest.expect.equality(child.lua_get([[#_G.notified]]), 1)
  local msg = child.lua_get([[_G.notified[1].msg]])
  Helpers.expect.match(msg, "Base URL: https://jira.example.com")
  Helpers.expect.match(msg, "Auth Type: bearer")
  Helpers.expect.match(msg, "Token: %*%*%*%*%*%*%*%*")
  Helpers.expect.match(msg, "Source: Config / Environment")
end

return T
