# Javaneh Disposable Database Validation Runbook

## Purpose and Status

This runbook validates the approved Javaneh lifecycle and database-security architecture in a genuinely separate disposable local database. It is an execution guide, not a production migration, and does not establish hosted-project feasibility.

No command in this document is permission to target the previously audited database or a hosted project. All DDL, DML, extensions, role changes, scheduler jobs, concurrency experiments, and cleanup operations are restricted to the disposable instance identified in Section 2.

The approved product behavior is fixed for these tests:

- Exactly three lifecycle states: `registered_draft`, `editing_window`, `submitted_for_evaluation`.
- Before explicit registration, temporary three-step Wizard state exists only in the client. No database session exists.
- Explicit registration creates one session and consumes one of the authenticated user's three idea slots.
- A dossier is created only when completion succeeds.
- Editing is allowed for exactly 168 elapsed hours. There is no early manual submission. Finalization is automatic.
- Registered drafts retain only their current state and revision counter. They have no history table or snapshots.
- Completed dossiers have an initial immutable snapshot and a snapshot for each accepted edit. Failed operations and idempotent retries create no extra snapshot.
- Permanent deletion is allowed in every lifecycle state and cascades to dossier snapshots and idempotency records. No tombstones remain.
- Existing Supabase Auth and the existing three-step Wizard and fields remain unchanged.
- No seven-stage process, new thematic categories, external evaluation integration, or file storage is included.

The scheduler identity is **not decided**. This runbook tests both approved alternatives and requires an explicit approval before implementation.

## 1. Safety Boundaries and Evidence Labels

### 1.1 Strict boundaries

- Never connect this runbook to the previously audited local database or a hosted Supabase project.
- Never use `--linked`, `--project-ref`, a hosted connection string, or any secret from `.env.local`.
- Run all mutations only with an explicitly verified disposable work directory and endpoint.
- Do not use `db reset`, broad Docker prune commands, or cleanup commands whose target is ambiguous.
- Do not make architecture choices based on a local test without the approval gates in Section 13.
- Preserve the existing repository migrations; copy them into the lab instead of editing them.

### 1.2 Evidence categories

The runbook records results in four categories:

1. **Previously verified local facts:** findings from the earlier read-only audit, which apply only to that audited local instance at that time.
2. **Disposable tests:** results that must be produced in the separate lab database.
3. **Hosted preflight:** checks that require a separately authorized hosted-project review and cannot be inferred from local behavior.
4. **Approval gates:** choices that must remain unresolved until the product owner explicitly decides.

Do not mark an unexecuted test as passed.

## 2. Disposable Environment Setup and Isolation

### 2.1 Preconditions

**Purpose:** Select a truly separate instance before changing any database object.

**Mode:** Read-only discovery, then disposable-only setup.

The CLI version is pinned to Supabase CLI `2.122.0`. Its global `--workdir` option was confirmed in that version's CLI help during the previous local audit. Use `--workdir "$LAB_ROOT"` on every CLI invocation.

Create a unique temporary project directory and select unused ports. The values below are examples; check every port in the generated config, not just the database port.

```sh
set -eu

LAB_ROOT="$(mktemp -d /tmp/javaneh-validation.XXXXXX)"
LAB_TAG="${LAB_ROOT##*.}"
LAB_API_PORT=55441
LAB_DB_PORT=55442
LAB_SHADOW_PORT=55440
LAB_STUDIO_PORT=55443

printf 'Lab root: %s\nLab tag: %s\n' "$LAB_ROOT" "$LAB_TAG"
```

Before proceeding, verify:

- The lab directory is outside the repository and unique.
- The CLI reports exactly `2.122.0`.
- Every service port selected for the lab is unused and differs from the audited runtime's ports.
- The runtime uses separate storage and a distinct project/instance identity.
- For Native runtime, documented runtime support confirms a second isolated instance can coexist. A unique work directory and ports alone do not prove storage isolation.
- The selected runtime will not reuse the audited database volume, data directory, or process.

If Native runtime does not document concurrent isolated instances, do not start a second Native instance next to the audited one. Use Docker only if it is available and genuinely isolated, or stop if no separate environment is possible. Do not assume Docker is available.

**Expected:** Unique lab directory and service ports, version-pinned CLI, and documented isolation from the audited instance.

**Stop if:** Instance storage/identity is uncertain, any port overlaps, or Native concurrency/isolation is not established.

### 2.2 Generate config using CLI 2.122.0

**Purpose:** Avoid unverified or invented Supabase config keys.

**Mode:** Mutates only the disposable project directory.

Initialize an empty project using the pinned CLI:

```sh
npx --yes supabase@2.122.0 --workdir "$LAB_ROOT" init
```

Use the generated `supabase/config.toml` as the configuration-schema reference. Change only the project ID and supported port values already emitted by this CLI version. Do not copy the repository config wholesale. Do not manually add `[local_smtp]`; that section was not verified against the pinned CLI schema. Keep email-testing configuration only if `init` generated it, and retain its exact generated section and keys.

