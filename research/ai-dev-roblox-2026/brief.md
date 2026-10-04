# Research Brief — AI developments that improve an agent-driven Roblox dev workflow

**Date:** 2026-10-01
**Depth:** standard (3–5 sub-agents, 1 follow-up round, 15+ sources)
**Requester context:** Solo Roblox game developer (Hazastudio Club Kit — Luau via Rojo, sold to multiple buyers). Works with AI coding agents (Cursor / Claude Code / Mimo) in a repo-driven workflow: agent instructions in AGENTS.md/CLAUDE.md, custom skills in `.mimocode/skills/` (grill-with-docs, diagnosing-bugs, code-review, tdd-luau, mcp-studio), MCP bridge to live Roblox Studio, portable git tooling, strict Luau typing, release/changelog discipline.

## Refined question

What are the most significant AI developments of the last ~12 months (Oct 2025 – Oct 2026) that could concretely improve how this user works with AI coding agents on Roblox projects — including: (a) agent skills/methodologies worth adopting, (b) agentic coding tooling & workflow patterns, (c) Roblox-specific AI capabilities (official and community), and (d) anything else actionable for a solo dev selling a Luau kit to multiple buyers?

## Scope

**In:**
- Agent skills ecosystems (Claude Agent Skills format, community registries, notable skills relevant to game dev / solo dev)
- Frontier coding models & agentic tools (capabilities that change daily workflow, not benchmarks for their own sake)
- Agent workflow patterns: memory, planning, subagents, hooks, verification loops, spec-driven development
- Roblox official AI: Assistant, MCP server, Studio features, Luau AI tooling
- Community Roblox AI tooling (Rojo/MCP bridges, Luau codegen, testing AI)
- Actionable adoption guidance for a solo dev with buyer-facing release discipline

**Out:**
- Image/video/music generation models (not relevant to this workflow)
- AI business/industry news, funding, policy (unless directly affecting tooling)
- Generic LLM benchmarks with no workflow implication
- Non-Roblox game engines (Unity/Unreal) except where a pattern transfers

## Assumptions

- User reads Indonesian; report will be written in Indonesian (sources in English).
- "Skills" means both the formal Agent Skills format and reusable agent workflows/methodologies.
- User's primary pain points (from repo): context drift across sessions, buyer-config safety, Studio-vs-code sync, regression risk in a multi-buyer kit, limited solo QA bandwidth.

## Angles

1. **F1 — Agent Skills ecosystem & reusable agent methodologies.** Claude Agent Skills format status, official/community skill registries, notable skills applicable to game dev / solo dev / release discipline; how skills are discovered/installed/versioned in late 2026.
2. **F2 — Frontier coding models & agentic IDEs (last 12 months).** What current top models/agents (Claude, GPT, others) do differently for repo-scale coding: long-horizon agents, subagents, memory, hooks; Cursor/Claude Code/Windsurf feature developments; what actually changed daily workflows per practitioner reports.
3. **F3 — Roblox official AI & Luau tooling.** Roblox Assistant evolution, official MCP server, Studio AI features, Luau type-inference/AI tooling, Creator Hub AI roadmap announcements in the last 12 months.
4. **F4 — Community Roblox AI tooling & MCP bridges.** State of roblox-studio-mcp / Rojo AI integrations, Luau codegen quality reports, AI-driven testing for Roblox (TestEZ, Jest-lua with agents), real dev-forum practitioner experience.
5. **F5 — Agent workflow patterns for solo devs (verification, memory, spec-driven).** Patterns like plan-mode-first, TDD-with-agents, eval loops, persistent agent memory files, guardrails for agent edits in production repos; practitioner evidence on what stuck vs. hype.
