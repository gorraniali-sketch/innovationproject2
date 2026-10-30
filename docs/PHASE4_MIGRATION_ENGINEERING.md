# Phase 4 Migration Engineering

## Status and Scope

These files author the approved lifecycle model as an additive, staged database layer. They have not been executed or validated against PostgreSQL. The existing public `idea_sessions` and `ideas` tables remain the legacy application model; no data mapping or application cutover is included.

Do not deploy until the hosted migration ledger, actual schema, legacy rows, role/ownership capabilities, and extension placement have been inspected. This repository does not establish that the hosted database is empty or matches the local migration history.

## Migration Order

Apply only after independently verifying that the hosted migration history contains the two existing baseline migrations and that their objects match the repository:

1. `20261024090000_initial_idea_schema.sql` creates the existing legacy public tables, timestamp triggers, owner policies, and `sync_idea_session_status` triggers.
2. `20261024090800_revoke_service_role_idea_access.sql` removes legacy table grants from `service_role`.
3. `20261030100000_phase4_lifecycle_schema.sql` creates and validates the three non-login owner roles, the private `idea_lifecycle` schema, and its four additive tables and constraints.
4. `20261030101000_phase4_lifecycle_security.sql` revokes direct API access, applies forced RLS, grants only the required columns/operations, establishes RPC, integrity, and scheduler policies, and attaches the existing timestamp trigger behavior to the new current-state tables.
5. `20261030102000_phase4_lifecycle_functions.sql` creates the RPCs, deferred integrity checks, trigger functions, function ownership, fixed search paths, and exact EXECUTE grants. It requires `extensions.digest(bytea,text)` to exist; it stops if that dependency is absent.
6. `supabase/scheduler/INSTALL_LIFECYCLE_FINALIZER.sql` is a separate psql installation script, outside `supabase/migrations`. It must not be run until disposable scheduler-identity validation passes.

Each migration uses a transaction. Role/schema mismatches, missing dependencies, or ownership failures abort rather than being silently normalized. The migration executor must be able to transfer functions to the approved roles without granting those roles table ownership or `BYPASSRLS`; this has not been validated on the hosted project.

## Legacy Compatibility and Blockers

The existing required table names are already occupied in `public` by the legacy schema. The lifecycle tables therefore use the same canonical table names inside the new, unexposed `idea_lifecycle` schema. Public RPC functions are the only intended API surface for the staged model. The new schema is not added to Supabase's exposed schemas, and API roles receive no direct schema/table access.

This is temporary coexistence, not a legacy data migration. The existing `sync_idea_session_status` trigger remains attached to the legacy public `ideas` table and continues to change only the legacy public `idea_sessions.status`. It cannot affect `idea_lifecycle` rows. The migration revokes unnecessary direct EXECUTE grants on the legacy trigger functions, but does not disable or detach either legacy trigger. The existing `public.set_updated_at` function and legacy timestamp triggers remain in place; the same timestamp function is attached to lifecycle sessions and ideas.

No mapping is assumed between legacy `in_progress` / `submitted` / `archived` values and the new three-state model. No legacy row is copied, updated, deleted, or reinterpreted. `registration_data` is accepted as an object and stored opaquely as the new session's initial draft object; it is not a backfill mapping.

Deployment blockers:

- Hosted migration history and current object definitions are unknown. The migrations intentionally stop if the lifecycle schema already exists, and the function migration stops if the expected legacy functions or pgcrypto location differ.
- Existing legacy data, status distributions, ownership integrity, and historical operation semantics have not been reviewed. A separately approved mapping/backfill and cutover plan is required before application traffic moves to the lifecycle API.
- Hosted function-owner transfer permissions, custom-role attributes/memberships, policy behavior, and pgcrypto namespace/grants have not been tested.
- The scheduler NOLOGIN runtime identity has not passed the required disposable-database validation. Scheduler installation remains disabled by default.
- No SQL, migration, database test, or scheduler job has been run for this work.

## Roles and Privilege Matrix

All three lifecycle owner roles are `NOLOGIN`, `NOSUPERUSER`, `NOCREATEDB`, `NOCREATEROLE`, `NOINHERIT`, and `NOBYPASSRLS`, with no role memberships. They do not own lifecycle tables.