The pinned CLI's startup in the next section is the config validation. Do not claim config validity before startup succeeds.

**Expected:** Generated config with unique project ID and ports, and no invented sections or keys.

**Failure:** If startup rejects a key or section, stop and correct only the lab config based on the CLI-generated schema.

### 2.3 Start exactly the disposable runtime

**Purpose:** Start only the lab instance.

**Mode:** Mutating, disposable environment only.

Docker runtime, only when available and isolated:

```sh
npx --yes supabase@2.122.0 --workdir "$LAB_ROOT" start
```

Native runtime, only after documented verification of independent concurrent storage, identity, and ports:

```sh
SUPABASE_EXPERIMENTAL_STACK=1 \
  npx --yes supabase@2.122.0 --workdir "$LAB_ROOT" \
  start --runtime native --eager
```

Do not use a status command or output mode that prints keys or secrets. If the CLI cannot prove the instance target, stop.

**Expected:** The lab runtime starts from `LAB_ROOT` using the lab config.

**Failure:** Any ambiguous target, reused storage, or port collision blocks the test.

### 2.4 Endpoint guard

**Purpose:** Verify every SQL connection before DDL/DML.

**Mode:** Read-only.

Connect explicitly through loopback and the selected lab database port. Use the disposable password interactively if needed; do not put credentials in command history or print them.

```sh
psql -X -h 127.0.0.1 -p "$LAB_DB_PORT" -U postgres -d postgres
```

Before each new SQL connection that will mutate data, run:

```sql
SELECT current_database(), current_user, inet_server_addr(),
       inet_server_port(), version();
```

Confirm the port exactly equals `LAB_DB_PORT`, the address is local, the server is PostgreSQL 17, and the identity is the lab database. Do not rely on the database name `postgres` alone.

**Expected:** Verified loopback endpoint and exact lab port.

**Stop if:** Port, address, server version, or instance identity differs or is ambiguous.

## 3. Baseline Migration Discovery and Copy

**Purpose:** Reproduce the current baseline in the lab without modifying repository migrations.

**Mode:** Read-only discovery, then copies and migrations in the disposable project only.

From the Javaneh repository, discover and canonicalize its root; do not hardcode a workspace path:

```sh
REPO_ROOT="$(git rev-parse --show-toplevel)"
REPO_ROOT="$(cd "$REPO_ROOT" && pwd -P)"
printf 'Discovered repository root: %s\n' "$REPO_ROOT"
```

Manually confirm that the printed path is the intended Javaneh checkout and is not `$LAB_ROOT`. List the migration filenames and check that the baseline files below exist. The currently audited repository contains:

- `20261024090000_initial_idea_schema.sql`
- `20261024090800_revoke_service_role_idea_access.sql`

If the checkout has additional migration files, do not blindly copy/apply them; identify and review their scope first. Copy the approved baseline files into the disposable project's migration directory and compare filenames/checksums with the sources:

```sh
mkdir -p "$LAB_ROOT/supabase/migrations"
cp -- "$REPO_ROOT/supabase/migrations/20261024090000_initial_idea_schema.sql" \
  "$LAB_ROOT/supabase/migrations/"
cp -- "$REPO_ROOT/supabase/migrations/20261024090800_revoke_service_role_idea_access.sql" \
  "$LAB_ROOT/supabase/migrations/"
```

Repeat the endpoint guard, then apply migrations only from the lab work directory:

```sh
npx --yes supabase@2.122.0 --workdir "$LAB_ROOT" migration up --local
```

Never run the migration command from the repository's Supabase workdir, and never link it to a hosted project.

**Expected:** The lab ledger records the reviewed baseline versions and the repository files/checksums are unchanged.

**Failure:** If root validation, file comparison, or target verification fails, stop before migration.

## 4. Approved Schema and Lifecycle Assertions

**Purpose:** Define the architecture the disposable tests must validate. This section is a specification, not migration SQL.

**Mode:** Catalog assertions read-only; test schema creation is disposable-only.

### 4.1 Aggregate root and quota

`idea_sessions` is the lifecycle and quota aggregate root. The approved target has these fields and constraints:

- `id uuid PRIMARY KEY DEFAULT gen_random_uuid()`.
- `user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE`.
- `state text NOT NULL CHECK (state IN ('registered_draft','editing_window','submitted_for_evaluation'))`.
- `current_step smallint NOT NULL CHECK (current_step BETWEEN 1 AND 3)`.
- `draft_data jsonb NOT NULL CHECK (jsonb_typeof(draft_data) = 'object')`.
- `draft_revision bigint NOT NULL DEFAULT 0 CHECK (draft_revision >= 0)`.
- `registration_key uuid NOT NULL`, `registration_hash bytea NOT NULL` with 32-byte SHA-256 check, and `registered_at timestamptz NOT NULL`.
- `created_at`, `updated_at` non-null `timestamptz`.
- `UNIQUE (id,user_id)` and `UNIQUE (user_id,registration_key)`.
- No pre-registration row; no `draft` lifecycle state; no draft-history table.
- The per-user limit is exactly three sessions in all lifecycle states. There is no configurable quota table.

