const DEFAULT_NAME = "OpenCode Agent"
const DEFAULT_EMAIL = "opencode-agent@users.noreply.github.com"
const DEFAULT_MESSAGE = "chore(agent): save OpenCode session changes"
const GLOBAL_CONFIG_PATH = `${Bun.env.HOME || ""}/.config/opencode/agent-commit.json`

async function readJsonConfig(path) {
  if (!path) return {}

  const file = Bun.file(path)
  if (!(await file.exists())) return {}

  try {
    return await file.json()
  } catch {
    return {}
  }
}

function readFlag(name, fallback) {
  const value = Bun.env[name]
  if (value === undefined) return fallback
  return !["0", "false", "no", "off"].includes(value.toLowerCase())
}

function readBool(value, fallback) {
  if (value === undefined || value === null || value === "") return fallback
  if (typeof value === "boolean") return value
  return !["0", "false", "no", "off"].includes(String(value).toLowerCase())
}

async function readSettings(worktree) {
  const projectConfigPath = worktree ? `${worktree}/.opencode/agent-commit.json` : ""
  const globalConfig = await readJsonConfig(GLOBAL_CONFIG_PATH)
  const projectConfig = await readJsonConfig(projectConfigPath)
  const fileConfig = { ...globalConfig, ...projectConfig }

  return {
    enabled: readBool(fileConfig.enabled, true),
    rewriteGitCommit: readBool(fileConfig.rewriteGitCommit, true),
    commitOnIdle: readBool(fileConfig.commitOnIdle, true),
    name: fileConfig.name || DEFAULT_NAME,
    email: fileConfig.email || DEFAULT_EMAIL,
    message: fileConfig.message || DEFAULT_MESSAGE,
    worktree,
  }
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'"'"'`)}'`
}

function shouldRewriteCommit(command) {
  if (!/\bgit\b[\s\S]*\bcommit\b/.test(command)) return false
  if (/\bGIT_AUTHOR_NAME=|\bGIT_COMMITTER_NAME=/.test(command)) return false
  if (/\b--author\b/.test(command)) return false
  if (/user\.name=|user\.email=/.test(command)) return false
  return true
}

async function commitDirtyWorktree($, settings) {
  const status = (await $`git -C ${settings.worktree} status --porcelain`.text()).trim()
  if (!status) return false

  await $`git -C ${settings.worktree} add -A`
  await $`env GIT_AUTHOR_NAME=${settings.name} GIT_AUTHOR_EMAIL=${settings.email} GIT_COMMITTER_NAME=${settings.name} GIT_COMMITTER_EMAIL=${settings.email} git -C ${settings.worktree} commit -m ${settings.message} 2> /dev/null`
  return true
}

export const AgentCommitPlugin = async ({ client, $, worktree }) => {
  const settings = await readSettings(worktree)
  let lastAttemptedStatus = ""

  settings.enabled = readFlag("OPENCODE_AGENT_COMMIT_ENABLED", settings.enabled)
  settings.rewriteGitCommit = readFlag("OPENCODE_AGENT_COMMIT_REWRITE_GIT_COMMIT", settings.rewriteGitCommit)
  settings.commitOnIdle = readFlag("OPENCODE_AGENT_COMMIT_ON_IDLE", settings.commitOnIdle)
  settings.name = Bun.env.OPENCODE_AGENT_COMMIT_NAME || settings.name
  settings.email = Bun.env.OPENCODE_AGENT_COMMIT_EMAIL || settings.email
  settings.message = Bun.env.OPENCODE_AGENT_COMMIT_MESSAGE || settings.message

  await client.app.log({
    body: {
      service: "agent-commit-plugin",
      level: "info",
      message: "Initialized agent commit plugin",
      extra: {
        enabled: settings.enabled,
        commitOnIdle: settings.commitOnIdle,
        rewriteGitCommit: settings.rewriteGitCommit,
      },
    },
  })

  return {
    "tool.execute.before": async (input, output) => {
      if (!settings.enabled || !settings.rewriteGitCommit) return
      if (input.tool !== "bash") return

      const command = output.args.command
      if (!command || !shouldRewriteCommit(command)) return

      output.args.command = [
        `GIT_AUTHOR_NAME=${shellQuote(settings.name)}`,
        `GIT_AUTHOR_EMAIL=${shellQuote(settings.email)}`,
        `GIT_COMMITTER_NAME=${shellQuote(settings.name)}`,
        `GIT_COMMITTER_EMAIL=${shellQuote(settings.email)}`,
        command,
      ].join(" ")
    },

    event: async ({ event }) => {
      if (!settings.enabled || !settings.commitOnIdle) return
      if (event.type !== "session.idle") return

      try {
        const status = (await $`git -C ${settings.worktree} status --porcelain`.text()).trim()
        if (!status) {
          lastAttemptedStatus = ""
          return
        }
        if (status === lastAttemptedStatus) return

        lastAttemptedStatus = status
        const committed = await commitDirtyWorktree($, settings)
        if (!committed) return

        await client.app.log({
          body: {
            service: "agent-commit-plugin",
            level: "info",
            message: "Committed dirty worktree on session idle",
            extra: {
              worktree: settings.worktree,
            },
          },
        })
      } catch (error) {
        await client.app.log({
          body: {
            service: "agent-commit-plugin",
            level: "error",
            message: "Failed to auto-commit dirty worktree",
            extra: {
              worktree: settings.worktree,
              error: error instanceof Error ? error.message : String(error),
            },
          },
        })
      }
    },
  }
}
