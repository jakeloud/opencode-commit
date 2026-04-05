# opencode-agent-commit

MVP OpenCode plugin that commits changes using an agent Git identity.

It does two things:

- rewrites any OpenCode-driven `git commit` shell command so it uses agent author and committer env vars
- auto-commits a dirty git worktree when the OpenCode session becomes idle

## Quick Install

Clone this repo and run:

```bash
./setup.sh
```

The installer will prompt for your agent identity and install the plugin either:

- globally into `~/.config/opencode/`, or
- into a specific project's `.opencode/` directory

## Files

- `.opencode/plugins/agent-commit.js` - OpenCode plugin
- `.opencode/package.json` - marks plugin code as ESM
- `setup.sh` - interactive installer

## Configuration

The plugin loads config from:

- `~/.config/opencode/agent-commit.json` for global installs
- `.opencode/agent-commit.json` for project installs

Environment variables still override file config when they are set:

- `OPENCODE_AGENT_COMMIT_ENABLED`
- `OPENCODE_AGENT_COMMIT_REWRITE_GIT_COMMIT`
- `OPENCODE_AGENT_COMMIT_ON_IDLE`
- `OPENCODE_AGENT_COMMIT_NAME`
- `OPENCODE_AGENT_COMMIT_EMAIL`
- `OPENCODE_AGENT_COMMIT_MESSAGE`

## Use It

1. Run `./setup.sh`.
2. Start OpenCode in a repo covered by your install.
3. Make changes with the agent.
4. Let the session go idle, or have the agent run a `git commit` command.

## Test It

After OpenCode makes a change, verify the latest commit identity:

```bash
git log -1 --format='%an <%ae> | %cn <%ce> | %s'
```

The author and committer should both match your configured agent identity.

## GitHub Attribution Caveat

GitHub attributes commits by author email. If you want commits to show up under a separate agent profile, the email must belong to that GitHub account and be verified there.
