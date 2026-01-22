local Skill = require("codecompanion._extensions.agentskills.skill")
local log = require("codecompanion.utils.log")
local scandir = require("plenary.scandir")
local tools = require("codecompanion._extensions.agentskills.tools")

local Extension = {}

---@class CodeCompanion.AgentSkills.Opts
---@field paths (string | { [1]: string, recursive: boolean })[] List of paths to search for skills

---@type CodeCompanion.AgentSkills.Opts
local current_opts = {
  paths = {},
}

---@type table<string, CodeCompanion.AgentSkills.Skill>?
local skills

local function discover_skills()
  skills = {}
  for _, path_spec in ipairs(current_opts.paths) do
    -- Normalize path specification
    local path, recursive
    if type(path_spec) == "string" then
      path = path_spec
      recursive = false
    else
      path = path_spec[1] or path_spec.path
      recursive = path_spec.recursive or false
    end
    path = vim.fs.normalize(path)

    log:info("Scanning skills in %s", path_spec)
    local skill_files = scandir.scan_dir(path, {
      search_pattern = function(dir)
        return vim.uv.fs_stat(vim.fs.joinpath(dir, "SKILL.md")) ~= nil
      end,
      depth = recursive and 99 or 1,
      add_dirs = true,
      only_dirs = true,
      hidden = false,
      respect_gitignore = true,
    })
    log:info("Found skill files: %s", skill_files)

    for _, skill_dir in ipairs(skill_files) do
      local ok, skill = pcall(Skill.load, skill_dir)
      if ok and skill and skill.name then
        skills[skill:name()] = skill
      else
        log:warn("Failed to load skill %s: %s", skill_dir, skill)
      end
    end
  end
end

---@param opts CodeCompanion.AgentSkills.Opts
function Extension.setup(opts)
  current_opts = vim.tbl_deep_extend("force", current_opts, opts or {})
  discover_skills()

  local cc_config = require("codecompanion.config")
  local tools_config = cc_config.interactions.chat.tools
  tools_config.activate_skill = {
    callback = tools.activate_skill,
    visible = false,
  }
  tools_config.load_skill_file = {
    callback = tools.load_skill_file,
    visible = false,
  }
  tools_config.run_skill_script = {
    callback = tools.run_skill_script,
    opts = {
      allowed_in_yolo_mode = false,
      require_approval_before = true,
      require_cmd_approval = true,
    },
    visible = false,
  }
  tools_config.groups.agent_skills = {
    description = "Agent Skills",
    tools = { "activate_skill", "load_skill_file", "run_skill_script" },
    opts = { collapse_tools = true },
  }
end

---@return table<string, CodeCompanion.AgentSkills.Skill>?
function Extension.get_skills()
  return skills
end

---@param name string
---@return CodeCompanion.AgentSkills.Skill?
function Extension.get_skill(name)
  return skills and skills[name]
end

Extension.exports = {
  Skill = Skill,
  discover = discover_skills,
  get_skills = Extension.get_skills,
}

return Extension
