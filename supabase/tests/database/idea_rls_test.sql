CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

BEGIN;
SET LOCAL search_path = public, extensions;

INSERT INTO auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  confirmed_at,
  created_at,
  updated_at
)
VALUES
  (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
    'authenticated',
    'authenticated',
    'idea-rls-user-a@example.test',
    '',
    now(),
    now(),
    now()
  ),
  (
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
    'authenticated',
    'authenticated',
    'idea-rls-user-b@example.test',
    '',
    now(),
    now(),
    now()
  );

INSERT INTO public.idea_sessions (id, user_id)
VALUES
  (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
  ),
  (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
  ),
  (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
  ),
  (
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
  );

SELECT extensions.plan(53);

SELECT extensions.has_table(
  'public',
  'idea_sessions',
  'idea_sessions exists'
);
SELECT extensions.has_table(
  'public',
  'ideas',
  'ideas exists'
);
SELECT extensions.ok(
  (
    SELECT relrowsecurity
    FROM pg_class
    WHERE oid = 'public.idea_sessions'::regclass
  ),
  'RLS is enabled on idea_sessions'
);
SELECT extensions.ok(
  (
    SELECT relrowsecurity
    FROM pg_class
    WHERE oid = 'public.ideas'::regclass
  ),
  'RLS is enabled on ideas'
);
SELECT extensions.ok(
  NOT has_table_privilege('anon', 'public.idea_sessions', 'SELECT'),
  'anon cannot read idea_sessions'
);
SELECT extensions.ok(
  NOT has_table_privilege('anon', 'public.ideas', 'INSERT'),
  'anon cannot insert ideas'
);
SELECT extensions.ok(
  NOT has_table_privilege('service_role', 'public.idea_sessions', 'SELECT'),
  'service_role has no direct read grant on idea_sessions'
);
SELECT extensions.ok(
  NOT has_table_privilege('service_role', 'public.ideas', 'INSERT'),
  'service_role has no direct insert grant on ideas'
);
SELECT extensions.ok(
  NOT has_column_privilege(
    'authenticated',
    'public.idea_sessions',
    'user_id',
    'UPDATE'
  ),
  'authenticated cannot change session ownership'
);
SELECT extensions.ok(
  NOT has_column_privilege(
    'authenticated',
    'public.idea_sessions',
    'status',
    'UPDATE'
  ),
  'authenticated cannot directly change session status'
);
SELECT extensions.ok(
  NOT has_column_privilege(
    'authenticated',
    'public.ideas',
    'user_id',
    'UPDATE'
  ),
  'authenticated cannot change idea ownership'
);
SELECT extensions.ok(
  NOT has_column_privilege(
    'authenticated',
    'public.ideas',
    'status',
    'UPDATE'
  ),
  'authenticated cannot change idea status'
);
SELECT extensions.ok(
  NOT has_column_privilege(
    'authenticated',
    'public.idea_sessions',
    'created_at',
    'UPDATE'
  )
  AND NOT has_column_privilege(
    'authenticated',
    'public.idea_sessions',
    'updated_at',
    'UPDATE'
  ),
  'authenticated cannot change session timestamps'
);
SELECT extensions.ok(
  NOT has_column_privilege(
    'authenticated',
    'public.ideas',
    'created_at',
    'UPDATE'
  )
  AND NOT has_column_privilege(
    'authenticated',
    'public.ideas',
    'updated_at',
    'UPDATE'
  ),
  'authenticated cannot change idea timestamps'
);
SELECT extensions.policies_are(
  'public',
  'idea_sessions',
  ARRAY[
    'idea_sessions_delete_own',
    'idea_sessions_insert_own',
    'idea_sessions_select_own',
    'idea_sessions_update_own_draft'
  ],
  'idea_sessions has only its owner-scoped policies'
);
SELECT extensions.policies_are(
  'public',
  'ideas',
  ARRAY[
    'ideas_delete_own',
    'ideas_insert_own_session_draft',
    'ideas_select_own',
    'ideas_update_own'
  ],
  'ideas has only its owner-scoped policies'
);

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1","role":"authenticated"}',
  true
);
SELECT set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
  true
);

