---
name: remige-dev-issue-workflow
description: >-
  Worktree-first development and issue handling for the remige repository
  (nichenqin/remige). Use when fixing a bug, implementing a feature, handling
  an issue, opening a PR, merging it, or recording work in Teable. Enforces one
  isolated git worktree per task and one Teable ledger record per bug/feature in
  base bsepeKiBBNc43DmkQTZ, linked to the branch, worktree, verification, GitHub
  PR, and the release that ships it. Routine PRs merge automatically after green
  CI; major ones wait for the user. Releases batch the merged fixes and run
  through the `release` skill. Triggers: "remige", "fix this bug", "implement
  this feature", "handle this issue", "open a PR", "merge it", "jevify",
  "修复 bug", "开发功能", "问题处理", "提交 PR", "合并", "记录到 Teable".
---

# Remige Dev Issue Workflow

Every behavioral change starts as a **bug** or **feature** record, is implemented
in its own **worktree**, ends with a **merged, recorded PR**, and joins the
**pending release batch** until a version ships it.

## Invariants

1. **Worktree-first.** All repository inspection that guides implementation,
   reproduction, edits, tests, commits, pushes, and PR creation happen in an
   isolated worktree. The primary checkout is read-only. Never edit it.
2. **One record per issue.** Search the ledger before creating. Never create a
   duplicate bug or feature record.
3. **The record is the source of truth** for the issue key (`BUG-<n>` /
   `FEAT-<n>`), branch, worktree, verification, and PR.
4. **Prove before fixing.** Reproduce the bug before editing; write numbered
   acceptance criteria before building a feature.
5. **Re-read every write.** A misspelled `singleSelect` value or wrong field
   name can leave a cell empty without failing the write.
6. **Routine merges itself; major waits.** After green CI, judge the PR (step
   8). Routine changes merge and update the record; major changes stop for the
   user's explicit confirmation.
7. **Releases are batches.** Merging never publishes anything. A merged record
   stays `Fixed` / `Shipped` until the `release` skill ships it in a version,
   then it becomes `Verified` / `Closed`. Report the pending count after every
   merge.

## Ledger

Base: `https://app.teable.ai/base/bsepeKiBBNc43DmkQTZ`

| | Bugs | Features |
| --- | --- | --- |
| Table | `tblImWhI073evDfnk98` | `tbl1zfUoytIxstJVjL2` |
| Default view | `viwGtn3DfTniQeHNTEG` | `viwy6mDKs2sOUCBQ08s` |
| Auto ID | `Bug ID` → `BUG-<n>` | `Feature ID` → `FEAT-<n>` |
| PR field | `Fix PR` | `PR` |
| Release field | `Releases` → Releases table | `Releases` → Releases table |
| Reporter | `Reported By`, `Reported At` | `Requested By`, `Requested At` |
| Extra field | `Root Cause` | `Acceptance` |

Shared fields: `Title` (primary), `Description`, `Status`, `Priority`, `Repo`,
`Branch`, `Worktree`, `PR Status`, `GitHub Issue`, `Verification`, `Links`,
`Releases`, `Created`, `Updated`.

Canonical record URL:

```
https://app.teable.ai/base/bsepeKiBBNc43DmkQTZ/table/<tableId>/<viewId>?recordId=<recId>
```

### Status lifecycle

| Stage | Bugs | Features | `PR Status` |
| --- | --- | --- | --- |
| Record created | `Open` | `Proposed` | — |
| Worktree created, implementation started | `In Progress` | `In Progress` | — |
| PR opened | `In Review` | `In Review` | `Open` |
| PR merged | `Fixed` | `Shipped` | `Merged` |
| Acceptance passed on the released artifact | `Verified` | `Closed` | `Merged` |
| Rejected / abandoned | `Won't Fix` | `Won't Do` | `Closed` |

`Verified` requires the acceptance path, not just green tests. Merge routine PRs
yourself after green CI; stop for a major classification (step 8). `Fixed` /
`Shipped` means merged but not released; the `release` skill moves records to
`Verified` / `Closed` once the version containing them is published and verified.

### Access

Use the **`teable` MCP server** for `app.teable.ai`. Tool names are namespaced
per client (`mcp__teable_get_records`, `mcp__teable__get-records`, …); match on
the server name and the tool name.

- Read: `get-records { tableId, recordId?, search?, projection }`
- Create: `create-records { tableId, header, records, typecast: true }`
- Update: `update-records { tableId, header: ["recordId", …], records, typecast: true }`
- Delete: `delete-records { tableId, recordIds }`
- Current operator (optional): `call-api { method: "GET", url: "/auth/user" }`

