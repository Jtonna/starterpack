# Starterpack

A plug-and-play AI agent orchestration setup for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). It gives your agents a structured workflow with human checkpoints, tiered model usage, mandatory documentation upkeep, and git-tracked tickets.

## Why it exists

One agent making a small mistake is fine. A swarm of agents all making small mistakes at the same time is not.

I've been running agent swarms since December in crude, rudimentary forms. Claude Code finally offers an official solution, not as powerful, but far more convenient. That said, swarms have fundamental workflow structure problems; assumptions cascade into bad decisions, and as the gastown and ralph wiggums era showed, token burn is inefficient and context usage gets sloppy. This is my attempt at a solution I can actually live with. It reduces cascading failures, enforces stricter workflows based on my personal preferences, keeps the human in the loop, and provides enough pushback to counter ADHD vibe coding. It also solves some project management headaches by tracking all work as GitHub Issues.

Arguably the most important part is a structured workflow to create new behaviors and lifecycles, something ive had issues with across various solutions.

## Installing

### Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and configured
- A GitHub repo with Actions enabled

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/Jtonna/starterpack/main/install.sh | bash
```

Pin a specific version:

```bash
curl -fsSL https://raw.githubusercontent.com/Jtonna/starterpack/main/install.sh | bash -s -- --version v0.7.8
```

Skip auto-commit:

```bash
curl -fsSL https://raw.githubusercontent.com/Jtonna/starterpack/main/install.sh | bash -s -- --no-commit
```

### Start Claude Code

```bash
claude
```

The orchestrator reads `CLAUDE.md`, loads the manifests, and picks up ready tickets. That's it.

## Hackable

The starterpack is designed to be modified. Two behavior files ship specifically for this: `create-behavior.xml` and `create-lifecycle.xml`. These define the rules, constraints, and XML skeleton templates for writing your own behaviors and lifecycles. There's also a dedicated authoring lifecycle (`authoring-behaviors-and-lifecycles.xml`) that walks you through the full process: drafting, a rule-violation review pass, a contradiction/redundancy review pass, and registration in the manifests.

What you can customize:

- **Behaviors**: modify agent capabilities independently. Each file owns one concern. Add a new behavior by creating a file and registering it in the manifest.
- **Lifecycles**: add or remove phases, change which behaviors load, adjust what gets presented at human gates.
- **MODELS_AND_ROLES.xml**: change model assignments per role. On a budget? Run implementers on Haiku with escalation to Sonnet. Want max quality? Set everything to Opus.

## About Behaviors and Lifecycles

The starterpack uses a three-layer architecture:

**Behaviors**: HOW to do things. Self-contained instruction sets with zero cross-references. Each behavior defines one concern (git workflow, escalation protocol, response format, etc.). Fix one without touching anything else. An agent can load a behavior without needing to understand the full system.

**Lifecycles**: WHEN to do things. They reference behaviors by name and define a sequence of phases with actors and transitions. Lifecycles never embed behavior content. The orchestrator loads referenced behaviors separately when composing agent instructions.

**Manifests**: the discovery layer. Lightweight indexes the orchestrator reads at startup so it knows what's available without loading everything into context. It pulls in specific files on demand.

### The standard flow

Every ticket goes through five phases, with a human gate at every transition:

**Entry**: routes incoming work. Existing ticket, spec file, or ad-hoc request. Creates tickets if needed and selects a branching strategy.

**Planning**: an explorer reads your codebase and docs. A planner breaks the ticket into sub-tasks with complexity ratings. A reviewer checks the plan. You approve before anything gets written.

**Implementation**: the orchestrator spawns parallel implementation teammates. Failures stop and report back. Technical failures escalate to an Opus agent; requirements issues escalate to you. After you approve, the orchestrator pushes to remote.

**Documentation**: a scout diffs the changes against existing docs. If updates are needed, auditors review each doc file and report findings. You pick which ones to apply.

**Pull Request**: a drafter compiles everything into a PR with a summary, change table, and suggested testing plan. You review it, then a submitter pushes and creates the PR.

The orchestrator (main Claude Code instance) never writes code, never reviews code, never touches files. It reads tickets, launches agents, and talks to you.

### On-demand lifecycles

Not every ticket follows the standard five-phase flow. On-demand lifecycles are alternative entry points registered in the manifest with `on-demand="true"`. They run independently and can feed back into the standard workflow. For example, `NIGHTLY_AUTONOMOUS_RUN` is a pre-flight gate for tickets labeled `autonomously-nightly` — it assesses whether the ticket has enough information for an AI agent to execute autonomously, then either activates autonomous mode on the standard workflow or posts clarifying questions on the GitHub issue and exits.

## About MODELS_AND_ROLES.xml

This is the system configuration file for who does what at which model tier. The orchestrator reads it at startup alongside the manifests.

### Model tiers

| Tier | Model | Used for |
|------|-------|----------|
| Reasoning | Opus | Planning, review, debugging, escalation, team coordination |
| Worker | Sonnet | Standard implementation tasks |
| Light | Haiku | Simple/mechanical work: renames, moves, boilerplate |

### Roles

Eleven roles are defined out of the box: orchestrator, explorer, planner, plan-reviewer, implementer, light-implementer, doc-scout, doc-auditor, doc-writer, pr-drafter, and submitter. Each role is assigned a default model tier.

### Dispatch

During planning, the planner assigns complexity ratings (light, standard, complex) to each sub-task. The orchestrator uses these ratings to select the starting model tier at dispatch: light tasks go to Haiku, standard tasks to Sonnet, complex tasks to Opus.

### Escalation

Cheaper models escalate up when they fail. A Haiku agent that gets stuck escalates to Sonnet. Sonnet escalates to Opus. Technical failures follow this chain automatically. Requirements failures escalate to you.

### Customization

Edit the roles section in `MODELS_AND_ROLES.xml` to change model assignments. Budget-conscious: set implementers to light with escalation to worker then reasoning. Max quality: set everything to reasoning.

## Comment Queue

The starterpack uses a comment queue (`.github/comment-queue.json`) to post comments on GitHub Issues as `github-actions[bot]` rather than the user's personal account. This is used by the nightly autonomous workflow to post clarification questions and progress updates.

How it works:

1. An agent appends `{"issue": 42, "body": "comment text"}` entries to `.github/comment-queue.json`
2. On push, the `comment-sync` GitHub Actions workflow detects the change
3. The workflow posts each queued comment via `gh issue comment` (appearing as `github-actions[bot]`)
4. The queue is cleared to `[]` and committed — the early-exit guard in the script prevents recursive triggers by exiting when the queue is already empty

## License

[MIT](LICENSE)