SELECT extensions.lives_ok(
  $$INSERT INTO public.idea_sessions (user_id, current_step, draft_data)
    VALUES (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
      1,
      '{"problem":"draft"}'::jsonb
    )$$,
  'user A can create an owned draft'
);
SELECT extensions.throws_ok(
  $$INSERT INTO public.idea_sessions (user_id, current_step, draft_data)
    VALUES (
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
      1,
      '{}'::jsonb
    )$$,
  '42501',
  NULL,
  'user A cannot create a session owned by user B'
);
SELECT extensions.is(
  (SELECT count(*) FROM public.idea_sessions)::bigint,
  4::bigint,
  'user A can read all and only their sessions'
);
SELECT extensions.is(
  (
    SELECT count(*)
    FROM public.idea_sessions
    WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
  )::bigint,
  0::bigint,
  'user A cannot read user B session'
);
SELECT extensions.lives_ok(
  $$UPDATE public.idea_sessions
    SET draft_data = '{"problem":"tampered"}'::jsonb
    WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'$$,
  'user A cannot update user B session'
);
SELECT extensions.lives_ok(
  $$DELETE FROM public.idea_sessions
    WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'$$,
  'user A cannot delete user B session'
);
RESET ROLE;
SELECT extensions.is(
  (
    SELECT count(*)
    FROM public.idea_sessions
    WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
  )::bigint,
  1::bigint,
  'user B session remains after user A update and delete attempts'
);
SELECT extensions.is(
  (
    SELECT draft_data
    FROM public.idea_sessions
    WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
  ),
  '{}'::jsonb,
  'user B draft is unchanged after user A update attempt'
);
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1","role":"authenticated"}',
  true
);
SELECT set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
  true
);
SELECT extensions.lives_ok(
  $$UPDATE public.idea_sessions
    SET current_step = 2, draft_data = '{"problem":"updated draft"}'::jsonb
    WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'$$,
  'user A can update their own draft'
);
SELECT extensions.throws_ok(
  $$UPDATE public.idea_sessions
    SET user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
    WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'$$,
  '42501',
  NULL,
  'user A cannot change session ownership'
);
SELECT extensions.throws_ok(
  $$UPDATE public.idea_sessions
    SET status = 'submitted'
    WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'$$,
  '42501',
  NULL,
  'user A cannot change session status'
);
SELECT extensions.throws_ok(
  $$INSERT INTO public.ideas (
      session_id, user_id, theme, problem, affected_people, possible_causes,
      proposed_solution, beneficiary_group, expected_outcome,
      implementation_barriers
    )
    VALUES (
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
      'theme', 'problem', 'people', 'causes', 'solution', 'beneficiaries',
      'outcome', 'barriers'
    )$$,
  '42501',
  NULL,
  'user A cannot submit an idea to user B session'
);
SELECT extensions.throws_ok(
  $$INSERT INTO public.ideas (
      session_id, user_id, theme, problem, affected_people, possible_causes,
      proposed_solution, beneficiary_group, expected_outcome,
      implementation_barriers
    )
    VALUES (
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
      'theme', 'problem', 'people', 'causes', 'solution', 'beneficiaries',
      'outcome', 'barriers'
    )$$,
  '42501',
  NULL,
  'user A cannot submit an idea to a nonexistent session'
);
SELECT extensions.lives_ok(
  $$INSERT INTO public.ideas (
      session_id, user_id, theme, problem, affected_people, possible_causes,
      proposed_solution, beneficiary_group, expected_outcome,
      implementation_barriers
    )
    VALUES (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
      'theme', 'problem', 'people', 'causes', 'solution', 'beneficiaries',
      'outcome', 'barriers'
    )$$,
  'user A can explicitly submit an idea for their own in-progress session'
);
SELECT extensions.is(
  (
    SELECT status
    FROM public.idea_sessions
    WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
  ),
  'submitted',
  'successful idea submission marks the session submitted'
);
SELECT extensions.throws_ok(
  $$INSERT INTO public.ideas (
      session_id, user_id, theme, problem, affected_people, possible_causes,
      proposed_solution, beneficiary_group, expected_outcome,
      implementation_barriers
    )
    VALUES (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
      'theme', 'problem', 'people', 'causes', 'solution', 'beneficiaries',
      'outcome', 'barriers'
    )$$,
  '42501',
  NULL,
  'a submitted session cannot be submitted again by an ordinary user'
);
SELECT extensions.lives_ok(
  $$UPDATE public.ideas
    SET theme = 'edited theme'
    WHERE session_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'$$,
  'user A can edit their own submitted idea'
);
SELECT extensions.throws_ok(
  $$UPDATE public.ideas
    SET user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
    WHERE session_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'$$,
  '42501',
  NULL,
  'user A cannot change idea ownership'
);
SELECT extensions.throws_ok(
  $$UPDATE public.ideas
    SET status = 'archived'
    WHERE session_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'$$,
  '42501',
  NULL,
  'user A cannot change idea status'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1","role":"authenticated"}',
  true
);
SELECT set_config(
  'request.jwt.claim.sub',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
  true
);

