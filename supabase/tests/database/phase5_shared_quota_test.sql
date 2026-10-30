CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

BEGIN;
SET LOCAL search_path = public, extensions;

SELECT extensions.no_plan();

INSERT INTO auth.users (
  id, aud, role, email, encrypted_password, confirmed_at, created_at, updated_at
)
VALUES
  (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', 'authenticated', 'authenticated',
    'phase5-quota-a@example.test', '', now(), now(), now()
  ),
  (
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1', 'authenticated', 'authenticated',
    'phase5-quota-b@example.test', '', now(), now(), now()
  );

SELECT extensions.ok(
  (SELECT registered_count = 0 AND NOT integrity_blocked
   FROM idea_lifecycle.idea_account_quota
   WHERE user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'),
  'Auth insert provisions one unblocked zero-count quota row'
);
SELECT extensions.ok(
  (SELECT count(*) = 3
   FROM pg_catalog.pg_roles
   WHERE rolname IN (
     'idea_rpc_owner', 'idea_integrity_owner', 'idea_scheduler_owner'
   )
     AND NOT rolcanlogin AND NOT rolsuper AND NOT rolbypassrls
     AND NOT rolcreaterole AND NOT rolcreatedb AND NOT rolinherit),
  'the three approved function roles remain restricted NOLOGIN roles'
);
SELECT extensions.ok(
  NOT has_table_privilege(
    'authenticated', 'idea_lifecycle.idea_account_quota', 'SELECT'
  ) AND NOT has_table_privilege(
    'service_role', 'idea_lifecycle.idea_account_quota', 'UPDATE'
  ) AND NOT has_table_privilege(
    'anon', 'idea_lifecycle.idea_account_quota', 'SELECT'
  ),
  'API roles have no direct quota table access'
);
SELECT extensions.ok(
  has_column_privilege(
    'idea_rpc_owner', 'idea_lifecycle.idea_account_quota',
    'integrity_blocked', 'SELECT'
  )
  AND NOT has_column_privilege(
    'idea_rpc_owner', 'idea_lifecycle.idea_account_quota',
    'integrity_blocked', 'UPDATE'
  ),
  'RPC owner can read but cannot change integrity_blocked'
);
SELECT extensions.ok(
  has_column_privilege(
    'idea_integrity_owner', 'idea_lifecycle.idea_account_quota',
    'integrity_blocked', 'UPDATE'
  )
  AND NOT has_column_privilege(
    'idea_integrity_owner', 'idea_lifecycle.idea_account_quota',
    'registered_count', 'UPDATE'
  ),
  'integrity owner can change metadata but not the quota count'
);
SELECT extensions.ok(
  NOT has_table_privilege('authenticated', 'public.idea_sessions', 'DELETE'),
  'authenticated cannot directly delete legacy sessions'
);
SELECT extensions.ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint
    WHERE constraint.conrelid =
      'idea_lifecycle.idea_account_quota'::pg_catalog.regclass
      AND constraint.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint.oid)
        LIKE '%registered_count%3%'
  ),
  'quota count has no maximum-three CHECK for bootstrap compatibility'
);
SELECT extensions.ok(
  NOT has_table_privilege(
    'idea_rpc_owner', 'idea_lifecycle.idea_dossier_revisions', 'DELETE'
  ) AND NOT has_table_privilege(
    'idea_rpc_owner', 'idea_lifecycle.idea_dossier_revisions', 'UPDATE'
  ),
  'RPC owner cannot mutate immutable revision snapshots'
);
SELECT extensions.ok(
  (SELECT relrowsecurity AND relforcerowsecurity
   FROM pg_catalog.pg_class
   WHERE oid = 'idea_lifecycle.idea_account_quota'::pg_catalog.regclass),
  'quota table has forced RLS'
);
SELECT extensions.ok(
  NOT has_function_privilege(
    'authenticated',
    'idea_lifecycle.cleanup_auth_user_before_delete()',
    'EXECUTE'
  ) AND NOT has_function_privilege(
    'anon',
    'public.finalize_expired_dossiers(integer)',
    'EXECUTE'
  ),
  'trigger cleanup and finalizer are not API-callable'
);

SET LOCAL ROLE authenticated;
SELECT pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1","role":"authenticated"}',
  true
);
SELECT pg_catalog.set_config(
  'request.jwt.claim.sub', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', true
);

