local Tools = {}

local Skill = require("codecompanion._extensions.agentskills.skill")

local function make_system_prompt()
  local AS = require("codecompanion._extensions.agentskills")
  local skill_list = vim
    .iter(AS.get_skills())
    :map(function(name, skill)
      return string.format("* `%s`: %s", name, skill:description())
    end)
    :join("\n\n")
  return string.format(
    [[## Agent Skills
You can use **Agent Skills** to acquire domain knowledge and capabilities to accomplish specific user tasks.

A skill contains detailed instructions about how to perform a specific kind of tasks. It may also contains a set of reference documents that can be explicitly loaded on demand, and scripts and resource files that can help you accomplish the tasks.

### When to use skills?
* The user explicitly requests to use a skill.
* The user task requires specific domain knowledge or capabilities that can be better handled by a skill.
* The execution of a skill's workflow delegates subtasks to another skill.

### How to use skills?
Agent Skills follow a **Progressive Disclosure** pattern: you are given names and descriptions of all available skills, and you can **activate** a skill to load its instructions, then optionally load its reference documents and resources as needed.

You must follow the steps below when you need to use a skill:
1. Determine which skill is most appropriate for the user task based on the skill descriptions.
2. Use `activate_skill` tool to activate the chosen skill, and you will be presented with the skill instructions.
3. Strictly follow the skill instructions to accomplish the user task.
4. *Only if needed*, use `load_skill_file` tool to load reference documents or resource files, use `run_skill_script` tool to execute scripts provided by the skill.

### Key points
* You must strictly follow the instructions provided by the activated skill.
* All files mentioned in the skill instructions DO NOT EXIST in your current working directory, so you MUST NOT access them using generic file access tools, no matter what the instructions say.
* You can only access skill files via `load_skill_file` tools.
* You can only run skill scripts via `run_skill_script` tools.
* You should give concise and clear process updates to the user on each step of the skill instructions.

### Example
1. User requests to generate a analytical report, and a skill named `report-generator` contains instructions on how to generate the report according to its description.
2. You use `activate_skill` tool to activate `report-generator` skill, and read its instructions.
3. You follow the instructions to gather and analyze data.
4. The instructions suggest reading `references/usage.md` for more details, so you use `load_skill_file` tool to load that file.
5. The instructions require running a script `scripts/generate_report.sh` with a specific template, so you use `run_skill_script` tool to execute that script with the required arguments.
6. You revisit the skill instructions to ensure all steps are followed, and present the final result to the user.

### What skills are available?
%s]],
    skill_list
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
        else
          return { status = "success", data = skill }
        end
      end,
    },
    output = {
      success = function(self, tools, cmd, stdout)
        local skill = stdout[#stdout] ---@type CodeCompanion.AgentSkills.Skill
        local for_user = string.format("Activated skill: %s", skill:name())
        tools.chat:add_tool_output(self, skill:read_content(), for_user)
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
        description = "Load a file provided by a skill.",
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
        local content = skill:read_file(args.file_path)
        if not content then
          return { status = "error", data = "File not found in skill: " .. args.file_path }
        end
        return { status = "success", data = content }
      end,
    },
    output = {
      success = function(self, tools, cmd, stdout)
        local content = stdout[#stdout]
        local for_user = string.format(
          "Loaded skill file successfully: %s/%s",
          self.args.skill_name,
          self.args.file_path
        )
        tools.chat:add_tool_output(self, content, for_user)
      end,
    },
  }
end

function Tools.run_skill_script()
  return {
    name = "run_skill_script",
    schema = {
      type = "function",
      ["function"] = {
        name = "run_skill_script",
        description = string.format(
          [[Run a script provided by a skill. The script will be executed in user's current working directory. Use placeholder '%s' in arguments to refer to the skill directory.]],
          Skill.SKILL_DIR_PLACEHOLDER
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
              items = {
                type = "string",
              },
              description = string.format(
                [[Arguments to pass to the script. Placeholder '%s' will be replaced with the skill directory path. E.g: ["--template", "%s/assets/template.html"].]],
                Skill.SKILL_DIR_PLACEHOLDER,
                Skill.SKILL_DIR_PLACEHOLDER
              ),
            },
          },
          required = { "skill_name", "script_path" },
        },
        strict = true,
      },
    },
    cmds = {
      function(self, args, input, output_handler)
        local AS = require("codecompanion._extensions.agentskills")
        local skill = AS.get_skill(args.skill_name)
        if not skill then
          return { status = "error", data = "Skill not found: " .. args.skill_name }
        end
        skill:run_script(args.script_path, args.args or {}, function(ok, output)
          if ok then
            output_handler({ status = "success", data = output })
          else
            output_handler({ status = "error", data = output })
          end
        end)
      end,
    },
    output = {
      success = function(self, tools, cmd, stdout)
        local output = stdout[#stdout]
        local for_user = string.format(
          "Run skill script successfully: %s %s",
          self.args.script_path,
          table.concat(self.args.args or {}, " ")
        )
        tools.chat:add_tool_output(self, output, for_user)
      end,
      error = function(self, tools, cmd, stderr)
        local error_msg = stderr[#stderr]
        local for_user = string.format(
          "Failed to run skill script: %s %s. Error: %s",
          self.args.script_path,
          table.concat(self.args.args or {}, " "),
          error_msg
        )
        tools.chat:add_tool_output(self, error_msg, for_user)
      end,
    },
  }
end

return Tools
