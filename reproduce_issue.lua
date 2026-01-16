local M = {}

function M.parse_inline_markdown(text)
  return { { type = "text", text = text } }
end

function M.markdown_to_adf(text)
  local doc = {
    type = "doc",
    version = 1,
    content = {},
  }

  local lines = vim.split(text, "\n")
  local current_node = nil
  local in_code_block = false
  local code_language = nil
  local code_lines = {}

  for _, line in ipairs(lines) do
    if in_code_block then
      if line:match("^```") then
        -- End of code block
        table.insert(doc.content, {
          type = "codeBlock",
          attrs = { language = code_language },
          content = {
            {
              type = "text",
              text = table.concat(code_lines, "\n"),
            },
          },
        })
        in_code_block = false
        code_lines = {}
        code_language = nil
        current_node = nil
      else
        table.insert(code_lines, line)
      end
    else
      local code_start, lang = line:match("^```(%w*)")
      local h_level, h_content = line:match("^(#+)%s+(.*)")

      if code_start then
        current_node = nil
        in_code_block = true
        code_language = lang -- This is likely the bug: lang is nil here
        code_lines = {}
        print("DEBUG: Start code block. Capture1:", code_start, "Capture2:", lang)
      elseif h_level then
        -- ...
      else
        -- ...
      end
    end
  end

  -- Handle unclosed
  if in_code_block then
    table.insert(doc.content, {
      type = "codeBlock",
      attrs = { language = code_language },
      content = { { type = "text", text = table.concat(code_lines, "\n") } },
    })
  end

  return doc
end

local input = [[ 
# Title
```lua
print("hello")
```
]]

local result = M.markdown_to_adf(input)
print(vim.inspect(result))
