local Tools = {}

local Skill = require("codecompanion._extensions.agentskills.skill")

local function make_system_prompt()
  local AS = require("codecompanion._extensions.agentskills")
  local auto_skills = {}
  local manual_skills = {}

  for name, skill in pairs(AS.get_skills()) do
    if skill:is_auto_invocation_disabled() then
      table.insert(manual_skills, string.format("- **%s**: %s", name, skill:description()))
    else
      table.insert(auto_skills, string.format("- **%s**: %s", name, skill:description()))
    end
  end

  table.sort(auto_skills)
  table.sort(manual_skills)

  local skill_list = table.concat(auto_skills, "\n")
  local manual_section = ""
  if #manual_skills > 0 then
    manual_section = string.format(
      "\n\n## 🔧 Manual-Only Skills\nThe following skills are only activated when explicitly requested by name:\n%s",
      table.concat(manual_skills, "\n")
    )
  end

  return string.format(
    [[# Agent Skills System

You are equipped with a **Progressive Disclosure Agent Skills System**. This allows you to dynamically load specialized domain knowledge and tools to solve complex user tasks.

## 🚀 Workflow
1. **Identify**: Review the "Available Skills" list below. If a skill matches the user's intent, check whether its content is already present in the conversation (look for `<agent-skill>` tags) — if so, skip activation and proceed to execution. Otherwise, choose it for activation.
2. **Activate**: Call `activate_skill` with the skill name. This injects the skill's specific instructions (SOPs) into your context.
3. **Execute**: Strictly follow the new instructions provided by the skill.
4. **Resource Access**: If the skill instructions reference files (docs, templates) or scripts:
   - Use `load_skill_file` to read files that are **explicitly referenced in the activated skill's documentation**. Never use it for files not mentioned in the skill.
   - Use `run_skill_script` to execute scripts that are **explicitly listed in the activated skill's documentation**. Never use it for scripts not mentioned in the skill.

## ⚠️ CRITICAL RULES
1. **VIRTUAL FILESYSTEM**: Files mentioned within a skill (e.g., `assets/template.md`, `scripts/build.sh`) exist in a **virtual skill directory**, NOT the user's physical workspace.
   - ❌ **NEVER** use standard file tools (`read_file`, `grep`, etc.) to access skill resources.
   - ✅ **ONLY** use `load_skill_file` and `run_skill_script`.
2. **CONTEXT SWITCHING**: When a skill is activated, its instructions take precedence for that specific sub-task.
3. **TRANSPARENCY**: Inform the user when you are activating a skill (e.g., "I will use the `git-expert` skill to handle this...").
4. **AVOID REDUNDANT ACTIVATION**: If a skill's content has already been injected into the conversation (indicated by `<agent-skill name="xxx">` tags), do NOT call `activate_skill` for that same skill. The skill instructions are already in your context.

## 📦 Available Skills
%s%s]],
    skill_list,
    manual_section
  )
end