CLI fallback when the MCP server is not mounted. Clear local proxies in the same
invocation:

```bash
env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY \
  -u all_proxy -u ALL_PROXY teable record get \
  --base-id bsepeKiBBNc43DmkQTZ --table-id <tableId> \
  --projection '["Title","Bug ID","Status","Fix PR"]'
```

### Write recipes

Create a bug (the auto-number field is read-only, so omit it):

```json
{
  "tableId": "tblImWhI073evDfnk98",
  "header": ["Title", "Description", "Status", "Priority", "Repo",
             "Reported By", "Reported At", "GitHub Issue"],
  "records": [[
    "Session expires after five minutes",
    "Expected: 24h session.\nActual: logout after 5m.\nRepro: ...",
    "Open", "P2", "owner/name", "alice",
    "2026-10-19T09:00:00+08:00",
    "https://github.com/owner/name/issues/12"
  ]],
  "typecast": true
}
```

Create a feature:

```json
{
  "tableId": "tbl1zfUoytIxstJVjL2",
  "header": ["Title", "Description", "Status", "Priority", "Repo",
             "Requested By", "Requested At", "Acceptance"],
  "records": [[
    "Add JSON output to the CLI",
    "One `--json` flag on the list command.",
    "Proposed", "P2", "owner/name", "alice",
    "2026-10-19T09:00:00+08:00",
    "1. `molt list --json` exits 0.\n2. stdout parses as JSON."
  ]],
  "typecast": true
}
```

Read back the created record and capture `recId`, `Bug ID` / `Feature ID`:

```json
{
  "tableId": "tblImWhI073evDfnk98",
  "recordId": "rec…",
  "projection": ["Title", "Bug ID", "Status", "Branch", "Worktree",
                 "Fix PR", "PR Status"]
}
```

Update progress. The first header element must be `recordId`; `""` skips a
field, `null` clears it:

```json
{
  "tableId": "tblImWhI073evDfnk98",
  "header": ["recordId", "Status", "Branch", "Worktree", "Fix PR", "PR Status"],
  "records": [[
    "rec…", "In Review", "fix/BUG-12-session-timeout",
    "/Users/me/projects/repo.fix-BUG-12-session-timeout",
    "https://github.com/owner/name/pull/34", "Open"
  ]],
  "typecast": true
}
```

The update example targets Bugs; use `PR` instead of `Fix PR` for Features.


Use full ISO 8601 timestamps with offset for date fields. `Repo` is
`owner/name` from `git remote get-url origin`; if there is no remote, use the
absolute repository path.

CLI fallback for writes:

```bash
env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY \
  -u all_proxy -u ALL_PROXY teable record create \
  --base-id bsepeKiBBNc43DmkQTZ --table-id <tableId> \
  --header '["Title","Status","Priority","Repo"]' \
  --records '[["…","Open","P2","owner/name"]]' --typecast

env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY \
  -u all_proxy -u ALL_PROXY teable record update \
  --base-id bsepeKiBBNc43DmkQTZ --table-id <tableId> \
  --header '["recordId","Status","Fix PR","PR Status"]' \
  --records '[["rec…","In Review","https://github.com/owner/name/pull/34","Open"]]' \
  --typecast
```


## Workflow

### 1. Intake and ledger

Resolve the repository root with `git rev-parse --show-toplevel`. If the cwd is
not the repository the user named, use that path instead; if neither is a git
repository, stop and ask.

Classify the work:

- **Bug** — existing behavior is wrong, regressed, or fails.
- **Feature** — new or intentionally changed behavior is wanted.
- **Neither** (docs-only, dependency bump with no behavior change) — use a
  worktree, skip the ledger, and say so. If the change turns out to alter
  behavior, create the record before editing.

Search for an existing record first:

```json
{
  "tableId": "tblImWhI073evDfnk98",
  "projection": ["Title", "Status", "Fix PR"],
  "search": { "value": "<distinctive title words>" },
  "take": 20
}
```

Search the chosen table; if the user supplied a GitHub issue URL, search both
tables for that URL. If a matching record exists, use it and do not create
another record.

If the user gives a Teable record URL, extract `recordId` and read it; do not
create another record. If the user gives an issue key (`BUG-12` / `FEAT-3`),
fetch the table with a projection that includes the auto ID and match the value.
If the record is already `Verified`, `Closed`, `Shipped`, or `Won't Fix`,
confirm the reopen with the user before changing its status, and append new
evidence instead of overwriting the existing description.