SELECT extensions.lives_ok(
  $$INSERT INTO public.idea_sessions (id, user_id, current_step, draft_data)
    VALUES
      ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
       'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', 1, '{}'::jsonb),
      ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3',
       'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', 1, '{}'::jsonb)$$,
  'legacy inserts reserve two shared account slots'
);
SELECT pg_catalog.set_config(
  'phase5.lifecycle_session_id',
  public.register_idea(
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc1', '{"problem":"first"}'::jsonb
  ) ->> 'session_id',
  true
);
SELECT extensions.lives_ok(
  $$INSERT INTO public.idea_sessions (id, user_id)
    VALUES (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
    ) ON CONFLICT (id) DO NOTHING$$,
  'conflict-skipped legacy INSERT does not invoke successful-insert reservation'
);
SELECT extensions.is(
  (SELECT registered_count FROM idea_lifecycle.idea_account_quota
   WHERE user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'),
  3::bigint,
  'lifecycle registration and legacy inserts share the same count'
);
SELECT extensions.is(
  public.register_idea(
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc1', '{"problem":"first"}'::jsonb
  ) ->> 'replayed',
  'true',
  'same registration key and payload return the original session'
);
SELECT extensions.throws_ok(
  $$SELECT public.register_idea(
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc2', '{"problem":"fourth"}'::jsonb
    )$$,
  '23514', NULL,
  'a fourth session is rejected'
);
SELECT extensions.throws_ok(
  $$SELECT public.register_idea(
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc1', '{"problem":"changed"}'::jsonb
    )$$,
  '23505', NULL,
  'conflicting registration-key reuse is rejected'
);
SELECT extensions.ok(
  NOT has_function_privilege(
    'authenticated', 'idea_lifecycle.reconcile_account_quota(uuid)', 'EXECUTE'
  ),
  'authenticated cannot reconcile or unblock another account'
);
SELECT pg_catalog.set_config(
  'app.idea_auth_cleanup_user_id',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
  true
);
SELECT extensions.is(
  public.get_my_idea_session('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2'),
  NULL::jsonb,
  'forged cleanup context does not expose another account through the read RPC'
);
SELECT extensions.is(
  public.delete_my_legacy_idea_session(
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
  ) ->> 'deleted',
  'false',
  'legacy delete RPC ignores forged cleanup context and uses auth.uid()'
);
SELECT pg_catalog.set_config('app.idea_auth_cleanup_user_id', '', true);

SELECT extensions.lives_ok(
  $$INSERT INTO public.ideas (
      session_id, user_id, theme, problem, affected_people, possible_causes,
      proposed_solution, beneficiary_group, expected_outcome,
      implementation_barriers
    ) VALUES (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
      'theme', 'problem', 'people', 'causes', 'solution', 'beneficiaries',
      'outcome', 'barriers'
    )$$,
  'legacy idea submission continues without a second quota reservation'
);
SELECT extensions.is(
  public.delete_my_legacy_idea_session(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2'
  ) ->> 'deleted',
  'true',
  'quota-first legacy delete RPC removes an owned legacy session'
);
SELECT extensions.is(
  (SELECT registered_count FROM idea_lifecycle.idea_account_quota
   WHERE user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'),
  2::bigint,
  'legacy session deletion releases exactly one quota unit'
);
SELECT extensions.throws_ok(
  $$DELETE FROM public.idea_sessions
    WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3'$$,
  '42501', NULL,
  'direct authenticated legacy DELETE is denied'
);
SELECT extensions.throws_ok(
  $$TRUNCATE public.idea_sessions$$,
  '42501', NULL,
  'session TRUNCATE guard rejects truncation'
);
SELECT extensions.throws_ok(
  $$UPDATE public.idea_sessions
    SET user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
    WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3'$$,
  '42501', NULL,
  'authenticated cannot change session ownership'
);

SELECT extensions.set_eq(
  $$SELECT session_id
    FROM jsonb_to_recordset(public.list_my_idea_sessions())
      AS row_data(session_id uuid)$$,
  $$SELECT id FROM idea_lifecycle.idea_sessions
    WHERE user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'$$,
  'session list returns the authenticated user lifecycle sessions'
);
SELECT extensions.is(
  public.get_my_idea_session(
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
  ),
  NULL::jsonb,
  'other-owner session read is indistinguishable from missing session'
);

SELECT pg_catalog.set_config(
  'phase5.lifecycle_session_id',
  public.register_idea(
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc3', '{"problem":"to complete"}'::jsonb
  ) ->> 'session_id',
  true
);
SELECT public.complete_dossier(
  pg_catalog.current_setting('phase5.lifecycle_session_id')::uuid,
  0,
  'dddddddd-dddd-4ddd-8ddd-ddddddddddd1',
  '{
    "theme":"health",
    "problem":"problem",
    "affected_people":"people",
    "possible_causes":"causes",
    "proposed_solution":"solution",
    "beneficiary_group":"beneficiaries",
    "expected_outcome":"outcome",
    "implementation_barriers":"barriers"
  }'::jsonb
);
RESET ROLE;
SELECT extensions.is(
  (SELECT count(*) FROM idea_lifecycle.idea_dossier_revisions AS revision
   JOIN idea_lifecycle.ideas AS idea ON idea.id = revision.idea_id
   WHERE idea.session_id =
     pg_catalog.current_setting('phase5.lifecycle_session_id')::uuid),
  1::bigint,
  'completion creates exactly one initial dossier revision'
);
SELECT extensions.throws_ok(
  $$UPDATE idea_lifecycle.ideas
    SET completed_at = completed_at + INTERVAL '1 second'
    WHERE session_id = current_setting('phase5.lifecycle_session_id')::uuid$$,
  '23514', NULL,
  'completion timestamp cannot be changed'
);
SELECT extensions.throws_ok(
  $$UPDATE idea_lifecycle.ideas
    SET submitted_at = clock_timestamp()
    WHERE session_id = current_setting('phase5.lifecycle_session_id')::uuid$$,
  '23514', NULL,
  'manual and early submission timestamp writes are rejected'
);
SELECT extensions.throws_ok(
  $$UPDATE idea_lifecycle.idea_dossier_revisions
    SET dossier = '{}'::jsonb
    WHERE idea_id = (
      SELECT id FROM idea_lifecycle.ideas
      WHERE session_id = current_setting('phase5.lifecycle_session_id')::uuid
    )$$,
  '55000', NULL,
  'completed dossier revision snapshots reject UPDATE'
);
SET LOCAL ROLE authenticated;
SELECT extensions.is(
  (public.list_my_idea_dossier_revisions(
    pg_catalog.current_setting('phase5.lifecycle_session_id')::uuid,
    0, 10
  ) ->> 'has_more')::boolean,
  false,
  'revision history is owner-scoped and bounded'
);

RESET ROLE;

-- Corrupt only inside this rollback-only test to verify fail-closed reconciliation.
UPDATE idea_lifecycle.idea_account_quota
SET registered_count = registered_count + 1
WHERE user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1';
SET LOCAL ROLE idea_integrity_owner;
SELECT extensions.is(
  idea_lifecycle.reconcile_account_quota(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
  ) ->> 'status',
  'blocked_mismatch',
  'reconciliation blocks a mismatch without silently repairing the count'
);
RESET ROLE;
SELECT extensions.ok(
  (SELECT integrity_blocked
   FROM idea_lifecycle.idea_account_quota
   WHERE user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'),
  'integrity mismatch remains blocked after reconciliation'
);

SET LOCAL ROLE authenticated;
SELECT pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1","role":"authenticated"}',
  true
);
SELECT pg_catalog.set_config(
  'request.jwt.claim.sub', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', true
);
SELECT extensions.throws_ok(
  $$SELECT public.register_idea(
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc4', '{"problem":"blocked"}'::jsonb
    )$$,
  '55000', NULL,
  'blocked account cannot reserve another slot'
);
RESET ROLE;

DELETE FROM idea_lifecycle.idea_account_quota
WHERE user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1';
SET LOCAL ROLE authenticated;
SELECT pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1","role":"authenticated"}',
  true
);
SELECT pg_catalog.set_config(
  'request.jwt.claim.sub', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', true
);
SELECT extensions.throws_ok(
  $$SELECT public.register_idea(
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc5', '{"problem":"missing row"}'::jsonb
    )$$,
  '23503', NULL,
  'registration fails rather than recreating a missing quota row'
);
RESET ROLE;

-- User B has both session types; Auth cleanup must delete them before FK cascades.
SET LOCAL ROLE authenticated;
SELECT pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1","role":"authenticated"}',
  true
);
SELECT pg_catalog.set_config(
  'request.jwt.claim.sub', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1', true
);
SELECT extensions.lives_ok(
  $$INSERT INTO public.idea_sessions (id, user_id)
    VALUES (
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
    )$$,
  'user B legacy session reserves quota'
);
SELECT public.register_idea(
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1', '{"problem":"auth cleanup"}'::jsonb
);
RESET ROLE;

DELETE FROM auth.users
WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1';
SELECT extensions.is(
  (SELECT count(*) FROM idea_lifecycle.idea_account_quota
   WHERE user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'),
  0::bigint,
  'Auth cleanup removes the quota row before FK cascade'
);
SELECT extensions.is(
  (SELECT count(*) FROM public.idea_sessions
   WHERE user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1')
  +
  (SELECT count(*) FROM idea_lifecycle.idea_sessions
   WHERE user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'),
  0::bigint,
  'Auth cleanup removes both legacy and lifecycle sessions'
);

SELECT * FROM extensions.finish();
ROLLBACK;
