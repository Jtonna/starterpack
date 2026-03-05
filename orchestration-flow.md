## Orchestration Flow Diagram

<details>
<summary>Click to expand full ASCII flow</summary>

```
╔═══════════════════════════════════════════════════════════════════════════════════════╗
║                          STARTERPACK ORCHESTRATION FLOW                             ║
╚═══════════════════════════════════════════════════════════════════════════════════════╝

  ┌─────────────────────────────────────────────────────────────────────────────────┐
  │                        CLAUDE.md — AGENT RUNTIME                               │
  │                                                                                │
  │  <role> "You are an orchestrator. You do NOT write code..."                    │
  │  <session-start> Read LIFECYCLE_MANIFEST → BEHAVIORS_MANIFEST → MODELS_AND_    │
  │                  ROLES                                                         │
  │                                                                                │
  │  <agent-routing> Teammates skip orchestrator role + session-start tasks        │
  │  <dispatch-mode> Nightly uses blocking sub-agents; interactive uses Teams      │
  └─────────────────────────────────────────────────────────────────────────────────┘
                                        │
          ┌─────────────────────────────┤
          │                             │
          v                             v
  ┌───────────────┐           ┌─────────────────┐
  │ NIGHTLY AUTO  │           │  INTERACTIVE     │
  │ (on-demand)   │           │  (human starts)  │
  └───────┬───────┘           └────────┬────────┘
          │                            │
          v                            │
  ┌───────────────┐                    │
  │ DETECT        │                    │
  │ gh issue list │                    │
  │ has nightly?  │                    │
  │  no → EXIT    │                    │
  │  err → EXIT   │                    │
  └───────┬───────┘                    │
          │ yes                        │
          v                            │
  ┌───────────────┐                    │
  │ ASSESS        │                    │
  │ issue info    │                    │
  │ sufficient?   │                    │
  └──┬─────┬──────┘                    │
     │     │                           │
     │     v                           │
     │  ┌──────────────┐               │
     │  │ROUTE_INCOMPLETE│             │
     │  │post questions │              │
     │  │via queue      │              │
     │  │→ EXIT         │              │
     │  └──────────────┘               │
     │ COMPLETE                        │
     v                                 │
  ┌───────────────┐                    │
  │ROUTE_COMPLETE │                    │
  │auto-approve   │                    │
  │all gates      │                    │
  └───────┬───────┘                    │
          │                            │
          └────────────────────────────┤
                                       │
                                       v
╔═════════════════════════════════════════════════════════════════════════════════════╗
║  ENTRY LIFECYCLE                                                                   ║
║                                                                                    ║
║  ┌──────────────────┐                                                              ║
║  │ IDENTIFY_ENTRY   │  Orchestrator (opus)                                         ║
║  │ Which path?      │                                                              ║
║  └──┬───┬───┬───────┘                                                              ║
║     │   │   │                                                                      ║
║     │   │   └── SPEC_FILE ──────┐                                                  ║
║     │   │                       v                                                  ║
║     │   │              ┌────────────────────┐                                      ║
║     │   └── AD_HOC ──→ │TICKET_AND_BRANCH   │  Orchestrator (opus)                 ║
║     │                  │SETUP                │  Create issues, select base branch   ║
║     └── EXISTING ────→ │                    │                                      ║
║                        └──┬──────┬──────────┘                                      ║
║                           │      │                                                 ║
║                           │      └── SPEC_FILE path only ──┐                       ║
║                           │                                v                       ║
║                           │                    ┌───────────────────┐                ║
║                           │                    │SPEC_FILE_APPROVAL │                ║
║                           │                    │HUMAN_GATE         │                ║
║                           │                    └───┬─────┬────────┘                ║
║                           │                        │     │ rejected → back to       ║
║                           │                        │     │ TICKET_AND_BRANCH_SETUP  ║
║                           │                approved│     └──────────────────────┘   ║
║                           │                        │                               ║
║                           v                        v                               ║
║                     ┌──────────────────┐                                           ║
║                     │ BRANCH_SETUP     │  light-tier sub-agent (haiku)             ║
║                     │ git checkout -b  │  create branch, push                      ║
║                     │ git push         │                                           ║
║                     └────────┬─────────┘                                           ║
╚══════════════════════════════╪═════════════════════════════════════════════════════╝
                               │
                               v
╔═════════════════════════════════════════════════════════════════════════════════════╗
║  PLANNING LIFECYCLE                                                                ║
║                                                                                    ║
║  ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐    ┌──────────┐  ║
║  │ INTAKE   │────→│ DRAFT    │────→│ REVIEW   │────→│HUMAN    │───→│ HANDOFF  │  ║
║  │          │     │          │     │          │     │  GATE    │    │          │  ║
║  │ Explorer │     │ Planner  │     │ Plan     │     │          │    │ Post plan│  ║
║  │ (opus)   │     │ (opus)   │     │ Reviewer │     │ rejected │    │ to issue │  ║
║  │ read-only│     │ sub-tasks│     │ (opus)   │     │    │     │    │          │  ║
║  │          │     │ + complex│     │          │     │    └─────┼──→ │ DRAFT    │  ║
║  └──────────┘     │ ratings  │     └──────────┘     └──────────┘    └────┬─────┘  ║
║                   └──────────┘                                          │         ║
║                   Each sub-task gets: light / standard / complex        │         ║
╚═════════════════════════════════════════════════════════════════════════╪═════════╝
                                                                         │
                               v─────────────────────────────────────────┘
╔═════════════════════════════════════════════════════════════════════════════════════╗
║  IMPLEMENTATION LIFECYCLE                                                          ║
║  Interactive: Agent Teams (TeamCreate) | Nightly: blocking Task sub-agents         ║
║                                                                                    ║
║  ┌──────────┐     ┌──────────────────────────────────────────────┐                 ║
║  │ LAUNCH   │────→│ DISPATCH                                     │                 ║
║  │          │     │ Orchestrator = Team Lead (opus)               │                 ║
║  │ Create   │     │                                              │                 ║
║  │ Agent    │     │  Complexity → Model Tier:                    │                 ║
║  │ Team     │     │    light    → haiku  (light-implementer)     │                 ║
║  └──────────┘     │    standard → sonnet (implementer)           │                 ║
║                   │    complex  → opus   (implementer)           │                 ║
║                   └────────────┬─────────────────────────────────┘                 ║
║                                │                                                   ║
║                                v                                                   ║
║                   ┌──────────────────────┐                                         ║
║                   │ MONITOR              │  No timeout/watchdog                    ║
║                   │ Receive messages     │  Stuck teammates run forever            ║
║                   │ Track success/fail   │                                         ║
║                   └────────────┬─────────┘                                         ║
║                                │                                                   ║
║                                v                                                   ║
║                   ┌──────────────────────┐                                         ║
║                   │ EVALUATE             │                                         ║
║                   │ All pass? ──────────────→ HUMAN_GATE                           ║
║                   │ TECHNICAL fail? ─────┐                                         ║
║                   │ REQUIREMENTS fail? ──┼─→ HUMAN escalation                      ║
║                   └──────────────────────┘                                         ║
║                          │                                                         ║
║                          v                                                         ║
║                   ┌──────────────┐                                                 ║
║                   │ ESCALATE     │  Spawn opus teammate w/ failure context          ║
║                   │ (opus)       │  Resolved? → back to DISPATCH                   ║
║                   │              │  Still stuck? → HUMAN                            ║
║                   └──────────────┘                                                 ║
║                                                                                    ║
║  ┌──────────┐     ┌──────────┐                                                     ║
║  │HUMAN     │────→│ PUSH     │────→ HANDOFF                                        ║
║  │  GATE    │     │ (haiku)  │     Proceed to DOCS                                 ║
║  │rejected →│     │ git push │                                                     ║
║  │ DISPATCH │     └──────────┘                                                     ║
║  └──────────┘                                                                      ║
╚═══════════════════════════════════════════════════════════════════════╪═════════════╝
                                                                       │
                               v───────────────────────────────────────┘
╔═════════════════════════════════════════════════════════════════════════════════════╗
║  DOCS LIFECYCLE                                                                    ║
║                                                                                    ║
║  ┌──────────┐                                                                      ║
║  │ SCOUT    │  Doc Scout (opus, read-only)                                         ║
║  │ Triage:  │                                                                      ║
║  └──┬─┬─┬───┘                                                                      ║
║     │ │ │                                                                          ║
║     │ │ └─ NO_CHANGES ──────────────────────────────────────────→ HANDOFF          ║
║     │ │                                                                            ║
║     │ └─── TRIVIAL ──→ HUMAN_GATE ──→ APPLY (sonnet) ──────────→ HANDOFF          ║
║     │                                                                              ║
║     └───── CHANGES ──→ AUDIT ──→ HUMAN_GATE ──→ APPLY (sonnet) → HANDOFF          ║
║                        (opus,     rejected → AUDIT                                 ║
║                        per-file)                                                   ║
╚═══════════════════════════════════════════════════════════════════════╪═════════════╝
                                                                       │
                               v───────────────────────────────────────┘
╔═════════════════════════════════════════════════════════════════════════════════════╗
║  PR LIFECYCLE                                                                      ║
║                                                                                    ║
║  ┌────────────────┐    ┌──────────┐    ┌──────────────────────────────────────┐     ║
║  │PREPARE_AND_     │──→│ CI_GATE  │──→│ HANDOFF                              │     ║
║  │SUBMIT           │   │ (haiku)  │   │                                      │     ║
║  │ (opus)          │   │          │   │  More children? ──→ PLANNING (loop)  │     ║
║  │ push, create PR │   │ PASS ────┼─→ │  Feature branch done? ──→ FINAL_PR  │     ║
║  │ Closes #N or    │   │ FAIL ──→ │   │  All done? ──→ COMPLETE             │     ║
║  │ Relates to #N   │   │ fix+retry│   │                                      │     ║
║  └────────────────┘   │ NONE ────┼─→ └──────────────────────────────────────┘     ║
║                        │ TIMEOUT→ │                                                ║
║                        │  human   │    ┌──────────┐    ┌──────────────┐             ║
║                        └──────────┘    │ FINAL_PR │──→│FINAL_CI_GATE │──→ DONE     ║
║                                        │ (opus)   │   │ (haiku)      │             ║
║                                        │ epic PR  │   └──────────────┘             ║
║                                        │ → main   │                                ║
║                                        └──────────┘                                ║
╚════════════════════════════════════════════════════════════════════════════════════╝


╔═════════════════════════════════════════════════════════════════════════════════════╗
║  AGENT TYPE SUMMARY                                                                ║
║                                                                                    ║
║  ┌─────────────────┬────────────┬──────────────────────────────────────────────┐    ║
║  │ Agent Type      │ Model Tier │ Spawned Via                                 │    ║
║  ├─────────────────┼────────────┼──────────────────────────────────────────────┤    ║
║  │ Orchestrator    │ opus       │ Session root (CLAUDE.md <role>)             │    ║
║  │ Explorer        │ opus       │ Task tool (sub-agent)                       │    ║
║  │ Planner         │ opus       │ Task tool (sub-agent)                       │    ║
║  │ Plan Reviewer   │ opus       │ Task tool (sub-agent)                       │    ║
║  │ Implementer     │ sonnet     │ Agent Team teammate (IMPLEMENTATION only)   │    ║
║  │ Light Impl.     │ haiku      │ Agent Team teammate (IMPLEMENTATION only)   │    ║
║  │ Doc Scout       │ opus       │ Task tool (sub-agent)                       │    ║
║  │ Doc Auditor     │ opus       │ Task tool (sub-agent)                       │    ║
║  │ Doc Writer      │ sonnet     │ Task tool (sub-agent)                       │    ║
║  │ PR Drafter      │ opus       │ Task tool (sub-agent)                       │    ║
║  │ Submitter       │ haiku      │ Task tool (sub-agent)                       │    ║
║  └─────────────────┴────────────┴──────────────────────────────────────────────┘    ║
║                                                                                    ║
║  Key: Task tool sub-agents = standard Claude Code sub-agents                       ║
║       Agent Team teammates = Agent Teams (IMPLEMENTATION, interactive mode)         ║
║       Nightly mode uses blocking Task sub-agents instead of Agent Teams             ║
║       HUMAN_GATE = hard block, or auto-approved in nightly mode                    ║
╚════════════════════════════════════════════════════════════════════════════════════╝
```

</details>