Create the record with `Status` = `Open` (bug) or `Proposed` (feature), and
`Priority` defaulting to `P2`. Use the user's language for `Title` and
`Description`. For a bug, include expected vs actual and the first reproduction
path. For a feature, include the acceptance criteria if they are already known.

**Done when:** the record read-back shows a non-empty auto ID and the intended
status, and the canonical record URL and issue key are captured.

### 2. Create and enter the worktree

Fetch first, then select the base explicitly. A bare `--create` can branch from
a stale local default:

```bash
git -C <repo> fetch origin
git -C <repo> symbolic-ref --short refs/remotes/origin/HEAD   # e.g. origin/main
```

Branch name: `<fix|feat>/<KEY>-<slug>`, for example
`fix/BUG-12-session-timeout` or `feat/FEAT-3-json-output`.

Create with worktrunk, without changing the current shell directory:

```bash
wt -C <repo> switch --create <branch> --base origin/<default> \
  --yes --no-cd --format=json
```

Read the JSON: `path` is the worktree, `base_branch` confirms the base. On
`Branch <branch> already exists`, rerun without `--create` to enter that
existing worktree; if it is not based on the intended branch, stop and ask.

Enter the worktree (`cd <path>`, or pass it as the harness's working
directory). Verify:

```bash
pwd
git -C <path> rev-parse --abbrev-ref HEAD   # exact issue branch
git -C <path> rev-parse HEAD                # baseline SHA
```

If `pwd` is still the primary checkout, stop; do not edit there. Run every
subsequent command with `cwd=<path>` or `git -C <path>` so the isolation does
not depend on a transient `cd`.

Update the record: `Branch`, `Worktree`, `Status` = `In Progress`.

**Done when:** the worktree path and branch are verified and the record
read-back shows both plus `In Progress`.

### 3. Prove the bug or fix the acceptance

- **Bug:** reproduce the reported behavior with the exact command or UI path.
  Capture the failing output, environment, and preconditions. Add `Root Cause`
  only after the evidence supports it. If it cannot be reproduced, record what
  was tried and do not claim a fix.
- **Feature:** write numbered, observable acceptance criteria into
  `Acceptance`. Each criterion needs a command or UI path and a pass/fail
  bound. Resolve ambiguity with the user before building.

**Done when:** the record contains either a failing reproduction or the
numbered acceptance criteria.

### 4. Implement

Follow the repository's own instructions (`AGENTS.md`, `CLAUDE.md`,
`CONTRIBUTING.md`, `Makefile`, package scripts). Make the smallest correct
change at the right layer. Add or update tests and docs. Do not mix unrelated
refactors into the change.

Commit in the worktree with the issue key in the subject, for example
`fix(BUG-12): extend session timeout` or `feat(FEAT-3): add --json output`.
Match the repository's existing commit style if it differs.

**Done when:** the code, tests, and docs are committed and
`git -C <path> status --porcelain` is empty.

### 5. Verify

Run the repository's canonical checks plus the exact reproduction or
acceptance path. For UI changes, observe the actual rendered surface, not just
unit tests. Never substitute "tests pass" for the original reproduction.

Write `Verification` in the record:

```text
Command: <copy-paste command>
Observed: <exit code / key output>
Acceptance: <criterion 1..n> — pass
```

**Done when:** the original bug no longer reproduces, or every acceptance
criterion passes, and the evidence is in the record.

### 6. Open the PR

Push the issue branch, then create a ready-for-review PR against the selected
base:

```bash
git -C <path> push -u origin <branch>
gh pr create --base <default> --title "<KEY> <summary>" --body "<body>"
```

The title must contain the exact issue key. The body must contain:

```markdown
Issue: <canonical record URL>
Issue ID: BUG-12
Repo: owner/name
Branch: fix/BUG-12-session-timeout
Summary: <what changed and why>
Verification: <commands and observed results>
```

For bugs, include the reproduction and root cause. For features, include the
acceptance criteria. Do not include secrets, tokens, customer data, or PII.

Capture the PR URL and number with `gh pr view --json number,url,state`.

**Done when:** the PR exists, its title contains the issue key, and its body
contains the record URL.

### 7. Link the PR back

Update the record:

- `Fix PR` (Bugs) or `PR` (Features) = PR URL
- `PR Status` = `Open` (or `Draft` only if the user asked for a draft)
- `Status` = `In Review`