| Role | Schema/table access | Function access |
| --- | --- | --- |
| `anon` | None on the private lifecycle schema/tables | No lifecycle RPC or finalizer EXECUTE |
| `authenticated` | No direct lifecycle table or schema access | EXECUTE only on `register_idea`, `save_registered_draft`, `complete_dossier`, `edit_dossier`, and `permanently_delete_idea` |
| `service_role` | No direct lifecycle schema/table access | No lifecycle function EXECUTE; BYPASSRLS does not grant SQL table access |
| `idea_rpc_owner` | RLS-scoped session SELECT/INSERT/UPDATE/DELETE; idea SELECT/INSERT/UPDATE; snapshot INSERT only; receipt SELECT/INSERT with restricted columns | Owns user RPCs and dossier validator; no finalizer EXECUTE |
| `idea_integrity_owner` | SELECT only on explicitly listed invariant-check columns in sessions, ideas, and revisions; no receipt-table access | Owns the deferred cross-table checker and its trigger function |
| `idea_scheduler_owner` | SELECT only on session ID/state and dossier ID/session/deadline/submission fields; UPDATE only on session state and dossier `submitted_at` | Owns and alone receives EXECUTE on the scheduler finalizer |

Function definitions use `SET search_path = pg_catalog, pg_temp`, schema-qualified application/Auth/extension objects, and explicit owners. Public RPC EXECUTE is revoked from `PUBLIC`, `anon`, `service_role`, and unrelated custom roles, then granted narrowly to `authenticated`. The SHA-256 digest overload is explicitly granted to `idea_rpc_owner`; the pgcrypto schema/extension ACL remains a hosted preflight dependency. Internal integrity functions are not API-callable. Trigger execution is restricted to trigger paths. The lifecycle schema has no API role `USAGE` grants.

## RLS and Integrity Visibility

All four lifecycle tables have RLS enabled and forced. RPC-owner policies scope user operations to `auth.uid()`; only the SECURITY DEFINER RPC owner accesses tables for user operations. There are no direct authenticated write policies or grants.

The integrity role has explicit `SELECT ... USING (true)` policies on the three invariant tables. This is cross-owner row visibility by design, not general access: column-level SELECT grants limit the role to state, ownership keys, dossier/revision values, and timestamp fields needed by the deferred checker. `idea_operation_keys` is not visible to the integrity role. The RPC owner has no snapshot UPDATE or DELETE privilege, and a `BEFORE UPDATE` guard rejects revision changes even for privileged update paths; no delete guard blocks legitimate parent cascades.

The scheduler sees only editing sessions and dossiers whose deadline is due and which have no submission timestamp. Its update policies allow only `editing_window -> submitted_for_evaluation` plus writing the dossier submission timestamp. It cannot update a draft, dossier content, revisions, or operation receipts.

Deferred constraint triggers check the aggregate at commit. A registered draft has no dossier or snapshots; each completed state has exactly one dossier; revisions are contiguous from initial revision 1; snapshot kinds, dossier values, latest-snapshot content, and timestamps agree; and submission time cannot precede the 168-hour deadline. A separate transition trigger permits only `registered_draft -> editing_window` under `idea_rpc_owner`, and `editing_window -> submitted_for_evaluation` under `idea_scheduler_owner` when the database deadline is due. Parent deletion is accepted after FK cascades remove the aggregate.

## RPC and Locking Semantics

