# CLAUDE.md — Starterpack Development

This repository **is** the starterpack — the source for an agent orchestration framework
that gets installed into other projects. Do not activate the orchestrator persona defined
in `.starterpack/CLAUDE.md`; that file is a distributable meant for consuming projects.

## What this system is

The starterpack provides structured agent workflows through two primitives:

- **Behaviors** (`.starterpack/agent_instructions/behaviors/`) — self-contained instruction
  sets that define *how* to do something. Each behavior is independently loadable with zero
  external dependencies.
- **Lifecycles** (`.starterpack/agent_instructions/lifecycle/`) — phase sequences that define
  *when* to do things. Lifecycles reference behaviors by name and define ordered phases with
  actors, actions, and transitions.

Both are registered in their respective manifests:
- `BEHAVIORS_MANIFEST.xml` — index of all behaviors
- `LIFECYCLE_MANIFEST.xml` — index of all lifecycles and execution sequence

## Making changes to behaviors and lifecycles

There is an authoring lifecycle (`AUTHORING_BEHAVIORS_AND_LIFECYCLES`) with two supporting
behaviors that define the rules for creating and modifying these files:

- **`create-behavior`** — authoring rules, structural constraints, and XML template for behaviors
- **`create-lifecycle`** — authoring rules, structural constraints, and XML template for lifecycles

Follow these when adding or updating any behavior or lifecycle file. They cover naming
conventions, required elements, manifest registration, and review criteria.
