# codecompanion-agentskills.nvim

An extension for [CodeCompanion.nvim](https://github.com/olimorris/codecompanion.nvim) that adds support for [Agent Skills](https://agentskills.io).

**Note: this project is currently in early prototype stage. There may be significant breaking changes without notice.**

## What is Agent Skills?

Agent Skills is a progressive disclosure system that enables AI agents to dynamically load specialized domain knowledge on demand. Instead of loading all knowledge at once, agents can activate specific skills only when needed.

For more information about Agent Skills, visit the [official website](https://agentskills.io).

## Features

- **Progressive Disclosure**: Activate specialized skills on demand to avoid context overload
- **Virtual Filesystem**: Skill resources are isolated from your workspace for security and clarity
- **Tools**:
  - `activate_skill`: Load a skill and inject its instructions into the AI context
  - `load_skill_file`: Read documentation, templates, or other text files provided by a skill
  - `run_skill_script`: Execute scripts provided by a skill
  - **The above tools are invisible to users and you should use the `@{agent_skills}` tool group in your Chat**
- **Flexible Discovery**: Scan single directories or recursively search for skills
- **Default Skill Paths**: Automatically discovers skills from well-known project and personal directories

## Requirements

- Neovim 0.11.0 or greater
- [CodeCompanion.nvim](https://github.com/olimorris/codecompanion.nvim)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "olimorris/codecompanion.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "cairijun/codecompanion-agentskills.nvim",
  },
  config = function()
    require("codecompanion").setup({
      -- Your CodeCompanion configuration...
      --
      -- Configure the AgentSkills extension
      extensions = {
        agentskills = {
          opts = {
            paths = {
              "~/my-agent-skills",  -- Single directory (non-recursive)
              { "~/.config/nvim/skills", recursive = true },  -- Recursive search
            },
            notify_on_discovery = true,  -- Show a notification when skills are discovered
          }
        }
      }
    })
  end
}
```

## Default Skill Paths

Skills are automatically discovered from the following well-known directories (no configuration needed):

| Type | Paths |
|------|-------|
| **Project** (relative to cwd) | `.github/skills/`, `.cursor/skills/`, `.claude/skills/`, `.codex/skills/`, `.agents/skills/` |
| **Personal** (home directory) | `~/.copilot/skills/`, `~/.cursor/skills/`, `~/.claude/skills/`, `~/.codex/skills/`, `~/.agents/skills/` |

Any additional paths specified in `opts.paths` are scanned on top of these defaults. Non-existent directories are silently skipped.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `paths` | `table` | `{}` | Additional paths to search for skills. Each entry can be a string (non-recursive) or a table `{ path, recursive = true }`. |
| `notify_on_discovery` | `boolean` | `false` | When `true`, displays a `vim.notify` message listing all discovered skills on startup. |
| `make_slash_commands` | `boolean` | `true` | When `true`, registers discovered skills as `/` slash commands in CodeCompanion chat. |

## Usage

* Put skill directories in one of the [default paths](#default-skill-paths) or any path configured in `opts.paths`. Each skill directory must contain a `SKILL.md` file with YAML frontmatter.
* Use `@{agent_skills}` tool group in your Chat. The LLM should activate skills when your task matches the skill's description. You can also explicitly ask the LLM to use a specific skill by name.
* Type `/` in the chat buffer to invoke a skill as a slash command (e.g., `/my-skill`). Skills are automatically registered as slash commands unless `make_slash_commands` is set to `false`.
* You can also use the editor context syntax `#{skill:<skill-name>}` to inject a skill explicitly into your chat buffer. *`@{agent_skills}` tool group is still required to ensure it functions properly*.

## SKILL.md Format

Each skill is defined in a `SKILL.md` file with YAML frontmatter:

```markdown
---
name: my-skill
description: Short description of what this skill does and when to use it.
license: MIT
disable-model-invocation: false
user-invokable: true
argument-hint: "[options]"
tools:
  - cmd_runner
  - agent_skills
compatibility:
  requires:
    - python3
metadata:
  author: your-name
---

# My Skill

Detailed instructions for the agent.
```

### Frontmatter Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Skill identifier. |
| `description` | Yes | Describes what the skill does and when to use it. Used by the agent to determine relevance. |
| `license` | No | License name or reference to a bundled license file. |
| `compatibility` | No | Environment requirements (system packages, network access, etc.). |
| `metadata` | No | Arbitrary key-value mapping for additional metadata. |
| `disable-model-invocation` | No | When `true`, the skill is only included when explicitly requested by name. The agent will not automatically apply it based on context. Default: `false`. |
| `user-invokable` | No | Controls whether the skill appears as a `/` slash command in the chat buffer. Default: `true`. |
| `argument-hint` | No | Hint text shown as the slash command description when invoked via `/`. Falls back to `description` if not set. |
| `tools` | No | List of tool or tool group names to inject into the chat when the skill is activated. |

### Skill Invocation Behavior

The `user-invokable` and `disable-model-invocation` fields control how a skill can be accessed:

| Configuration | `/` Slash Command | Auto-loaded by Agent | Use Case |
|---|---|---|---|
| Default (both omitted) | ✅ | ✅ | General-purpose skills |
| `user-invokable: false` | ❌ | ✅ | Background knowledge the agent loads when relevant |
| `disable-model-invocation: true` | ✅ | ❌ | On-demand skills invoked manually |
| Both set | ❌ | ❌ | Effectively disabled |