### 4.2 Completed dossier and revision snapshots

`ideas` contains only a completed dossier, one per session:

- `id uuid PRIMARY KEY DEFAULT gen_random_uuid()`.
- `session_id uuid NOT NULL UNIQUE`, `user_id uuid NOT NULL`.
- `dossier jsonb NOT NULL`, `dossier_schema_version smallint NOT NULL DEFAULT 1` constrained to version 1, `dossier_revision bigint NOT NULL CHECK (dossier_revision >= 1)`.
- `completed_at timestamptz NOT NULL`, `edit_deadline_at timestamptz NOT NULL`, `submitted_at timestamptz NULL`, and `created_at`/`updated_at`.
- `UNIQUE (id,session_id,user_id)` and composite FK `(session_id,user_id)` to `idea_sessions(id,user_id) ON DELETE CASCADE`.
- Check `edit_deadline_at = completed_at + interval '168 hours'`.
- The dossier uses exactly the existing Wizard fields: `theme`, `problem`, `affectedPeople`, `possibleCauses`, `proposedSolution`, `beneficiaryGroup`, `expectedOutcome`, and `implementationBarriers`; validate as nonblank strings. Do not add thematic categories.

`idea_dossier_revisions` retains completed-dossier history only:

- `idea_id`, `session_id`, `owner_id`, `revision`, `snapshot_kind`, `dossier`, `captured_at`.
- Primary key `(idea_id,revision)`; revision is positive; revision 1 is `initial`; revisions above 1 are `edit`.
- Composite FK `(idea_id,session_id,owner_id)` to `(ideas.id,ideas.session_id,ideas.user_id) ON DELETE CASCADE`.
- Initial snapshot and current dossier creation happen atomically. Each accepted edit updates current dossier, increments revision, and inserts its snapshot in the same transaction. Rejected edits and idempotent retries add no snapshot.
- Application users cannot update or independently delete snapshots. Use no delete-blocking trigger; parent deletion must cascade through snapshots.

`idea_operation_keys` stores only idempotency receipts, never draft/dossier content. It has session/owner identity, operation, UUID idempotency key, server-computed 32-byte request hash, result revision/metadata, and creation time. It is unique by owner/operation/key and cascades with the session. Registration's key/hash live on the session. Deletion removes all corresponding idempotency state.

Deferred checks at transaction commit must enforce:

- `registered_draft` has zero dossier rows.
- The other two states each have exactly one dossier.
- Current dossier revision matches identical latest snapshot; revisions are contiguous; kinds and timestamps are consistent.
- If parent session deletion has cascaded through dossiers and snapshots, the checker accepts the absent parent.

### 4.3 State transitions and time rule

Only these transitions are allowed:

```text
registered_draft -> editing_window -> submitted_for_evaluation
```

Deletion is allowed in every state. There is no early manual submission. `complete_dossier` captures one `clock_timestamp()` after locks are obtained and sets the exact 168-hour deadline. An edit succeeds only if its post-lock database time is strictly less than the deadline. The scheduler transitions due rows automatically; a delayed scheduler must not extend edit eligibility.

## 5. Roles, Ownership, RLS, and Grants

**Purpose:** Validate restricted definer owners, least privilege, policy coverage, and privilege behavior.

**Mode:** Catalog checks read-only; role/table/policy setup and tests are disposable-only.

### 5.1 Roles and ownership

The application function-owner roles are exactly:

- `idea_rpc_owner`
- `idea_integrity_owner`
- `idea_scheduler_owner`

Each must be `NOLOGIN`, `NOSUPERUSER`, `NOCREATEDB`, `NOCREATEROLE`, `NOINHERIT`, and `NOBYPASSRLS`. Do not make these roles table owners or grant membership to `anon`, `authenticated`, or `service_role`.

PostgreSQL `ALTER FUNCTION ... OWNER TO` requires the caller to own the function (or be superuser), be able to `SET ROLE` to the new owner, and the new owner to have `CREATE` on the function's schema. Test this in a dedicated non-exposed schema such as `lab_owner_probe`, not `public`. Temporarily grant only that schema's `USAGE, CREATE` to the intended role, transfer the probe function, and revoke `CREATE` afterward. Keep tables owned by `postgres`.

Check role attributes and memberships through `pg_roles` and `pg_auth_members`; check function owner through `pg_proc`; check table owner through `pg_class`; check effective schema/table/column privileges with PostgreSQL privilege functions.

**Expected:** Function ownership transfers without custom table ownership or `BYPASSRLS`.

**Stop if:** Transfer requires broad privileges or cannot be performed without a role design change.

### 5.2 Secure function settings and request identity

Every `SECURITY DEFINER` function uses the fixed path:

```text
pg_catalog, pg_temp
```

Fully qualify application objects as `public.*`, Auth helpers as `auth.uid()`/`auth.jwt()`, and pgcrypto functions using the schema discovered from `pg_extension`. Do not rely on unqualified references or dynamic SQL. API roles have TEMP privilege, so `pg_temp` is explicitly last.