- Registration and permanent deletion take the same transaction-scoped account advisory lock before quota counting/deletion. Registration checks an existing registration key and request hash before counting, so identical retries resolve to the original session. A different hash is rejected. All lifecycle sessions count toward the fixed three-per-account cap.
- Save, completion, and edit lock the session first, authorize by `auth.uid()`, then check the session-scoped receipt before stale revision, lifecycle state, or deadline checks. Hashes are computed server-side with SHA-256 over canonical JSONB request objects. Receipts store hashes/result revision metadata, not content.
- Completion atomically creates the dossier, revision-1 immutable snapshot, editing state, and receipt. It captures one database timestamp and sets `edit_deadline_at` to exactly `completed_at + interval '168 hours'`.
- Edit locks the session before the dossier, then captures `clock_timestamp()` only after both locks. It accepts only `v_now < edit_deadline_at`, checks the expected dossier revision, and atomically updates the current dossier, inserts the next snapshot, and records the receipt. Same-hash retries return prior metadata before deadline/revision checks; rejected edits create no receipt or snapshot.
- Permanent deletion takes the account lock, then the session lock, then the dossier lock, and deletes the session. Foreign keys cascade permanently through dossier, snapshots, and receipts.
- No user RPC supports early submission. Only the scheduler finalizer can transition a completed dossier to `submitted_for_evaluation`.

## Finalizer Lock Ordering and Atomicity

`finalize_expired_dossiers(batch_size)` validates a batch size of 1–100 and runs as `idea_scheduler_owner`. Each loop iteration selects exactly one due session, ordered by session ID, with `LIMIT 1 FOR UPDATE OF session SKIP LOCKED`. It does not preselect or lock a batch. It then locks that session's idea row, captures database time, and rechecks session state, deadline, and submission timestamp while both locks are held. It updates session state and dossier `submitted_at` in the same transaction, and only then selects the next session.

The function has no exception-swallowing handler. If any row fails during a call, the function statement fails and all rows finalized by that invocation roll back. It never takes the account advisory lock, preserving the account-lock -> session -> idea ordering used by registration/deletion without introducing a scheduler lock cycle.

## Scheduler Installation Prerequisites

Do not install pg_cron or schedule a job until disposable validation confirms all of the following against the exact runtime/version:

- The `NOLOGIN` `idea_scheduler_owner` is the actual execution identity accepted by the installed pg_cron mode.
- `cron.job.username`, actual `session_user`, invoker `current_user`, and SECURITY DEFINER `current_user` have been captured; scheduling acceptance alone is insufficient.
- The scheduled call actually succeeds with the role's exact schema/table/column/function privileges and RLS policies.
- A due row is finalized, a non-due row remains editable, repeated runs are safe, and failures are visible in job-run details.
- The one-minute cadence and exact pg_cron version/source behavior have been verified.

Only after that gate, run the separate psql script with `idea_scheduler_identity_validated=disposable-no-login-execution-confirmed`. The script installs/checks pg_cron, refuses an existing job of the same name, switches to the scheduler owner for scheduling, verifies the stored username/command/cadence, and runs transactionally. If NOLOGIN execution fails, stop for an explicit architecture decision; do not silently create a LOGIN role or add a fourth lifecycle role.

## Required Disposable PostgreSQL Acceptance Tests

Before deployment, create a genuinely isolated disposable Supabase/PostgreSQL environment and test at least:

- Exact migration ordering, schema/role ownership, NOLOGIN attributes, no role memberships, no table ownership by custom roles, and function-owner transfer without broad privileges.
- Effective grants and EXECUTE for `PUBLIC`, `anon`, `authenticated`, `service_role`, and all three custom roles; direct authenticated table mutation must be absent.
- RLS visibility and WITH CHECK behavior for two synthetic owners, including the integrity role's restricted columns and scheduler due-only visibility.
- Canonical JSON validation (missing, extra, non-string, and blank keys), 1–3 current step, and rejection of all other lifecycle states.
- Three-session quota, same-key/same-hash registration retries, conflicting registration hashes, and concurrent registration/deletion quota races.
- Session-scoped operation receipts, same-hash retry before stale/deadline checks, conflicting hashes, stale revisions, and no receipt/snapshot on rejected operations.
- Atomic completion, exact 168 elapsed hours, strict before/equal/after deadline edit checks, concurrent edits, and edit-vs-finalizer races.
- Deferred integrity failures for missing/mismatched snapshots, revision gaps, wrong snapshot kind/timestamp, current-dossier mismatch, and invalid state/dossier combinations; verify transaction rollback.
- Snapshot update/delete denial, successful parent cascade deletion in every state, and Auth-user cascade behavior using synthetic users.
- The repeated single-row finalizer pattern under competing workers, lock ordering, due/non-due filtering, batch limit, and fail-fast rollback of earlier rows in a batch when a later row errors.
- Existing legacy trigger behavior and `set_updated_at` on the legacy tables, while proving new lifecycle operations do not invoke legacy status synchronization.
- pgcrypto namespace and effective digest EXECUTE, plus real pg_cron execution identity and job success.

