---
name: squadkit
role: Orchestrate it — multi-agent crews with the roles → squads → crews vocabulary
oneLiner: Multi-agent team coordination — spawn role-aware crews for execution or read-only discovery, end to end.
commands:
  - /squadkit:init
  - /squadkit:spawn-team
  - /squadkit:agent-team-retro
summary: >
  squadkit introduces a small coordination model — a role is one agent with a
  fixed contract, a squad is a role-cohesive group, a crew is a team-lead
  driving one or more squads. Spawn execution crews on a feature branch or
  discovery crews that produce blueprint comments on issues, with init and a
  SessionStart hook keeping role context alive across resumes.
---

squadkit is the team-shaped sibling to swarmkit's parallel agents.