At RPC entry, require non-null `auth.uid()` and the expected authenticated JWT role. Never accept caller-supplied owner ID. Test invocation as `authenticated` with local request claims. Inside definer code, assert `current_user` is the intended custom owner and `auth.uid()` still matches the request subject.

### 5.3 RLS target behavior

Enable and `FORCE ROW LEVEL SECURITY` on every application table in the disposable test schema. Function-owner roles must be non-owner and `NOBYPASSRLS`.

Role policy targets and behavior:

- `authenticated`: owner-scoped SELECT only after the direct access test grants; no permanent direct writes for RPC-only mutation.
- `idea_rpc_owner`: owner-scoped policies sufficient for registration, draft save, completion, edits, and permanent session deletion. It may preserve `registered_draft` or perform `registered_draft -> editing_window`, but must not set `submitted_for_evaluation`.
- `idea_integrity_owner`: SELECT-only access to the three tables needed for deferred invariant checks.
- `idea_scheduler_owner`: only due `editing_window` rows and the transition to `submitted_for_evaluation`; no other state transition.

PostgreSQL combines permissive policies with OR and restrictive policies with AND. Remove broad permissive policies; test effective policy behavior. Grant SELECT on every column and referenced relation used in RLS expressions (including `user_id`, `session_id`, and `state`) to the role evaluating those policies. Do not mistake missing SQL privilege errors for successful RLS filtering.

Before interpreting behavior tests, inspect the complete effective policy inventory, including command, target roles, permissive/restrictive mode, `USING`, and `WITH CHECK`:

```sql
SELECT schemaname, tablename, policyname, permissive, roles, cmd,
       qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'idea_sessions', 'ideas', 'idea_dossier_revisions', 'idea_operation_keys'
  )
ORDER BY tablename, policyname;
```

Assert there is no unexpected `PUBLIC`/`{public}` policy or broad permissive policy. Remember that adding a restrictive policy cannot cancel a matching permissive policy that grants broader access; the permissive set is ORed first, then restrictive policies are ANDed.

### 5.4 Grant baseline

The disposable test must verify effective privileges, not only ACL text:

- `anon`: no app-table privileges and no lifecycle RPC EXECUTE.
- `authenticated`: owner-scoped SELECT and EXECUTE only on user-facing RPCs; no direct INSERT/UPDATE/DELETE where mutation is RPC-only.
- `service_role`: no direct app-table privileges and no EXECUTE on lifecycle RPCs or legacy trigger functions, despite Supabase's `BYPASSRLS` attribute.
- `idea_rpc_owner`: only required session/idea/receipt/snapshot privileges, with no scheduler transition.
- `idea_integrity_owner`: SELECT-only on the invariant-check tables.
- `idea_scheduler_owner`: only the exact state and submission-time column updates required for finalization.

Revoke default `PUBLIC` function EXECUTE and grant only intended RPCs. Verify effective EXECUTE for `PUBLIC`, `anon`, `authenticated`, `service_role`, and custom roles. Do not grant broad privileges to make a test pass.

### 5.5 Separate direct-authenticated and definer RLS test suites

Run these as independent suites in the disposable environment.

**Suite A: direct authenticated access.** Temporarily grant only minimum table and column privileges to `authenticated`; define policies explicitly `TO authenticated`. Use synthetic owners A and B, and claims for A. Test:

| Initial state | Operation | Expected | Assertion |
|---|---|---|---|
| B-owned row exists | A SELECTs B row | Zero rows, not privilege error | Count visible rows as A; confirm row remains as test owner |
| No B row for insert | A INSERTs with B user_id | WITH CHECK rejection | Verify INSERT privilege existed before interpreting error |
| B-owned row exists | A UPDATEs B row | Zero rows changed | Confirm row unchanged as test owner |
| A-owned row exists | A changes user_id to B or writes forbidden state | WITH CHECK rejection | Verify UPDATE privilege existed first |
| B-owned row exists | A DELETEs B row | Zero rows deleted | Confirm row remains as test owner |

Then revoke the temporary DML grants and verify direct mutation is absent.

**Suite B: SECURITY DEFINER access.** Create probe functions owned by `idea_rpc_owner`, grant EXECUTE only to `authenticated`, and define policies explicitly for `idea_rpc_owner`. Repeat the same SELECT/INSERT/UPDATE/DELETE ownership tests and invalid WITH CHECK cases through the functions. The probe must record `current_user = idea_rpc_owner`. Verify the function owner has required schema, table, column, and function privileges so an SQL privilege failure is not misreported as RLS isolation.

Add explicit lifecycle authorization probes, separate from ordinary ownership tests:

