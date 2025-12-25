local log = require("codecompanion.utils.log")
local yaml = require("codecompanion._extensions.agentskills.3rd.yaml")

local MD_YAML_FRONTMATTER_QUERY =
  vim.treesitter.query.parse("markdown", "(document (minus_metadata) @yaml_frontmatter)")

---@param path string path to the SKILL.md
---@return table<string, any>
local function parse_skill_meta(path)
  local content = vim.fn.readblob(path)
  local md_parser = vim.treesitter.get_string_parser(content, "markdown")
  md_parser:parse()
  local tree = md_parser:trees()[1]
  return vim
    .iter(MD_YAML_FRONTMATTER_QUERY:iter_captures(tree:root()))
    :map(function(capture_id, node)
      if MD_YAML_FRONTMATTER_QUERY.captures[capture_id] ~= "yaml_frontmatter" then
        return
      end
      local yaml_text = vim.treesitter.get_node_text(node, content)
      local ok, meta = pcall(yaml.eval, yaml_text)
      if ok then
        return meta
      end
    end)
    :next()
end

---@class CodeCompanion.AgentSkills.Skill
---@field path string
---@field meta table<string, any>
local Skill = {
  SKILL_DIR_PLACEHOLDER = "${SKILL_DIR}",
}
Skill.__index = Skill

---@param path string
function Skill.load(path)
  path = vim.fs.normalize(path)
  local meta = parse_skill_meta(vim.fs.joinpath(path, "SKILL.md"))
  if meta == nil then
    error("Failed to parse SKILL.md frontmatter at " .. path)
  end
  return setmetatable({
    path = path,
    meta = meta,
  }, Skill)
end

---@return string
function Skill:name()
  return vim.trim(self.meta.name)
end

---@return string
function Skill:description()
  return vim.trim(self.meta.description)
end

function Skill:_normalize_path_in_skill(path_in_skill)
  local p = vim.fs.normalize(vim.fs.joinpath(self.path, path_in_skill))
  if vim.fs.relpath(self.path, p) == nil then
    error("Attempted to access file outside of skill directory: " .. path_in_skill)
  end
  return p
end

---@return string
function Skill:read_content()
  return self:read_file("SKILL.md")
end

---@param path_in_skill string
---@return string
function Skill:read_file(path_in_skill)
  return vim.fn.readblob(self:_normalize_path_in_skill(path_in_skill))
end

---@param script string
---@param args string[]
---@param callback fun(ok: boolean, output_or_error: string)
function Skill:run_script(script, args, callback)
  local cmd = { self:_normalize_path_in_skill(script) }
  local placeholder_pattern = vim.pesc(self.SKILL_DIR_PLACEHOLDER)
  for _, arg in ipairs(args or {}) do
    arg = string.gsub(arg, placeholder_pattern, self.path)
    table.insert(cmd, arg)
  end
  log:info("Running skill script: %s", cmd)
  vim.system(cmd, {
    stdout = true,
    stderr = true,
  }, function(out)
    log:info("Skill script exited with code %d: %s", out.code, cmd)
    callback = vim.schedule_wrap(callback)
    if out.code == 0 then
      callback(true, out.stdout)
    else
      local msg
      if out.signal and out.signal ~= 0 then
        msg = string.format("Script terminated with signal %d", out.signal)
      else
        msg = string.format("Script exited with code %d", out.code)
      end
      callback(false, msg .. "\nSTDERR:\n" .. out.stderr)
    end
  end)
end

return Skill