function Tools.activate_skill()
  return {
    name = "activate_skill",
    system_prompt = make_system_prompt(),
    schema = {
      type = "function",
      ["function"] = {
        name = "activate_skill",
        description = "Activate an agent skill to load its instructions.",
        parameters = {
          type = "object",
          properties = {
            skill_name = {
              type = "string",
              description = "The name of the skill to activate.",
            },
          },
          required = { "skill_name" },
        },
        strict = true,
      },
    },
    cmds = {
      function(self, args)
        local AS = require("codecompanion._extensions.agentskills")
        local skill = AS.get_skill(args.skill_name)
        if not skill then
          return { status = "error", data = "Skill not found: " .. args.skill_name }
        end

        local skill_id =
          string.format("<editor_context>skill:%s</editor_context>", args.skill_name)
        local context_items = (self and self.chat and self.chat.context_items) or {}
        for _, ctx in ipairs(context_items) do
          if ctx.id == skill_id then
            return {
              status = "error",
              data = "Skill already in context: "
                .. args.skill_name
                .. ". Do not activate skills that are already in context.",
            }
          end
        end

        return { status = "success", data = skill }
      end,
    },
    output = {
      success = function(self, output, meta)
        local AS = require("codecompanion._extensions.agentskills")
        local skill = output[#output] ---@type CodeCompanion.AgentSkills.Skill
        local for_user = string.format("Activated skill: %s", skill:name())
        meta.tools.chat:add_tool_output(self, skill:read_content(), for_user)
        AS.inject_skill_tools(meta.tools.chat, skill)
      end,
      error = function(self, output, meta)
        local error_msg = string.format(
          "Failed to activate skill: %s. Error: %s",
          self.args.skill_name,
          output[#output]
        )
        meta.tools.chat:add_tool_output(self, error_msg)
      end,
    },
  }
end

function Tools.load_skill_file()
  return {
    name = "load_skill_file",
    schema = {
      type = "function",
      ["function"] = {
        name = "load_skill_file",
        description = "Load a file that is pre-packaged inside an activated skill's directory.\n\n**PREREQUISITE (must satisfy ALL before calling)**:\n1. You have already called `activate_skill` for the target skill.\n2. The skill's documentation **explicitly references** the file path you intend to load.\n3. The `file_path` is copied **verbatim** from the skill's documentation — do NOT construct or guess paths.\n\nIf no file is referenced in the skill documentation, do NOT call this tool. For files in the user's workspace, use standard file reading tools instead. To execute skill scripts, use `run_skill_script`.",
        parameters = {
          type = "object",
          properties = {
            skill_name = {
              type = "string",
              description = "The name of the skill to load the file from.",
            },
            file_path = {
              type = "string",
              description = "The path of the file to load, relative to the skill directory. Example: 'references/usage.md' or 'assets/template.html'.",
            },
          },
          required = { "skill_name", "file_path" },
        },
        strict = true,
      },
    },
    cmds = {
      function(self, args)
        local AS = require("codecompanion._extensions.agentskills")
        local skill = AS.get_skill(args.skill_name)
        if not skill then
          return { status = "error", data = "Skill not found: " .. args.skill_name }
        end
        local ok, content = pcall(function()
          return skill:read_file(args.file_path)
        end)
        if not ok then
          return { status = "error", data = "Failed to read file: " .. tostring(content) }
        end
        if not content then
          return { status = "error", data = "File not found in skill: " .. args.file_path }
        end
        return { status = "success", data = content }
      end,
    },
    output = {
      success = function(self, output, meta)
        local content = output[#output]
        local for_user = string.format(
          "Loaded skill file successfully: %s/%s",
          self.args.skill_name,
          self.args.file_path
        )
        meta.tools.chat:add_tool_output(self, content, for_user)
      end,
      error = function(self, output, meta)
        local error_msg = string.format(
          "Failed to load skill file: %s/%s. Error: %s",
          self.args.skill_name,
          self.args.file_path,
          output[#output]
        )
        meta.tools.chat:add_tool_output(self, error_msg)
      end,
    },
  }
end

function Tools.run_skill_script()
  local interpreters =
    require("codecompanion._extensions.agentskills.interpreter").get_enabled_interpreters()
  local interpreter_lines = {}
  local available_names = {}
  for name, handler in pairs(interpreters) do
    table.insert(available_names, name)
    local deps_note = handler.support_dependencies and " (supports dependencies)" or ""
    table.insert(interpreter_lines, string.format("- %s%s", name, deps_note))
  end
  table.sort(available_names)
  table.sort(interpreter_lines)

  local interpreter_desc = table.concat(interpreter_lines, "\n")

  return {
    name = "run_skill_script",
    schema = {
      type = "function",
      ["function"] = {
        name = "run_skill_script",
        description = string.format(
          [[Run a script that is **pre-packaged inside an activated skill's directory**.

**PREREQUISITE (must satisfy ALL before calling)**:
1. You have already called `activate_skill` for the target skill.
2. The skill's documentation **explicitly lists** the script path you intend to run.
3. The `script_path` is copied **verbatim** from the skill's documentation — do NOT construct or guess paths.

If no script is listed in the skill documentation, do NOT call this tool.
If you need to run a general command unrelated to any skill, this tool CANNOT help — inform the user instead.

The script runs in the user's current working directory. Use placeholder '%s' in arguments to refer to the skill directory.

Supported interpreters:
%s

Note: Only interpreters that support dependencies can use the 'dependencies' parameter.]],
          Skill.SKILL_DIR_PLACEHOLDER,
          interpreter_desc
        ),
        parameters = {
          type = "object",
          properties = {
            skill_name = {
              type = "string",
              description = "The name of the skill to run the script from.",
            },
            script_path = {
              type = "string",
              description = "The path of the script to run, relative to the skill directory. Example: 'scripts/generate_report.sh'.",
            },
            args = {
              type = "array",
              items = { type = "string" },
              description = string.format(
                [[Argument array to pass to the script. Placeholder '%s' will be replaced with the skill directory path. E.g: ["--template", "%s/assets/template.html"].]],
                Skill.SKILL_DIR_PLACEHOLDER,
                Skill.SKILL_DIR_PLACEHOLDER
              ),
            },
            interpreter = {
              type = "string",
              enum = available_names,
              description = "The interpreter to use for running the script.",
            },
            dependencies = {
              type = "array",
              items = { type = "string" },
              description = [[List of runtime dependencies. Only supported by interpreters that support dependencies. E.g: ["requests", "numpy>=1.20"].]],
            },
          },
          required = { "skill_name", "script_path", "interpreter" },
        },
        strict = true,
      },
    },
    cmds = {
      function(self, args, opts)
        if args.skill_name == nil then
          return { status = "error", data = "Missing required parameter: skill_name" }
        end
        if args.script_path == nil then
          return { status = "error", data = "Missing required parameter: script_path" }
        end
        if args.interpreter == nil then
          return { status = "error", data = "Missing required parameter: interpreter" }
        end

        local AS = require("codecompanion._extensions.agentskills")
        local skill = AS.get_skill(args.skill_name)
        if not skill then
          return { status = "error", data = "Skill not found: " .. args.skill_name }
        end
        skill:run_script(
          args.interpreter,
          args.script_path,
          args.args ~= vim.NIL and args.args or nil,
          args.dependencies ~= vim.NIL and args.dependencies or nil,
          vim.schedule_wrap(function(ok, output)
            if ok then
              opts.output_cb({ status = "success", data = output })
            else
              opts.output_cb({ status = "error", data = output })
            end
          end)
        )
      end,
    },
    handlers = {
      setup = function(self, meta)
        -- Dynamic approval settings based on scripts_require_approval
        local AS = require("codecompanion._extensions.agentskills")
        local skill = AS.get_skill(self.args.skill_name)
        if skill and skill.opts and skill.opts.scripts_require_approval == false then
          self.opts.require_approval_before = false
        else
          self.opts.require_approval_before = true
        end

        -- Smart argument escaping logic (for display only)
        local args = self.args.args
        if args == vim.NIL or args == nil then
          self.escaped_args = {}
          return
        end

        local escaped = {}
        for _, arg in ipairs(args) do
          if string.match(arg, "^[%w%.%-%_/:]+$") then
            table.insert(escaped, arg)
          else
            table.insert(escaped, vim.fn.shellescape(arg))
          end
        end

        self.escaped_args = escaped
      end,
    },

    output = {
      prompt = function(self)
        local argv = {
          self.args.interpreter,
          self.args.script_path,
          unpack(self.escaped_args),
        }

        local msg = {
          string.format("Confirm to run script from skill '%s'?", self.args.skill_name),
          "Command:\n    " .. table.concat(argv, " "),
        }

        local deps = self.args.dependencies ~= vim.NIL and self.args.dependencies or nil
        if deps and #deps > 0 then
          table.insert(msg, "Dependencies:\n    " .. table.concat(deps, ", "))
        end

        return table.concat(msg, "\n")
      end,

      success = function(self, output, meta)
        local output = output[#output]
        local argv = { self.args.interpreter, self.args.script_path, unpack(self.escaped_args) }
        local for_user = string.format("Run skill script successfully: %s", table.concat(argv, " "))
        meta.tools.chat:add_tool_output(self, output, for_user)
      end,

      error = function(self, output, meta)
        local error_msg = output[#output]
        local parts = { self.args.interpreter, self.args.script_path, unpack(self.escaped_args) }
        local for_user = string.format(
          "Failed to run skill script: %s. Error: %s",
          table.concat(parts, " "),
          error_msg
        )
        meta.tools.chat:add_tool_output(self, error_msg, for_user)
      end,
    },
  }
end

return Tools