| Initial state | Role/claims and operation | Expected | Assertion |
|---|---|---|---|
| Owned `editing_window` session | Authenticated user calls an `idea_rpc_owner`-owned probe attempting `editing_window -> submitted_for_evaluation` | Rejected by the RPC-owner policy/guard | Function reports policy/guard rejection; session state remains `editing_window` |
| Owned due `editing_window` session with completed dossier | Scheduler-owned finalizer runs | Success, `editing_window -> submitted_for_evaluation` only | Session is submitted and dossier timestamp is set atomically |
| Owned non-due `editing_window` session | Scheduler finalizer runs | No transition | State remains `editing_window`; no submitted timestamp |
| Owned `registered_draft` or already `submitted_for_evaluation` session | Scheduler-owned transition probe attempts to set submitted state | Rejected or filtered, with no row change | State and dossier timestamps remain unchanged |

For the first probe, verify the called function owner is `idea_rpc_owner`; do not test by connecting as a superuser and infer RLS behavior. For scheduler probes, verify the effective role and required UPDATE column privileges before attributing a denial to RLS.

**Expected for both:** Cross-owner access is filtered or rejected according to command and policy; invalid WITH CHECK operations fail; no cross-owner data or mutation is visible.

**Stop if:** A permission failure prevents RLS evaluation, a broad permissive policy opens access, or a result is ambiguous.

## 6. RPC, Quota, Idempotency, Concurrency, and Deletion Tests

**Purpose:** Validate the approved transaction semantics in a disposable schema/runtime.

**Mode:** All mutation and two-connection race tests are disposable-only.

### 6.1 RPC inventory and expected behavior

Validate these approved entry points (names and parameter shapes are the current target contract; do not use this runbook to implement or silently redesign them):

- `register_idea(registration_key, registration_data)`.
- `save_registered_draft(session_id, expected_revision, idempotency_key, draft_data, current_step)`.
- `complete_dossier(session_id, expected_draft_revision, idempotency_key, dossier)`.
- `edit_dossier(session_id, expected_dossier_revision, idempotency_key, dossier)`.
- `permanently_delete_idea(session_id)`.
- Internal scheduler-only `finalize_expired_dossiers(batch_size)`.

Each user RPC derives identity from `auth.uid()`, checks owner, validates input and state, and uses a fixed search path. Do not create a session or persist temporary Wizard state before explicit registration.

### 6.2 Quota and registration

A per-user transaction-scoped advisory lock serializes registration and permanent deletion. Both operations take the same user lock before counting or deleting. Count every existing session in all three lifecycle states. Registration rejects when the user has three; deletion frees one slot. No quota configuration table exists.

| Initial state | Role/claims and operation | Expected | Assertion |
|---|---|---|---|
| User A has two sessions in mixed states | A registers a new valid idea | Success; third slot consumed | A has exactly three session rows; no idea row yet |
| A has three sessions | A registers another idea | Rejected | Still exactly three rows |
| No row for A, no registration key | A registers malformed fields | Rejected without session | A's session count unchanged |
| Client has unregistered Wizard state only | No RPC called | No database row | Query finds no session for that client-generated draft |

Use a two-connection test for concurrent retries with the same registration key: both submit the same key and identical canonical request hash for user A. Exactly one session is created and both calls resolve to that registration. Repeat with the same key but different request hashes; one request may win, but the other must reject and no second session may appear. Verify the per-user advisory lock serializes registration checks and that the quota remains at most three.

### 6.3 Idempotency order and hashes

Registration serializes on the user lock, checks `(user_id, registration_key)` and request hash before quota count, and returns the existing session for an identical retry. A different hash for the same key is rejected.

For save, completion, and edit, lock and authorize the session first, then look up the receipt. A same-hash existing receipt returns its original result **before** expected-revision, lifecycle, or deadline checks. A different hash is rejected. Only after a receipt miss may the RPC lock the dossier, check state/revision/deadline, perform the transaction, and insert a receipt. A successful retry after deadline or finalization returns the original result and creates no new revision/snapshot. Receipts store hashes/result metadata, not content, and cascade with the session.

Hash canonical JSON/operation/session/expected revision and complete input server-side with SHA-256 using the actual pgcrypto schema. Never accept a client digest.

| Initial state | Operation | Expected | Assertion |
|---|---|---|---|
| Registered draft at revision N | Save with new key, correct expected N | Success, revision N+1 | Latest draft replaced; no draft-history/snapshot rows |
| Same request/key retried | Retry save | Original result | Revision remains N+1; one receipt |
| Same key, changed payload | Retry | Rejected | No additional write |
| Stale expected revision, new key | Save | Rejected | Draft/revision unchanged |
| Existing successful edit receipt, deadline now passed/finalized | Same edit retry and hash | Original result returned | No new snapshot or revision |
| Existing receipt, same key, different hash | Any mutation | Rejected | No changes |
| `editing_window` dossier at revision N, before deadline | Edit uses stale expected revision or invalid dossier under a new key | Rejected | Current dossier/revision unchanged; snapshot count unchanged |
| `editing_window` dossier at/after deadline, new idempotency key | Edit request | Rejected | No dossier update, revision increment, receipt, or snapshot |

### 6.4 Lifecycle, deadline, and concurrency