Record each outcome as passed, failed, or not run. No result is implied by these authored files.

## Phase 5 Shared Quota Implementation

### Status and migration order

Phase 5 is authored but has not been executed or validated by PostgreSQL. Preserve the four historical migrations exactly as written. After verifying the deployed ledger and object state, the forward-only sequence is:

1. `20261024090000_initial_idea_schema.sql` creates the legacy public model and its status/timestamp triggers.
2. `20261024090800_revoke_service_role_idea_access.sql` revokes the legacy table grants from `service_role`.
3. `20261030100000_phase4_lifecycle_schema.sql`, `20261030101000_phase4_lifecycle_security.sql`, and `20261030102000_phase4_lifecycle_functions.sql` create the Phase 4 model and base RPCs.
4. `20261030103000_phase5_shared_quota.sql` creates the shared quota table, locks and seeds both session stores, adds the Auth/session triggers and RLS policies, revokes direct legacy session DELETE, and temporarily disables the old registration/permanent-delete RPC grants.
5. `20261030104000_phase5_quota_rpc_api.sql` replaces quota-aware mutation RPCs, adds legacy-session delete and owner-scoped read RPCs, adds timestamp protection, and restores authenticated execution grants.
6. `20261030105000_phase5_scheduler_canary.sql` creates persisted scheduler-canary evidence and an owner-restricted probe. It does not create a cron job.
7. `supabase/scheduler/VALIDATE_LIFECYCLE_SCHEDULER.sql` is manually run only against a selected disposable target to schedule the harmless canary. `INSTALL_LIFECYCLE_FINALIZER.sql` remains separate and must not be run until its persisted evidence checks pass and finalizer activation is explicitly approved.

The Phase 5 migrations are transactional. A migration failure should roll back that migration’s DDL and data changes. The bootstrap takes `SHARE ROW EXCLUSIVE` locks on Auth users and both session tables; it therefore requires a controlled write-maintenance window and must not be applied blindly during active traffic.

### Preconditions and role ownership

Before applying Phase 5, verify the hosted migration ledger, actual table/function owners, Auth schema trigger privileges, custom role attributes/memberships, effective API-role ACLs, schema ACLs, default privileges, and pgcrypto location. The migrations fail if the expected base objects/roles are absent, but cannot prove the hosted records are safe to map. Do not edit historical migrations or assume the hosted database is empty.

The only privileged lifecycle roles are `idea_rpc_owner`, `idea_integrity_owner`, and `idea_scheduler_owner`; each is expected to remain NOLOGIN, NOSUPERUSER, NOCREATEDB, NOCREATEROLE, NOINHERIT, and NOBYPASSRLS, with no role memberships and no session/idea table ownership.

- `idea_rpc_owner` reads `registered_count` and `integrity_blocked`, updates only count/timestamp fields, and cannot change `integrity_blocked`. It performs owner-scoped mutations and Auth cleanup.
- `idea_integrity_owner` provisions quota rows and updates only integrity metadata; it cannot update `registered_count`. It can read the restricted cross-owner columns needed for reconciliation.
- `idea_scheduler_owner` owns the finalizer and scheduler canary functions; it has no quota-table access.
- API roles have no quota-table access. Legacy `authenticated` DELETE on `public.idea_sessions` is revoked; `public.delete_my_legacy_idea_session(uuid)` is quota-first and creates no operation receipt.

Temporary schema CREATE grants are used only for explicit function ownership transfers and are revoked in the same migration. The functions migration revokes PUBLIC/API EXECUTE on the pgcrypto digest overload and grants it to `idea_rpc_owner`. Default privileges are tightened for objects created by the Phase 5 migration identity; hosted ACLs belonging to other object-creating roles still require preflight inspection.

### Bootstrap procedure