SELECT extensions.is(
  (
    SELECT count(*)
    FROM public.ideas
    WHERE session_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
  )::bigint,
  0::bigint,
  'user B cannot read user A idea'
);
SELECT extensions.lives_ok(
  $$UPDATE public.ideas
    SET theme = 'tampered'
    WHERE session_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'$$,
  'user B cannot update user A idea'
);
SELECT extensions.lives_ok(
  $$DELETE FROM public.ideas
    WHERE session_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'$$,
  'user B cannot delete user A idea'
);
RESET ROLE;
SELECT extensions.is(
  (
    SELECT count(*)
    FROM public.ideas
    WHERE session_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
  )::bigint,
  1::bigint,
  'user A idea remains after user B update and delete attempts'
);
SELECT extensions.is(
  (
    SELECT theme
    FROM public.ideas
    WHERE session_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
  ),
  'edited theme',
  'user A idea is unchanged after user B update attempt'
);
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1","role":"authenticated"}',
  true
);
SELECT set_config(
  'request.jwt.claim.sub',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
  true
);
SELECT extensions.lives_ok(
  $$INSERT INTO public.ideas (
      session_id, user_id, theme, problem, affected_people, possible_causes,
      proposed_solution, beneficiary_group, expected_outcome,
      implementation_barriers
    )
    VALUES (
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
      'theme', 'problem', 'people', 'causes', 'solution', 'beneficiaries',
      'outcome', 'barriers'
    )$$,
  'user B can submit an idea for their own session'
);
SELECT extensions.is(
  (SELECT count(*) FROM public.ideas)::bigint,
  1::bigint,
  'user B can read only their own idea'
);
SELECT extensions.lives_ok(
  $$DELETE FROM public.ideas
    WHERE session_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'$$,
  'user B can delete their own submitted idea'
);
SELECT extensions.is(
  (
    SELECT status
    FROM public.idea_sessions
    WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
  ),
  'in_progress',
  'deleting an idea reopens its session'
);
SELECT extensions.lives_ok(
  $$INSERT INTO public.ideas (
      session_id, user_id, theme, problem, affected_people, possible_causes,
      proposed_solution, beneficiary_group, expected_outcome,
      implementation_barriers
    )
    VALUES (
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
      'theme', 'problem', 'people', 'causes', 'solution', 'beneficiaries',
      'outcome', 'barriers'
    )$$,
  'user B can resubmit after deleting their idea'
);
SELECT extensions.lives_ok(
  $$DELETE FROM public.idea_sessions
    WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'$$,
  'user B can delete their own session'
);
SELECT extensions.is(
  (
    SELECT count(*)
    FROM public.ideas
    WHERE session_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
  )::bigint,
  0::bigint,
  'deleting a session cascades to its idea'
);

RESET ROLE;
SET LOCAL ROLE anon;
SELECT extensions.throws_ok(
  $$SELECT * FROM public.idea_sessions$$,
  '42501',
  NULL,
  'anon cannot read sessions'
);
SELECT extensions.throws_ok(
  $$INSERT INTO public.ideas (
      session_id, user_id, theme, problem, affected_people, possible_causes,
      proposed_solution, beneficiary_group, expected_outcome,
      implementation_barriers
    )
    VALUES (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
      'theme', 'problem', 'people', 'causes', 'solution', 'beneficiaries',
      'outcome', 'barriers'
    )$$,
  '42501',
  NULL,
  'anon cannot insert ideas'
);

RESET ROLE;
UPDATE public.idea_sessions
SET status = 'submitted'
WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3';

SELECT extensions.throws_ok(
  $$INSERT INTO public.ideas (
      session_id, user_id, theme, problem, affected_people, possible_causes,
      proposed_solution, beneficiary_group, expected_outcome,
      implementation_barriers
    )
    VALUES (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
      'theme', 'problem', 'people', 'causes', 'solution', 'beneficiaries',
      'outcome', 'barriers'
    )$$,
  '23505',
  NULL,
  'the unique session constraint rejects a second idea'
);
SELECT extensions.throws_ok(
  $$INSERT INTO public.ideas (
      session_id, user_id, theme, problem, affected_people, possible_causes,
      proposed_solution, beneficiary_group, expected_outcome,
      implementation_barriers
    )
    VALUES (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
      'theme', 'problem', 'people', 'causes', 'solution', 'beneficiaries',
      'outcome', 'barriers'
    )$$,
  '23514',
  NULL,
  'a trigger failure rejects the idea insert'
);
SELECT extensions.is(
  (
    SELECT count(*)
    FROM public.ideas
    WHERE session_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3'
  )::bigint,
  0::bigint,
  'the failed trigger insert is rolled back'
);
SELECT extensions.is(
  (
    SELECT status
    FROM public.idea_sessions
    WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3'
  ),
  'submitted',
  'trigger failure leaves the preexisting session state unchanged'
);

SELECT * FROM extensions.finish();
ROLLBACK;
