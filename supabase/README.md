# Supabase data model

## Tables and lifecycle

- `idea_sessions` stores one user's in-progress wizard, its current step
  (`1`–`3`), and an object-valued JSONB draft. Its status is `in_progress` or
  `submitted`.
- `ideas` stores at most one explicitly submitted idea per session. Its status
  is `submitted` or `archived`; the initial authenticated API grants do not
  allow users to change that status. All eight answer columns are required and
  must contain non-whitespace text.
- Both tables use UUID primary keys and UTC-capable `timestamptz` creation and
  update timestamps. `updated_at` is advanced by a PostgreSQL trigger.
- `ideas.session_id` is unique, so a session can have at most one final idea.
  Its composite foreign key to `(idea_sessions.id, idea_sessions.user_id)`
  prevents assigning an idea to a session owned by another user. Deleting a
  session, or deleting its auth user, cascades to the associated idea(s).

## Form field mapping

| TypeScript field | PostgreSQL column |
| --- | --- |
| `theme` | `theme` |
| `problem` | `problem` |
| `affectedPeople` | `affected_people` |
| `possibleCauses` | `possible_causes` |
| `proposedSolution` | `proposed_solution` |
| `beneficiaryGroup` | `beneficiary_group` |
| `expectedOutcome` | `expected_outcome` |
| `implementationBarriers` | `implementation_barriers` |

Save partial answers and `current_step` in `idea_sessions`; only create an
`ideas` row after the user explicitly submits the completed draft. Merely
showing the client-side summary does not submit or persist an idea.

An `AFTER INSERT` trigger changes the owning session from `in_progress` to
`submitted` in the same transaction as inserting the idea. An `AFTER DELETE`
trigger reopens the session as `in_progress`; deleting a session itself still
cascades to its idea. These transitions use a narrowly scoped
`SECURITY DEFINER` trigger function with a fixed `search_path`, and direct
authenticated updates to session status are denied by column privileges and
RLS. Apply migrations as the trusted Supabase migration role that owns the
tables and trigger function.

## Row-level security and grants

RLS is enabled on both tables. Only the `authenticated` database role receives
application table privileges; `anon`, `PUBLIC`, and `service_role` receive
none after both migrations are applied. The follow-up migration explicitly
removes Supabase's default `service_role` grants for these tables. Policies
restrict reads, writes, and deletes to rows whose `user_id` equals `auth.uid()`.
Idea inserts also require an owned `in_progress` session; the composite
foreign key enforces the same ownership relationship independently of the
policy.

Authenticated users can create and edit session draft fields, but cannot set
session status or timestamps. They can insert a final idea only in `submitted`
status and edit its eight answer fields. The idea's owner and session IDs,
status, and timestamps are not user-editable. Deleting an owned idea reopens
its session; deleting the session removes the idea through the documented
cascade.

The trigger function needs `SECURITY DEFINER` so it can update the protected
session status atomically without granting that column to clients. It is
restricted to trigger use, uses a fixed `search_path`, and must remain owned by
the trusted migration/table-owner role. Do not expose a `service_role` secret
to application code or the browser.

## Application connection and authentication

The Next.js app uses `@supabase/ssr` with the public
`NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` values,
and `NEXT_PUBLIC_SITE_URL` for validated email redirect construction. Copy the
repository's [`.env.example`](../.env.example) to `.env.local` and fill the
Supabase values from the project's Connect dialog; never put a `service_role`
key in application environment variables. The publishable key is intentionally
public; RLS and server-verified identity, not the key or UI visibility, protect
private rows.

The server client reads and writes the Supabase session cookies, and
[`src/proxy.ts`](../src/proxy.ts) refreshes sessions with `auth.getClaims()` as
recommended for Next.js 16. Server-side current-user checks use
`auth.getUser()`; do not use `auth.getSession()` to authorize requests. Keep
session-dependent reads in server-only code, verify identity on every private
operation, and rely on RLS for database authorization. Any Server Component
that calls `getCurrentUser()` must do so behind a `<Suspense>` boundary; do not
read the session at the top level of a layout. Do not place session data or
user-specific reads in shared caches or the static shell.

The application implements email/password registration with email confirmation,
password sign-in, PKCE email callbacks, password reset, confirmation resend, and
sign-out. See the repository [README](../README.md) for the required Supabase
Auth provider, URL allow-list, and email-template configuration. The app uses
only the public publishable key; it does not use `service_role`.

This integration does not connect the idea wizard or persist drafts.

## Local migration and RLS tests

The local development configuration is generated by the official Supabase CLI
in `config.toml`. It is not linked to a hosted project. The tested CLI version
is `2.122.0`; invoking it through `npx` avoids adding it to the application's
dependencies:

```sh
npx --yes supabase@2.122.0 start
npx --yes supabase@2.122.0 migration up --local
npx --yes supabase@2.122.0 test db --local
```

The pgTAP suite in `tests/database/idea_rls_test.sql` uses synthetic users and
rows inside a transaction and rolls them back. Do not run `db reset`,
`stop --no-backup`, or any linked/remote command to execute these tests.
Starting the local stack may download Docker images and creates local Docker
resources; stop it with `npx --yes supabase@2.122.0 stop` when no longer needed.

In the current dev-container, Docker is available but the full CLI stack could
not start because the container could not resolve the Docker host alias needed
by Supabase services. The migration and pgTAP suite were therefore executed
directly against an isolated Supabase Postgres 17.11 image with its Auth schema
and API roles. The CLI-managed local stack and Data API still need verification
on a host where the Supabase service network resolves correctly.

Do not link this directory to a hosted project or run a linked migration/test
unless an isolated staging project has been selected and the owner has
explicitly approved remote access and schema changes.