1. Confirm this exact migration sequence is absent from the hosted ledger and its preconditions match the reviewed objects.
2. Drain writers. The migration locks `auth.users`, then `public.idea_sessions`, then `idea_lifecycle.idea_sessions` in `SHARE ROW EXCLUSIVE` mode. Let active transactions finish; abort/retry deployment if lock acquisition is unsafe.
3. Seed one quota row for every existing Auth user with the sum of that user’s rows in both session tables. The count has only a nonnegative constraint and preserves accounts already above three. No legacy status is mapped.
4. Verify Auth coverage, no quota orphans, and exact count parity while locks remain held. Install Auth provisioning/cleanup, both session reservation/release trigger pairs, identity-immutability and TRUNCATE guards, and RLS policies before commit.
5. The migration keeps temporary migration-role RLS visibility through final count verification, then removes the temporary policies and column grants before commit.

After commit, Auth AFTER INSERT is the only normal creation path for new quota rows. Registration fails if its row is missing; it never creates one. The controlled bootstrap is the only creation path for pre-existing users.

### Counter and cleanup semantics

Both session INSERT triggers atomically reserve in a BEFORE trigger and reject missing, blocked, or count-at-least-three rows. Both DELETE triggers lock the quota row `NOWAIT`, require a positive count, and decrement once. RPC bodies never increment/decrement. Any statement error rolls back both row and counter effects.

Auth BEFORE DELETE cleanup uses only `OLD.id`, locks quota `NOWAIT`, deletes legacy then lifecycle sessions, lets ordinary DELETE triggers decrement, verifies both tables empty and count zero, then deletes the quota row before FK cascades run. A transaction-local `app.idea_auth_cleanup_user_id` marker enables only role-targeted cleanup RLS policies and lets the legacy `sync_idea_session_status` trigger avoid reopening a session being deleted. No public RPC accepts that marker or a target owner ID. Auth trigger installation and managed-schema behavior remain hosted/disposable validation gates; a settable custom GUC is not a security boundary against arbitrary SQL-capable administrators.

Session `id` and `user_id` updates are rejected, TRUNCATE privileges are revoked and guarded, and API roles cannot modify quota rows. Superusers and trusted database administrators can still bypass ordinary triggers; administrative maintenance is outside the API threat boundary.

### Lock order and retries

Ordinary mutations use quota → session → idea → revision/receipt. Registration locks an existing quota row before its idempotency lookup; insert triggers are the sole reservation authority. Lifecycle deletion and legacy deletion RPCs lock quota before session. Legacy direct DELETE is revoked. Auth deletion begins with PostgreSQL’s Auth-row lock and uses quota `NOWAIT`; a conflict aborts and requires retrying the complete Auth deletion.

- `40001`: retry the complete transaction with the same registration idempotency key and payload.
- `55P03`: retry the complete Auth deletion after backoff; do not retry an individual trigger statement.
- `40P01`: privileged multi-user maintenance must sort account quota locks and session locks consistently; otherwise one transaction rolls back and the operator must retry the full maintenance transaction.
- Do not retry arbitrary constraint, authorization, or validation errors.

Reconciliation locks the quota row, counts both session stores, and marks a mismatch blocked without changing the count. A clean comparison never clears a prior block automatically. Repair and unblock require an audited integrity-owner operation after human review.

### RPC signatures

Authenticated-only public RPCs are:

- `register_idea(p_registration_key uuid, p_registration_data jsonb)`
- `save_registered_draft(p_session_id uuid, p_expected_revision bigint, p_idempotency_key uuid, p_draft_data jsonb, p_current_step smallint)`
- `complete_dossier(p_session_id uuid, p_expected_draft_revision bigint, p_idempotency_key uuid, p_dossier jsonb)`
- `edit_dossier(p_session_id uuid, p_expected_dossier_revision bigint, p_idempotency_key uuid, p_dossier jsonb)`
- `permanently_delete_idea(p_session_id uuid)`
- `delete_my_legacy_idea_session(p_session_id uuid)`
- `list_my_idea_sessions()`
- `get_my_idea_session(p_session_id uuid)`
- `list_my_idea_dossier_revisions(p_session_id uuid, p_after_revision bigint DEFAULT 0, p_limit integer DEFAULT 20)`