Only `registered_draft -> editing_window -> submitted_for_evaluation` is permitted. `complete_dossier` creates dossier, initial snapshot, and transition atomically. Edits use `clock_timestamp()` captured after locks and require strict `v_now < edit_deadline_at`. The deadline is completion plus exactly 168 elapsed hours. No manual early submission operation exists.

Lock order:

- Registration: user quota lock, registration receipt lookup/count, insert session.
- Draft save: session row, receipt lookup; on miss validate and update.
- Completion: session row, receipt lookup; on miss insert dossier/snapshot and change state.
- Edit: session row, receipt lookup; on miss dossier row; then post-lock time and validation.
- Deletion: user quota lock, session row, dossier row if present, delete session.
- Scheduler: session rows `FOR UPDATE SKIP LOCKED`, then dossier rows; never take quota lock.

No operation takes session/dossier lock and then quota lock; the scheduler never requests quota lock. This avoids a lock cycle between scheduler and user operations. Validate with two independent connections and synchronization barriers.

| Initial state | Concurrent operations | Expected | Assertion |
|---|---|---|---|
| A has two sessions | Two registrations race | One gets third slot; other rejects | Count is exactly three |
| A has three sessions | Registration races permanent deletion | Serialized outcome; never above three | Count never exceeds three; deleted graph absent |
| One `editing_window` dossier at revision N | Two edits expect N | Exactly one accepted | Current revision N+1 and one new snapshot |
| User A has two sessions and submits the same registration key concurrently on two connections | Same key/hash registration race | One registration; both callers resolve to same session | Exactly one new row and one registration identity |
| User A has two sessions and submits the same registration key concurrently with different hashes | Conflicting registration race | One request wins; the other rejects | Exactly one new row; no silent key reuse |
| Due `editing_window` dossier | Edit races scheduler | Either valid pre-deadline edit commits first or finalization wins; no post-deadline edit | Session final state consistent; no partial snapshot |
| One due and one non-due `editing_window` session | Scheduler finalization batch | Only due session transitions | Due row is submitted; non-due row remains editable |
| Any lifecycle state | Owner permanent delete races edit | Deletion commits or edit completes before deletion; no orphan | Session, dossier, snapshots, receipts all absent after delete |

For exact deadline behavior, test before, equal to, and after the deadline through an internal deterministic time-check helper or controlled test clock. Production RPC must use `clock_timestamp()` after locks. Scheduler delay must not change edit eligibility.

### 6.5 Permanent deletion

Test `permanently_delete_idea` under owner claims from every lifecycle state. It deletes the session; FKs cascade to dossier, all snapshots, and all operation/registration keys. Repeating deletion is a no-op without disclosing another owner's row. Test Auth-user cascade only with a synthetic user created in the disposable Auth schema.

**Expected:** No soft-delete markers or tombstones; no associated content/history/keys remain. Hosted backups are out of scope and require hosted retention review.

## 7. Dossier Revision and Deferred Integrity Tests

**Purpose:** Validate current-dossier/snapshot consistency and immutability.

**Mode:** Deferred triggers, test data, and transactions are disposable-only.

Install deferred constraint-trigger probes on `idea_sessions`, `ideas`, and `idea_dossier_revisions`. At commit, verify final state: `registered_draft` has zero dossier rows; other states have exactly one; revisions are contiguous; revision 1 is `initial`; later revisions are `edit`; and the current dossier equals its latest snapshot. If the parent session/dossier was deleted in the same transaction, accept the cascade outcome.

| Initial state | Transaction | Expected | Assertion after commit / rollback |
|---|---|---|---|
| Registered draft, no dossier | Commit unchanged | Success | Zero dossier rows |
| Registered draft | Add dossier without completion/state transition | Deferred failure | Transaction rolls back |
| Registered draft | Complete with dossier rev 1, initial snapshot, editing-window transition | Success | One dossier and matching rev-1 snapshot |
| Editing window at revision N | Update dossier to N+1 and insert matching edit snapshot | Success | Current dossier equals latest snapshot |
| Any completed dossier | Omit snapshot, wrong kind, revision gap, or mismatched content | Deferred failure | No partial state persists |
| Editing window at revision N | Submit an edit rejected for stale revision, invalid input, or expired deadline | Failure | Current dossier and revision unchanged; snapshot count unchanged |
| Snapshot exists | Application/RPC role UPDATE snapshot | Permission/trigger rejection | Snapshot unchanged |
| Snapshot exists | Application/RPC role independently DELETE snapshot | No DELETE privilege; if tested by test owner, deferred check rejects inconsistent history | Snapshot remains after rejected transaction |
| Session with dossier/snapshots | Owner deletes parent session | Success | FK cascade removes dossier and all snapshots |

Use an update-only snapshot guard; do not create a delete-blocking trigger. Verify that legitimate parent `ON DELETE CASCADE` succeeds. Composite snapshot FK must tie idea, session, and owner exactly. No standalone application delete path is allowed.

## 8. pgcrypto Validation

**Purpose:** Verify SHA-256 availability and least privilege.

**Mode:** Catalog checks are read-only; optional grants/test calls are disposable-only.

