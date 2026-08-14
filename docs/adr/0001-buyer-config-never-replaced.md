# ADR 0001 — Buyer-owned config is never replaced; fill-forward only

**Status:** Accepted
**Date:** 2026-08-14

## Context

Buyers edit `ClubKitConfig.luau` and `Secrets.luau` after installing the Kit. Every engine update needs a way to deliver *new* config keys without destroying the buyer's existing values. The naive options were: (a) ship a full config file and tell buyers to re-merge by hand on every update, or (b) never add config keys after launch.

Both fail in practice: (a) guarantees lost buyer values and support tickets eventually; (b) freezes the product's configurability.

## Decision

`ClubKitConfig.luau` and `Secrets.luau` are **buyer-owned**: no release channel (source sync or RBXM) ever replaces them. New config keys reach buyers via **fill-forward**: missing keys are added additively from `ClubKitConfigSchema` — by the plugin after an engine update (source patch), and at runtime in-memory via `ConfigBootstrap`. Existing buyer values always win.

Consequence for development: adding a config field means updating **both** the schema and the template config; removing or renaming a key is a breaking change requiring a migration note in the release folder.

## Consequences

- Engine updates are safe to apply blindly — buyer data survives.
- The schema is the single source of truth for config keys; template and fill-forward both derive from it.
- Renames/removals of config keys are breaking changes and must be treated like DataStore key migrations.
- Any code or tooling that writes the whole config file is a bug by definition.