Re-read the record and confirm every field. A misspelled option or field name
does not fail the write; it leaves the cell empty.

**Done when:** the record read-back shows the PR URL, `PR Status = Open`, and
`Status = In Review`.

### 8. CI, classify, merge

Wait for checks on the PR head:

```bash
gh pr checks <number> --watch
```

A failed check is in scope: fix it in the same worktree, push, and re-run the
proving path. Never merge with a red or pending check.

Classify the PR before merging — jevify it: freeze this rubric first, then judge
the PR:

- **Unit:** title, body, changed paths, the diff capped at 24k with a truncation
  marker, and the CI result.
- **`risk`** — `choice`:
  - `routine`: every change is required by the issue, follows existing patterns,
    and leaves public interfaces, schemas, stored data, and release files intact.
  - `major`: it breaks a public interface, schema, config format, or migration;
    touches auth, permissions, credentials, payments, or data deletion; edits
    release, version, tag, or distribution files; or changes behavior the issue
    does not ask for.

Use `judge` for one PR and `judge_batch` when several are in flight. Escalate to
yourself and read the diff when the choice's top probability is below 0.8, the
diff was truncated, or the judge errored. The `major` examples are hard
overrides: they hold even when the judge answers `routine`.

- **Major** — reply with the reason, the risk, and the scope the confirmation
  covers; wait. Nothing merges and the record stays `In Review`.
- **Routine** — merge with the repository's merge method (default
  `gh pr merge <number> --squash --delete-branch`), then confirm
  `gh pr view --json state` returns `MERGED`.

After merge:

- `PR Status` = `Merged`
- Bug `Status` = `Fixed`; Feature `Status` = `Shipped`
- Link the record to the release that will ship it: when a `Planning` / `In
  Progress` Releases record exists, add the record to its `Bugs` / `Features`
  link. Otherwise it is pending and joins the next batch.
- Run the acceptance path on the merged commit and record the evidence. The
  release gate re-runs it on the published artifact.

If the PR is closed unmerged, set `PR Status` = `Closed` and return `Status` to
`Open` / `Planned` or the rejection value.

Optionally remove the worktree after merge, when it has no uncommitted work and
the user asked for cleanup. `wt remove` deletes the merged branch by default;
add `--no-delete-branch` when the branch should be kept:

```bash
wt -C <repo> remove <branch> --no-delete-branch
```

**Done when:** CI is green and either `gh pr view --json state` reads `MERGED`
with the record showing `Merged` plus `Fixed` / `Shipped`, or the major
classification is escalated with its reason and the PR is untouched.

### 9. Pending release handoff

Merging is not shipping. Read the pending set from the ledger: records with
`PR Status` = `Merged` (or a direct commit with Bug `Status` = `Fixed` /
Feature `Status` = `Shipped`) whose `Releases` link points at no `Released`
record. This catches records whose `Status` lagged behind the merge.

Then read the Releases table `tblxyEt9f1iPUF4s5u0` for the latest `Released`
version and date, and apply the readiness rules owned by the `release` skill.
When a rule fires, hand off to the `release` skill and cut the batch there;
otherwise report how many fixes are waiting and why the batch holds.

**Done when:** the report states the pending count, the record keys, and either
the readiness rule that fired or the waiting reason.

### 10. Report

Reply in the user's language. Include:

- Issue key and canonical record URL
- Branch and worktree path
- PR URL and CI state
- Merge outcome: merged automatically, or waiting for the user's confirmation
- Verification commands and observed results
- Pending release: N fixes merged but unreleased, with their keys
- Release readiness verdict: the rule that fires, or why the batch waits
- Current `Status`

If a ledger write, worktree, push, CI, merge, or release step failed, state the
gap; do not claim the workflow completed.

## Guardrails

- Never edit the primary checkout. If the worktree is not the active cwd, stop
  and correct it before touching files.
- Never create a second record for the same issue; search first.
- Never claim a fix without a pre-fix reproduction and a post-fix proof.
- Never set `Verified` from local tests alone; it requires the acceptance path.
- Auto-merge a routine PR once CI is green; a `major` classification waits for
  the user's explicit confirmation.
- Publish only through the `release` skill and the repository's release path;
  merging a fix never publishes a version.
- Never force-push or delete an unmerged branch without explicit user permission.
- Never put secrets, tokens, customer records, or PII into the ledger or PR.
- If the worktree or PR exists but the ledger write fails, keep the work and
  report the ledger gap; do not invent record IDs or URLs.