The earlier audit found pgcrypto 1.3 installed in `extensions`, with digest overloads executable by `PUBLIC`. Recheck the disposable environment using `pg_extension`, `pg_namespace`, and `pg_proc`; never assume the schema. Check effective EXECUTE for each custom role and use the schema-qualified digest function. If reducing PUBLIC EXECUTE in the lab, grant only the needed overload to the RPC role.

**Expected:** Catalog-reported namespace matches the function call; the RPC role can hash requests without broad application grants.

**Stop if:** Extension is unavailable or the namespace/permissions cannot be safely resolved.

## 9. Legacy Function, Trigger, and ACL Inspection

**Purpose:** Discover actual schemas and verify obsolete state synchronization and timestamp triggers.

**Mode:** Catalog inspection is read-only; behavior tests are disposable-only.

Do not assume the functions are in `public`. Discover function schema/overloads and properties:

```sql
SELECT n.nspname AS function_schema,
       p.proname,
       p.oid::regprocedure AS identity,
       pg_get_userbyid(p.proowner) AS owner,
       p.prosecdef AS security_definer,
       p.proconfig,
       p.proacl
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE p.proname IN ('set_updated_at', 'sync_idea_session_status')
ORDER BY n.nspname, p.proname, p.oid::regprocedure::text;
```

Discover attached triggers through `pg_trigger`, joining each trigger's relation and function. Explicitly check for the old `ideas_sync_session_after_insert` and `ideas_sync_session_after_delete` triggers, but determine actual schema and relation from catalogs. Check effective EXECUTE for `PUBLIC`, `anon`, `authenticated`, and `service_role`, plus function dependencies in `pg_depend`.

In disposable transactions:

- Insert a valid legacy idea for an owned `in_progress` session; if the old insert trigger exists, verify it changes the session to `submitted`.
- Delete that idea; if the old delete trigger exists, verify it reopens the session to `in_progress`.
- Update a permitted draft/answer field and verify the actual discovered `set_updated_at()` trigger advances `updated_at`.
- Verify `service_role` and other API roles' function EXECUTE directly; do not infer from table grants.

If a candidate architecture migration is later tested, apply only to the lab and verify obsolete sync triggers are removed or safely replaced, the legacy function cannot change approved lifecycle state, and EXECUTE is revoked from unintended roles. Confirm the valid timestamp trigger still works.

**Expected:** Actual schemas, owners, search paths, ACLs, dependencies, and behavior are documented. No legacy trigger silently changes the approved lifecycle after the candidate migration.

## 10. pg_cron Scheduler Identity Validation

**Purpose:** Distinguish scheduling acceptance, stored username, connection login identity, invoker current role, and finalizer definer role.

**Mode:** Source inspection is read-only; extension, functions, grants, test table, schedule, and job are disposable-only.

### 10.1 Version-specific source review

Check installed pg_cron version and use the exact corresponding source tag/build. The prior finding references pg_cron 1.6.4. Inspect both standard libpq and background-worker execution paths for role LOGIN checks and failure handling. Do not infer background-worker behavior from libpq or from a different version. Do not assume `cron.use_background_workers` bypasses PostgreSQL LOGIN eligibility.

A successful `cron.schedule()` proves only that scheduling was accepted. `cron.job.username` proves only stored identity. Neither proves execution.

### 10.2 Identity probe

Create a disposable log table and two functions:

- `lab_cron_invoker_probe()`, explicitly `SECURITY INVOKER`. At entry, it records `session_user` and `current_user`. It calls the finalizer and records whether the call returned. After return, it records both identities again.
- A finalizer probe, `SECURITY DEFINER`, owned by `idea_scheduler_owner`, with the intended fixed `search_path`, RLS and restricted privileges. Inside its body, after the definer switch, it records `session_user` and `current_user`, then records successful access to the intended finalizer action.

The scheduled command must be simply:

```sql
SELECT lab_cron_invoker_probe();
```

Schedule the disposable probe at the approved one-minute cadence using `* * * * *`. Use a unique lab job name and ensure the disposable command calls the probe that in turn invokes the finalizer. The production design remains automatic finalization on a monitored one-minute schedule; this probe validates that cadence without scheduling anything in the audited database.

Do not put `SET ROLE` in the scheduled command. Do not make the invoker probe `SECURITY DEFINER` or place identity logging inside a definer wrapper.

Interpretation:

| Capture point | `session_user` | `current_user` |
|---|---|---|
| Invoker probe entry | Actual cron execution login identity | Effective role at invoker entry; absent SET ROLE, ordinarily equals session_user |
| Inside SECURITY DEFINER finalizer | Same actual cron execution login identity | `idea_scheduler_owner` after definer switch |
| Invoker probe after finalizer returns | Same cron execution login identity | Restored invoker execution role |

Verify all four stages independently: schedule accepted, `cron.job.username`, actual execution (run status plus identity log), and successful intended-finalizer access. A job that is accepted or stored but never runs has failed validation.

