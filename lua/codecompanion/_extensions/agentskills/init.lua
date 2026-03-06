local Skill = require("codecompanion._extensions.agentskills.skill")
local log = require("codecompanion.utils.log")

local Extension = {}

---@class CodeCompanion.AgentSkills.Opts
---@field paths (string | { [1]: string, recursive: boolean })[] List of paths to search for skills

---@type CodeCompanion.AgentSkills.Opts
local current_opts = {
  paths = {},
  ignore_dirs = {},
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
    -- Custom scan to follow symlinked directories
    local function is_dir_or_symlink_dir(p)
      local stat = vim.uv.fs_lstat(p)
      if not stat then
        return false
      end
      if stat.type == "directory" then
        return true
      end
      if stat.type == "link" then
        local target_stat = vim.uv.fs_stat(p)
        return target_stat and target_stat.type == "directory"
      end
      return false
    end

    local function scan_skills(dir, depth, max_depth, result, visited)
      if depth > max_depth then
        return
      end
      local real = vim.uv.fs_realpath(dir)
      if not real or visited[real] then
        return
      end
      visited[real] = true
      if not is_dir_or_symlink_dir(dir) then
        return
      end
      local skill_md = vim.fs.joinpath(dir, "SKILL.md")
      if vim.uv.fs_stat(skill_md) then
        table.insert(result, dir)
      end
      local handle = vim.uv.fs_scandir(dir)
      if not handle then
        return
      end

      while true do
        local name, typ = vim.uv.fs_scandir_next(handle)
        if not name then
          break
        end
        -- Skip hidden directories and commonly ignored directories
        if name:sub(1, 1) ~= "." and not current_opts.ignore_dirs[name] then
          local child = vim.fs.joinpath(dir, name)
          if is_dir_or_symlink_dir(child) then
            scan_skills(child, depth + 1, max_depth, result, visited)
          end
        end
      end
    end

    local skill_files = {}
    scan_skills(path, 0, recursive and 99 or 1, skill_files, {})
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

  -- Detect CodeCompanion version
  local ok, cc = pcall(require, "codecompanion")
  local version = 18
  if ok and cc and cc.version then
    version = tonumber(cc.version():match("^(%d+)")) or 18
  end

  discover_skills()

  -- Apply version compatibility decorator
  local cc_compat = require("codecompanion._extensions.agentskills.cc_compat")
  local tools_module = require("codecompanion._extensions.agentskills.tools")

  local tools_config = require("codecompanion.config").interactions.chat.tools
  tools_config.activate_skill = {
    callback = cc_compat.decorate_tool(tools_module.activate_skill, version),
    visible = false,
  }
  tools_config.load_skill_file = {
    callback = cc_compat.decorate_tool(tools_module.load_skill_file, version),
    visible = false,
  }
  tools_config.run_skill_script = {
    callback = cc_compat.decorate_tool(tools_module.run_skill_script, version),
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
