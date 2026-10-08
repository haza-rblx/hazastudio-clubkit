# Quest milestones + quota + Robux/manual rewards (2026-10-08)

Owner request: PARKLAB "event absen" — one streak quest, three milestones (7 days 50 R$ ×100,
14 days 50 R$ ×150, 21 days "Voucher undian 8 bit"), Robux paid manually, claims and daily
check-ins visible on the dashboard. Event starts **2026-10-09**; owner chose to ship everything at
once. Decisions are in `CONTEXT.md` § Event board ("Owner decisions 2026-10-08").

## Rules (owner decisions)

- Strict streak: one skipped WIB day → the next check-in starts at 1 (all streak quests).
- Milestone claimable ⇔ current progress ≥ threshold, not yet claimed, not blocked, slots left.
  A reset takes back unclaimed milestones.
- Check-in and claim are one button: a claimable milestone turns the button into "Claim <reward>";
  one press = check-in (if not yet today) + claim. Failure → button stays a claim (retry).
- Quota: first-come slots per milestone, counted by the VPS across servers. Full → "Check in".
- Robux reward: recorded only, paid manually. At most **one Robux reward per player per quest**.
  Requires membership of the venue group (`Config.Group.GROUP_ID`); non-member → Roblox join
  prompt, then the claim.
- Manual reward: free text, recorded only, no one-per-quest rule.
- Every milestone claim goes to the VPS first (dashboard log + quota); in-game rewards
  (membership/title/xp) are granted after the VPS accepts.
- Dashboard only (no Discord webhooks): claims per milestone with Sent/Pending, daily check-in log.

## Contract

### Board (existing `GET /game/:key/v3/event-board`) — quest gains `milestones`

```json
{ "id": 12, "category": "...", "title": "...", "description": "...",
  "goal":   { "type": "streak", "value": 21 },
  "reward": { "type": "manual", "value": "Voucher undian 8 bit" },
  "milestones": [
    { "id": 31, "value": 7,  "reward": { "type": "robux",  "value": "50" }, "quota": 100 },
    { "id": 32, "value": 14, "reward": { "type": "robux",  "value": "50" }, "quota": 150 },
    { "id": 33, "value": 21, "reward": { "type": "manual", "value": "Voucher undian 8 bit" }, "quota": null }
  ],
  "startDate": "2026-10-09", "dueDate": "2026-10-31" }
```

- `milestones`: 1–5 entries, ascending strictly by `value`; `id` = stable row id (never reused).
- `goal.value` / `reward` = the **last** milestone (old readers keep working).
- Reward types: `membership` (Tier1..Tier3) | `title` (≤40 chars) | `xp` (1..1e6) |
  `robux` (integer string 1..100000) | `manual` (free text 1..40 chars).
- `quota`: positive integer or null (unlimited).
- A quest without milestones (old rows) is sent with one synthesized milestone
  `{ id: 0, value: goal.value, reward, quota: null }` — kit also synthesizes it if absent.

### Quota — `GET /game/:key/v3/event-quota` (game auth, same as event-board)

`{ "milestones": { "31": { "claimed": 37, "quota": 100 }, "32": { "claimed": 0, "quota": 150 } } }`
Only milestones with a quota on visible (not ended) quests. Kit polls every 20 s while any exists.

### Claim — `POST /game/:key/v3/event-claims` (game auth)

Request `{ "questId": 12, "milestoneId": 31, "userId": 1, "username": "a", "displayName": "A" }`

One transaction:
1. milestone exists on a non-deleted quest of this game, quest active today (WIB) → else
   `{ ok:false, reason:"not_found" | "inactive" }`
2. existing claim for (milestone, user) → `{ ok:true, slot, already:true }` (idempotent)
3. reward `robux` and the user has a robux claim on another milestone of this quest →
   `{ ok:false, reason:"robux_taken" }`
4. quota set and claimed ≥ quota → `{ ok:false, reason:"quota_full" }`
5. insert; `slot` = 1-based claim order on that milestone →
   `{ ok:true, slot, claimed, quota }`

### Release — `POST /game/:key/v3/event-claims/release` (game auth)

`{ questId, milestoneId, userId }` → deletes that claim if not marked sent (in-game grant
failed after the VPS accepted). `{ ok:true }`.

### Check-in log — `POST /game/:key/v3/event-checkins` (game auth)

`{ "entries": [ { "questId": 12, "userId": 1, "username": "a", "displayName": "A",
"day": "2026-10-09", "streak": 3 } ] }` (≤ 200 entries). Upsert unique (quest, user, day).
`{ ok:true, stored:n }`.

### Dashboard (owner auth)

- Quest form: milestone rows (threshold, reward type + value, optional quota), add/remove, max 5.
  Lock: a milestone with claims cannot be removed nor its reward type changed; quota cannot go
  below its claimed count.
- Claims view per quest: per milestone, rows slot # / username / display name / userId /
  claimed at (WIB) / status. Sent toggle records who + when; filter Pending.
- Check-in log per quest: per day count + list of players (username, streak).

## Kit (this repo)

- `DailyQuestDomain` RESET_GAP 3 → 2.
- `EventBoardDomain`: `Milestone`, milestones on Quest, `claims` map on progress entry (legacy
  `claimedAt` = milestone "0"), robux/manual reward types, claimable/robux-exclusivity rules.
- `EventBoardController`: claim per milestone (VPS first → DataStore claim → grant), auto-claim
  on check-in, group check (GetGroupsAsync, not cached IsInGroup), `needGroup` → client
  `PromptJoinAsync` → re-claim, quota poll, check-in log queue.
- UI: milestone list + slots in the quest popup, button label, calendar badge — mocked from the
  owner's components first.