Monitor `cron.job_run_details` for successful runs on the one-minute cadence and failures, and query the disposable lifecycle tables for due `editing_window` rows remaining after the expected run interval. The test passes only when due rows are finalized and non-due rows remain editable; a missing run, failed job, or overdue due row is a failure requiring investigation. Record the observed cadence and execution errors before unscheduling the lab job.

### 10.3 Preserve both scheduler models as alternatives

Do not adopt either model in this runbook.

**Model A: NOLOGIN execution owner.** `idea_scheduler_owner` remains `NOLOGIN`, `NOSUPERUSER`, `NOBYPASSRLS`, owns the `SECURITY DEFINER` finalizer, and is the candidate cron username. Test whether the exact installed pg_cron version can schedule and actually run the job as this role. `SET ROLE` before `cron.schedule` is not proof.

**Model B: separate LOGIN execution role.** `idea_scheduler_owner` remains NOLOGIN and owns the finalizer. A separate `idea_scheduler_login` may be evaluated with LOGIN, no elevated attributes, only minimum database CONNECT/schema USAGE/finalizer EXECUTE, and no direct application-table mutation privileges. Schedule under that login identity; verify `cron.job.username`, actual `session_user`, invoker `current_user`, definer `current_user`, and successful finalizer call. This role would be able to invoke the finalizer directly, so the finalizer must enforce due-row checks and must not expose unsafe caller-controlled operations.

For each model, record the exact pg_cron execution mode tested, source version, username stored, job status/error, identity log, and finalizer result. If Model A fails, record failure; do not change it to LOGIN. If Model B succeeds, do not silently adopt it. The scheduler identity choice requires explicit user approval before implementation.

**Expected:** Only actual successful execution under the tested role counts as validated.

**Stop if:** NOLOGIN cannot execute and there is no explicit decision to use Model B; LOGIN behavior, function identity, or finalizer access remains ambiguous; or a broader privilege is needed.

## 11. Hosted Supabase Preflight

**Purpose:** Identify what local testing cannot prove. This is a future, separately authorized hosted review, not part of this runbook's tests.

Do not connect to a hosted project during disposable validation. Before any hosted deployment, an authorized operator must inspect:

- Actual hosted PostgreSQL version, role attributes, role memberships, schema ACLs, object owners, default privileges, and migration identity capabilities.
- Whether custom NOLOGIN roles and function ownership transfer are permitted without BYPASSRLS/table ownership.
- Actual pgcrypto installation namespace and function grants.
- Hosted pg_cron version, preload/configuration, job execution mode, LOGIN checks, `cron.job.username`, actual `session_user`, definer `current_user`, and finalizer success.
- Existing data, migration history, legacy statuses, ownership consistency, per-user counts, and any ambiguous historical records.
- Backup/restore evidence and provider backup-retention behavior for permanent deletion.

Local success does not prove any hosted item.

## 12. Cleanup

**Purpose:** Remove only the disposable instance and lab resources.

**Mode:** Destructive, disposable environment only.

Before cleanup, verify `LAB_ROOT`, unique project ID, and runtime identity again. For CLI-managed runtime:

```sh
case "$LAB_ROOT" in
  /tmp/javaneh-validation.*) ;;
  *) printf '%s\n' "Refusing unexpected LAB_ROOT"; exit 1 ;;
esac

npx --yes supabase@2.122.0 --workdir "$LAB_ROOT" stop --no-backup
```

For Native runtime, use its documented per-instance shutdown only after confirming the disposable instance identity. Remove only resources labeled with the unique lab project ID. Never use broad prune commands. If identity is ambiguous, do not delete; ask an operator to identify the lab resources.

## 13. Final Readiness and Approval Gates

| Classification | Current status |
|---|---|
| Previously verified local facts | The earlier audit observed PostgreSQL 17.11, Supabase CLI 2.122.0, pgcrypto 1.3 in `extensions`, pg_cron available/preloaded but not installed, local `postgres` with CREATEROLE and BYPASSRLS, and no rows in the audited local idea/Auth tables at audit time. These facts apply only to that local instance and time. The audited database must not be used by this runbook. |
| Must be tested in disposable environment | Runtime isolation and generated config validity; baseline migration copy/ledger; custom role creation and ownership transfer; definer execution/claims; effective schema/table/column/function privileges; both direct and definer RLS suites; lifecycle, quota, idempotency, concurrency, deadline, and deletion; deferred snapshot integrity/cascade; legacy trigger/function behavior and ACLs; pgcrypto access; pg_cron job acceptance, stored identity, actual execution identity, and finalizer success. No unexecuted test is passed. |
| Requires hosted preflight | Hosted role and schema permissions, object/grant state, data/migration history, extension placement, pg_cron version/execution identity, and backup-retention behavior. |
| Requires explicit user approval | Choice between the NOLOGIN scheduler execution model and the separate LOGIN scheduler model if needed. No choice is made here. |

**Readiness rule:** Do not call the architecture validated until all required disposable tests pass. Do not call it ready for hosted deployment until hosted preflight passes. If pg_cron cannot execute under the selected identity, stop for the explicit scheduler decision. Preserve Auth and the three-step Wizard unchanged throughout.
