# Starterpack

A plug-and-play AI agent orchestration setup for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). It came out of months of working with AI agent swarms 10+ hours a day and constantly running into the same problems.

## Why This Exists

If you've spent any time with AI agents writing code, you've probably hit these:

- **Vibe coding** -agents ship code with no human review, subtle bugs compound over time
- **Documentation drift** -the codebase evolves but docs don't, so future agent sessions work off stale info and things start breaking in weird ways
- **Token burn** -Opus doing work that Haiku handles fine
- **Lost context** -scattered commits with no traceability, agents forgetting what they were doing mid-session

One agent making a small mistake is fine. A swarm of agents all making small mistakes at the same time is not.

## What It Does

Starterpack gives Claude Code a structured workflow with human checkpoints, tiered model usage, and mandatory documentation upkeep:

- **Human gates** -nothing ships without your approval. Not planning, not code, not docs, not the PR
- **Tiered models** -Opus plans and reviews, Sonnet/Haiku implement. Cheaper models escalate to Opus automatically when they get stuck
- **Doc audits every time** -every ticket triggers a documentation review, not just when someone remembers
- **Git-tracked tickets** -[Beads](https://github.com/cosmix/beads) issues live in your repo, sync to GitHub Issues, and tie directly to branches and commits
- **Team-based implementation** -the orchestrator spawns parallel implementation teammates and manages failure recovery. Technical failures escalate to an Opus agent; requirements issues escalate to you

## How It Works

Every ticket goes through four loops:

```
PLANNING → IMPLEMENTATION → DOCUMENTATION → PULL REQUEST
```

**Planning** -Explorer reads your codebase and docs (code is source of truth). Planner breaks the ticket into sub-tasks with complexity ratings. Reviewer checks the plan. You approve before anything gets written.

**Implementation** -The orchestrator spawns implementation teammates in parallel using Agent Teams. Teammates that fail stop and report back. Technical failures (logic bugs, command errors) escalate to an Opus teammate for resolution. Requirements issues (impossible plan, unclear spec) escalate to you for clarification.

**Documentation** -Scout diffs the changes against existing docs. If updates are needed, auditors review each doc file and report findings. You pick which ones to apply.

**Pull Request** -Drafter compiles everything into a PR with a summary, change table, and suggested testing plan. You review it, then a submitter pushes and creates the PR.

The orchestrator (main Claude Code instance) never writes code, never reviews code, never touches files. It reads tickets, launches agents, and talks to you. That's it.

## Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and configured
- [Beads CLI](https://github.com/cosmix/beads) installed (`v0.49.5+`)
- A GitHub repo with Actions enabled
  - GitLab CI and Bitbucket Pipelines support is on the roadmap

## Quick Start

1. **Install into your project:**
   ```powershell
   irm https://raw.githubusercontent.com/Jtonna/starterpack/main/install.ps1 | iex
   ```
   To install a specific version:
   ```powershell
   $env:STARTERPACK_VERSION = "v1.0.0"
   irm https://raw.githubusercontent.com/Jtonna/starterpack/main/install.ps1 | iex
   ```

2. **Initialize beads:**
   ```bash
   bd init --prefix <short-prefix>-
   # Prefix must be ≤8 chars, lowercase, end with hyphen (e.g. "myapp-")
   ```

3. **Create a ticket:**
   ```bash
   bd create --title "Your first task" --type task --priority 2
   ```

4. **Start Claude Code:**
   ```bash
   claude
   ```
   The orchestrator reads `CLAUDE.md`, loads the workflows, and picks up ready tickets.

## Project Structure

```
CLAUDE.md                              # Orchestrator runtime - the brain
install.ps1                            # Install/upgrade script (PowerShell)
release.ps1                            # Release tagging script (maintainer use)
.starterpack/
  workflows/
    WORKFLOW_ENTRY.xml               # Entry points, scope enforcement, branching strategy
    MODELS.xml                       # Model tiers, roles, escalation rules
    BEADS.xml                        # Issue tracker config, prefix management
    WORKFLOW_PLANNING.xml            # Planning loop
    WORKFLOW_IMPLEMENTATION.xml      # Implementation loop
    WORKFLOW_DOCS.xml                # Documentation audit loop
    WORKFLOW_PR.xml                  # Pull request loop
  beads_sync.md                      # How the GitHub Actions sync works
.github/
  workflows/beads-sync.yml            # Beads → GitHub Issues sync trigger
  scripts/beads-sync.sh               # Sync script
.beads/                                # Beads issue database (git-tracked)
```

## Customization

Everything is meant to be tweaked:

- **`.starterpack/config/models.xml`** -Change which models handle which roles. On a budget? Run implementers on Haiku with escalation to Sonnet. Want max quality? Set everything to Opus.
- **`.starterpack/config/beads.xml`** -Add custom issue types, change branch prefix mappings.
- **Workflow files** -Add or remove phases, adjust human gates, change what gets presented for review.

## Background

This came together during the Gastown / Ralph Wiggums era of AI agent development. Autonomous swarms were the hype, but the tooling hadn't caught up. I watched projects pile up technical debt at machine speed -agents confidently shipping broken code, docs rotting within days, token bills climbing with nothing to show for it.

The answer wasn't less AI, it was more structure. Human gates where they matter. Cheap models where they're good enough. Expensive models only when the cheap ones can't hack it. Documentation that gets checked every single time.

This is how I run all my projects now.

## License

[MIT](LICENSE)
