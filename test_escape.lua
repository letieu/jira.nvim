local text = 'vim.print("ok")'
local data = {
  content = {
    {
      type = "codeBlock",
      content = {
        {
          type = "text",
          text = text,
        },
      },
    },
  },
}

local json_data = vim.json.encode(data)
print("Original JSON: " .. json_data)

-- Logic from api.lua
local escaped = json_data:gsub('"', '"')
print("Escaped for Shell: " .. escaped)

local cmd = ('curl -d "%s"'):format(escaped)
print("Command: " .. cmd)
