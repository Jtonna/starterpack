# Starterpack

A plug-and-play AI agent orchestration setup for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). It came out of months of working with AI agent swarms 10+ hours a day and constantly running into the same problems.

## Why This Exists

If you've spent any time with AI agents writing code, you've probably hit these:

- **Vibe coding** — agents ship code with no human review, subtle bugs compound over time
- **Documentation drift** — the codebase evolves but docs don't, so future agent sessions work off stale info and things start breaking in weird ways
- **Token burn** — Opus doing work that Haiku handles fine
- **Lost context** — scattered commits with no traceability, agents forgetting what they were doing mid-session

One agent making a small mistake is fine. A swarm of agents all making small mistakes at the same time is not.

## What It Does

Starterpack gives Claude Code a structured workflow with human checkpoints, tiered model usage, and mandatory documentation upkeep:

- **Human gates** — nothing ships without your approval. Not planning, not code, not docs, not the PR
- **Tiered models** — Opus plans and reviews, Sonnet/Haiku implement. Cheaper models escalate to Opus automatically when they get stuck
- **Doc audits every time** — every ticket triggers a documentation review, not just when someone remembers
- **Git-tracked tickets** — [Beads](https://github.com/cosmix/beads) issues live in your repo, sync to GitHub Issues, and tie directly to branches and commits
- **Team-based implementation** — the orchestrator spawns parallel implementation teammates and manages failure recovery. Technical failures escalate to an Opus agent; requirements issues escalate to you

## Architecture

The starterpack uses a three-layer architecture with strict separation of concerns:

```
MANIFESTS → LIFECYCLES → BEHAVIORS
(what exists)  (when to do it)  (how to do it)
```

### Manifests — high-level, low-context indexes

Manifests are lightweight summaries that tell the orchestrator what's available without loading everything into context. The orchestrator reads these at session start and loads individual files on demand.

- **`BEHAVIORS_MANIFEST.xml`** — lists every behavior with a one-paragraph summary and which roles it applies to
- **`LIFECYCLE_MANIFEST.xml`** — lists every lifecycle phase with a summary and which behaviors it uses
- **`AGENT_TEAMS.xml`** — model tiers, agent roles, dispatch rules, and team constraints

The orchestrator never needs to read all behavior files upfront. It reads the manifest, knows what's available, and pulls in specific files when it needs them.

### Lifecycles — when things happen

Lifecycle files define the orchestration sequence: what phases run, in what order, with what gates. They reference behaviors by name using `<uses-behavior>` tags but contain zero implementation details about _how_ to do something.

```xml
<!-- lifecycle/implementation.xml -->
<uses-behavior name="git-with-beads" />
<uses-behavior name="escalation" />
<uses-behavior name="scope-enforcement" />
```

The orchestrator loads a lifecycle file when entering a phase, then loads the referenced behaviors and includes them in the instructions it gives to sub-agents.

### Behaviors — how to do things

Behavior files are self-contained instruction sets. Each one defines _how_ to do something — git workflow rules, escalation protocols, response formats — without referencing any other files. Zero cross-references.

This means:
- **Fix a behavior** without touching any lifecycle
- **Fix a lifecycle** without modifying any behavior
- **Compose custom lifecycles** by mixing different behaviors for different use cases
- **Tell a sub-agent** to load specific behaviors without it needing to understand the full system

The orchestrator can also dynamically compose instructions by combining behaviors that aren't in any predefined lifecycle — useful for one-off tasks or custom workflows that don't fit the standard sequence.

## How It Works

Every ticket goes through five phases:

```
ENTRY → PLANNING → IMPLEMENTATION → DOCUMENTATION → PULL REQUEST
```

**Entry** — Routes incoming work. Existing ticket, spec file, or ad-hoc request. Creates tickets if needed, selects branching strategy.

**Planning** — Explorer reads your codebase and docs (code is source of truth). Planner breaks the ticket into sub-tasks with complexity ratings. Reviewer checks the plan. You approve before anything gets written.

**Implementation** — The orchestrator spawns implementation teammates in parallel using Agent Teams. Teammates that fail stop and report back. Technical failures escalate to an Opus teammate. Requirements issues escalate to you. After you approve, the orchestrator pushes to remote.

**Documentation** — Scout diffs the changes against existing docs. If updates are needed, auditors review each doc file and report findings. You pick which ones to apply.

**Pull Request** — Drafter compiles everything into a PR with a summary, change table, and suggested testing plan. You review it, then a submitter pushes and creates the PR.

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
   The orchestrator reads `CLAUDE.md`, loads the manifests, and picks up ready tickets.

## Project Structure

```
CLAUDE.md                                          # Orchestrator bootstrap — points to manifests
install.ps1                                        # Install/upgrade script (PowerShell)
release.ps1                                        # Release tagging script (maintainer use)
.starterpack/
  agent_instructions/
    BEHAVIORS_MANIFEST.xml                         # Index of all behaviors (load on demand)
    LIFECYCLE_MANIFEST.xml                         # Index of all lifecycle phases
    AGENT_TEAMS.xml                                # Model tiers, roles, dispatch rules
    behaviors/                                     # HOW — self-contained, zero cross-references
      git-with-beads.xml                           #   Branching, commits, push, beads integration
      escalation.xml                               #   Failure protocol, model-tier escalation chains
      scope-enforcement.xml                        #   File scope limits, out-of-scope reporting
      sub-task-tracking.xml                        #   Sub-task progress as ticket comments
      documentation-structure.xml                  #   Doc model: single-project, monorepo layouts
      pr-template.xml                              #   PR body template
      human-gate.xml                               #   Approval protocol, per-lifecycle gate contexts
      response-format.xml                          #   LIFECYCLE: {name} // {message} prefix format
    lifecycle/                                     # WHEN — reference behaviors by name only
      entry.xml                                    #   Entry routing, branching strategy selection
      planning.xml                                 #   Planning loop: explore → draft → review → gate
      implementation.xml                           #   Impl loop: dispatch → monitor → escalate → gate → push
      docs.xml                                     #   Documentation audit loop
      pr.xml                                       #   PR loop: draft → gate → submit
  hooks/
    post-merge                                     # Auto-import beads after merge
  beads_sync.md                                    # How the GitHub Actions sync works
.github/
  workflows/beads-sync.yml                         # Beads → GitHub Issues sync trigger
  scripts/beads-sync.sh                            # Sync script
.beads/                                            # Beads issue database (git-tracked)
```

## Customization

Everything is meant to be tweaked:

- **`AGENT_TEAMS.xml`** — Change which models handle which roles. On a budget? Run implementers on Haiku with escalation to Sonnet. Want max quality? Set everything to Opus.
- **Behavior files** — Modify agent capabilities independently. Each file owns one concern. Add a new behavior by creating a file and adding it to the manifest.
- **Lifecycle files** — Add or remove phases, adjust which behaviors are loaded, change what gets presented at human gates.
- **`human-gate.xml`** — Customize what information is presented at each approval checkpoint per lifecycle.
- **`response-format.xml`** — Change the response prefix format to match your team's preferences.

### Adding a new behavior

1. Create a new file in `.starterpack/agent_instructions/behaviors/`
2. Add an entry to `BEHAVIORS_MANIFEST.xml` with a summary and applicable roles
3. Add `<uses-behavior name="..." />` to any lifecycle that should use it

No other files need to change.

### Composing custom lifecycles

The orchestrator isn't limited to the predefined lifecycle sequence. Since behaviors are self-contained, you can:

- Create a new lifecycle file that references any combination of behaviors
- Have the orchestrator dynamically instruct a sub-agent with specific behaviors for a one-off task
- Skip the lifecycle files entirely and compose behavior instructions directly for ad-hoc work

The manifests are the discovery layer. The behaviors are the instruction layer. The lifecycles are just one way to compose them.

## Background

This came together during the Gastown / Ralph Wiggums era of AI agent development. Autonomous swarms were the hype, but the tooling hadn't caught up. I watched projects pile up technical debt at machine speed — agents confidently shipping broken code, docs rotting within days, token bills climbing with nothing to show for it.

The answer wasn't less AI, it was more structure. Human gates where they matter. Cheap models where they're good enough. Expensive models only when the cheap ones can't hack it. Documentation that gets checked every single time.

This is how I run all my projects now.

## License

[MIT](LICENSE)