They derive ownership from `auth.uid()`, do not accept caller owner IDs, and return no result for both nonexistent and other-owner single-session IDs. Revision pages are capped at 100. `idea_lifecycle` remains unexposed; no direct table grants are given to API roles. Permanent deletion creates no operation receipt. Dossier completion creates the first idea/snapshot atomically, and edits use strict `clock_timestamp() < edit_deadline_at`.

### Scheduler preflight

The canary script checks the expected database name/OID, pg_cron extension/schema/configuration and NOLOGIN scheduler role before scheduling only `public.capture_lifecycle_scheduler_canary(nonce)`. The function persists database identity, `session_user`, invoker `current_user`, definer `current_user`, and execution time. Operators must correlate that row with a successful `cron.job_run_details` record. The finalizer installer requires this persisted evidence and successful cron run; its psql variables select the expected target and evidence nonce but are not proof by themselves.

Do not schedule the finalizer as part of this phase. Before a later activation, independently verify finalizer ownership, effective column/function privileges, RLS behavior, stored job identity, and a successful first scheduled finalizer execution. If NOLOGIN execution fails, stop for explicit approval; do not add a fourth role or make the scheduler role LOGIN.

### Test commands and deployment gates

Run only against a genuinely separate disposable PostgreSQL/Supabase instance, never the protected local instance or hosted project. The following are examples for the disposable lab workdir after its endpoint and identity have been verified:

```sh
npx --yes supabase@2.122.0 --workdir "$LAB_ROOT" migration up --local
npx --yes supabase@2.122.0 --workdir "$LAB_ROOT" test db --local
```

The new pgTAP file is `supabase/tests/database/phase5_shared_quota_test.sql`. It has not been executed. It does not replace independent-connection tests: separately test READ COMMITTED and REPEATABLE READ last-slot races, registration versus deletion, Auth deletion versus registration and legacy INSERT/DELETE, two Auth deletions, and sorted versus unsorted multi-user maintenance. Record `40001`, `55P03`, and `40P01` results and verify full-transaction retry behavior.

For independent-connection tests, use two disposable `psql` sessions with the same synthetic Auth user and request claims. In the READ COMMITTED case, pause connection A after its quota-row lock; connection B attempts the final reservation and must wait, then reject after A commits the last slot. In the REPEATABLE READ case, let A establish a snapshot, let B reserve and commit, then have A attempt its registration: A must fail with `40001`, and a fresh whole-transaction retry using A's same idempotency key must observe the full quota and create no fourth session. Do not retry only the failed INSERT within A's transaction.

For registration-versus-Auth-deletion, coordinate one connection after its quota lock and before/at the session INSERT FK check. The deletion connection obtains the Auth row and runs cleanup. If registration owns quota, Auth cleanup must fail immediately with `55P03` and roll back the Auth deletion; retrying the complete deletion after registration commits must remove both session types and quota. If cleanup owns quota and commits first, registration must fail missing-row/serialization and must not provision a replacement. Repeat with direct legacy INSERT and deletion, legacy delete RPC, lifecycle permanent delete, and two Auth deletes. For multi-user maintenance, test a sorted quota-then-session lock procedure; deliberately reverse it to demonstrate that PostgreSQL can abort one transaction with `40P01` and that no partial counter changes remain.

Also test role memberships/effective privileges/default ACLs, RLS cleanup-marker isolation, direct API TRUNCATE and ownership changes, quota drift blocking, timestamp writes, exact deadline equality, edit/finalizer races, snapshot cascade behavior, and the actual pg_cron identity. No SQL, migration, test, or cron script has been executed for Phase 5.

Rollback is safe only while a migration transaction is in progress. After successful deployment, do not drop the quota table, triggers, or evidence based on a conventional down migration: doing so can lose account counts or reopen bypass paths. Roll forward with an audited repair/retirement migration. Before hosted activation, resolve legacy status/data mapping separately, review users already above three, validate Auth schema trigger permissions and behavior, and obtain scheduler activation approval.
