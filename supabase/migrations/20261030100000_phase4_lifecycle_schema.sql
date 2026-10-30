BEGIN;

DO $roles$
DECLARE
  v_role_name text;
  v_role record;
BEGIN
  FOREACH v_role_name IN ARRAY ARRAY[
    'idea_rpc_owner',
    'idea_integrity_owner',
    'idea_scheduler_owner'
  ] LOOP
    SELECT * INTO v_role FROM pg_catalog.pg_roles
    WHERE rolname = v_role_name;

    IF NOT FOUND THEN
      EXECUTE pg_catalog.format(
        'CREATE ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS',
        v_role_name
      );
    ELSIF v_role.rolcanlogin
       OR v_role.rolsuper
       OR v_role.rolcreatedb
       OR v_role.rolcreaterole
       OR v_role.rolinherit
       OR v_role.rolbypassrls THEN
      RAISE EXCEPTION 'Existing role % does not match the approved restricted role attributes',
        v_role_name;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_auth_members AS membership
    WHERE membership.roleid IN (
      SELECT oid FROM pg_catalog.pg_roles
      WHERE rolname IN (
        'idea_rpc_owner', 'idea_integrity_owner', 'idea_scheduler_owner'
      )
    )
    OR membership.member IN (
      SELECT oid FROM pg_catalog.pg_roles
      WHERE rolname IN (
        'idea_rpc_owner', 'idea_integrity_owner', 'idea_scheduler_owner'
      )
    )
  ) THEN
    RAISE EXCEPTION 'Approved lifecycle owner roles must have no role memberships';
  END IF;
END;
$roles$;

DO $schema$
BEGIN
  IF pg_catalog.to_regnamespace('idea_lifecycle') IS NOT NULL THEN
    RAISE EXCEPTION 'Schema idea_lifecycle already exists; inspect deployment history before continuing';
  END IF;
END;
$schema$;

CREATE SCHEMA idea_lifecycle;

COMMENT ON SCHEMA idea_lifecycle IS
  'Private staged lifecycle schema. Not exposed through the Supabase Data API; legacy public idea tables remain separate until an approved data migration.';

CREATE TABLE idea_lifecycle.idea_sessions (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  state text NOT NULL DEFAULT 'registered_draft',
  current_step smallint NOT NULL DEFAULT 1,
  draft_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  draft_revision bigint NOT NULL DEFAULT 0,
  registration_key uuid NOT NULL,
  registration_hash bytea NOT NULL,
  registered_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  CONSTRAINT idea_lifecycle_sessions_state_check
    CHECK (state IN (
      'registered_draft',
      'editing_window',
      'submitted_for_evaluation'
    )),
  CONSTRAINT idea_lifecycle_sessions_step_check
    CHECK (current_step BETWEEN 1 AND 3),
  CONSTRAINT idea_lifecycle_sessions_draft_object_check
    CHECK (pg_catalog.jsonb_typeof(draft_data) = 'object'),
  CONSTRAINT idea_lifecycle_sessions_revision_check
    CHECK (draft_revision >= 0),
  CONSTRAINT idea_lifecycle_sessions_registration_hash_check
    CHECK (pg_catalog.octet_length(registration_hash) = 32),
  CONSTRAINT idea_lifecycle_sessions_id_user_key UNIQUE (id, user_id),
  CONSTRAINT idea_lifecycle_sessions_user_registration_key
    UNIQUE (user_id, registration_key)
);

CREATE TABLE idea_lifecycle.ideas (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  session_id uuid NOT NULL UNIQUE,
  user_id uuid NOT NULL,
  dossier jsonb NOT NULL,
  dossier_schema_version smallint NOT NULL DEFAULT 1,
  dossier_revision bigint NOT NULL,
  completed_at timestamptz NOT NULL,
  edit_deadline_at timestamptz NOT NULL,
  submitted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  CONSTRAINT idea_lifecycle_ideas_session_owner_fkey
    FOREIGN KEY (session_id, user_id)
    REFERENCES idea_lifecycle.idea_sessions (id, user_id)
    ON DELETE CASCADE,
  CONSTRAINT idea_lifecycle_ideas_schema_version_check
    CHECK (dossier_schema_version = 1),
  CONSTRAINT idea_lifecycle_ideas_revision_check
    CHECK (dossier_revision >= 1),
  CONSTRAINT idea_lifecycle_ideas_deadline_check
    CHECK (edit_deadline_at = completed_at + INTERVAL '168 hours'),
  CONSTRAINT idea_lifecycle_ideas_dossier_check
    CHECK (
      pg_catalog.jsonb_typeof(dossier) = 'object'
      AND (dossier - ARRAY[
        'theme', 'problem', 'affected_people', 'possible_causes',
        'proposed_solution', 'beneficiary_group', 'expected_outcome',
        'implementation_barriers'
      ]) = '{}'::jsonb
      AND dossier ?& ARRAY[
        'theme', 'problem', 'affected_people', 'possible_causes',
        'proposed_solution', 'beneficiary_group', 'expected_outcome',
        'implementation_barriers'
      ]
      AND pg_catalog.jsonb_typeof(dossier -> 'theme') = 'string'
        AND dossier ->> 'theme' ~ '[^[:space:]]'
      AND pg_catalog.jsonb_typeof(dossier -> 'problem') = 'string'
        AND dossier ->> 'problem' ~ '[^[:space:]]'
      AND pg_catalog.jsonb_typeof(dossier -> 'affected_people') = 'string'
        AND dossier ->> 'affected_people' ~ '[^[:space:]]'
      AND pg_catalog.jsonb_typeof(dossier -> 'possible_causes') = 'string'
        AND dossier ->> 'possible_causes' ~ '[^[:space:]]'
      AND pg_catalog.jsonb_typeof(dossier -> 'proposed_solution') = 'string'
        AND dossier ->> 'proposed_solution' ~ '[^[:space:]]'
      AND pg_catalog.jsonb_typeof(dossier -> 'beneficiary_group') = 'string'
        AND dossier ->> 'beneficiary_group' ~ '[^[:space:]]'
      AND pg_catalog.jsonb_typeof(dossier -> 'expected_outcome') = 'string'
        AND dossier ->> 'expected_outcome' ~ '[^[:space:]]'
      AND pg_catalog.jsonb_typeof(dossier -> 'implementation_barriers') = 'string'
        AND dossier ->> 'implementation_barriers' ~ '[^[:space:]]'
    ),
  CONSTRAINT idea_lifecycle_ideas_id_session_owner_key
    UNIQUE (id, session_id, user_id)
);

CREATE TABLE idea_lifecycle.idea_dossier_revisions (
  idea_id uuid NOT NULL,
  session_id uuid NOT NULL,
  owner_id uuid NOT NULL,
  revision bigint NOT NULL,
  snapshot_kind text NOT NULL,
  dossier jsonb NOT NULL,
  captured_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  CONSTRAINT idea_lifecycle_revisions_pkey PRIMARY KEY (idea_id, revision),
  CONSTRAINT idea_lifecycle_revisions_parent_fkey
    FOREIGN KEY (idea_id, session_id, owner_id)
    REFERENCES idea_lifecycle.ideas (id, session_id, user_id)
    ON DELETE CASCADE,
  CONSTRAINT idea_lifecycle_revisions_number_check CHECK (revision >= 1),
  CONSTRAINT idea_lifecycle_revisions_kind_check
    CHECK (
      (revision = 1 AND snapshot_kind = 'initial')
      OR (revision > 1 AND snapshot_kind = 'edit')
    ),
  CONSTRAINT idea_lifecycle_revisions_dossier_check
    CHECK (
      pg_catalog.jsonb_typeof(dossier) = 'object'
      AND (dossier - ARRAY[
        'theme', 'problem', 'affected_people', 'possible_causes',
        'proposed_solution', 'beneficiary_group', 'expected_outcome',
        'implementation_barriers'
      ]) = '{}'::jsonb
      AND dossier ?& ARRAY[
        'theme', 'problem', 'affected_people', 'possible_causes',
        'proposed_solution', 'beneficiary_group', 'expected_outcome',
        'implementation_barriers'
      ]
      AND pg_catalog.jsonb_typeof(dossier -> 'theme') = 'string'
        AND dossier ->> 'theme' ~ '[^[:space:]]'
      AND pg_catalog.jsonb_typeof(dossier -> 'problem') = 'string'
        AND dossier ->> 'problem' ~ '[^[:space:]]'
      AND pg_catalog.jsonb_typeof(dossier -> 'affected_people') = 'string'
        AND dossier ->> 'affected_people' ~ '[^[:space:]]'
      AND pg_catalog.jsonb_typeof(dossier -> 'possible_causes') = 'string'
        AND dossier ->> 'possible_causes' ~ '[^[:space:]]'
      AND pg_catalog.jsonb_typeof(dossier -> 'proposed_solution') = 'string'
        AND dossier ->> 'proposed_solution' ~ '[^[:space:]]'
      AND pg_catalog.jsonb_typeof(dossier -> 'beneficiary_group') = 'string'
        AND dossier ->> 'beneficiary_group' ~ '[^[:space:]]'
      AND pg_catalog.jsonb_typeof(dossier -> 'expected_outcome') = 'string'
        AND dossier ->> 'expected_outcome' ~ '[^[:space:]]'
      AND pg_catalog.jsonb_typeof(dossier -> 'implementation_barriers') = 'string'
        AND dossier ->> 'implementation_barriers' ~ '[^[:space:]]'
    )
);

CREATE TABLE idea_lifecycle.idea_operation_keys (
  session_id uuid NOT NULL,
  owner_id uuid NOT NULL,
  operation text NOT NULL,
  operation_key uuid NOT NULL,
  request_hash bytea NOT NULL,
  result_revision bigint,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  CONSTRAINT idea_lifecycle_operation_keys_pkey
    PRIMARY KEY (session_id, operation, operation_key),
  CONSTRAINT idea_lifecycle_operation_keys_session_owner_fkey
    FOREIGN KEY (session_id, owner_id)
    REFERENCES idea_lifecycle.idea_sessions (id, user_id)
    ON DELETE CASCADE,
  CONSTRAINT idea_lifecycle_operation_keys_operation_check
    CHECK (operation IN ('save_registered_draft', 'complete_dossier', 'edit_dossier')),
  CONSTRAINT idea_lifecycle_operation_keys_hash_check
    CHECK (pg_catalog.octet_length(request_hash) = 32),
  CONSTRAINT idea_lifecycle_operation_keys_revision_check
    CHECK (result_revision IS NULL OR result_revision >= 0)
);

CREATE INDEX idea_lifecycle_sessions_user_idx
  ON idea_lifecycle.idea_sessions (user_id, id);
CREATE INDEX idea_lifecycle_ideas_deadline_idx
  ON idea_lifecycle.ideas (edit_deadline_at, session_id)
  WHERE submitted_at IS NULL;
CREATE INDEX idea_lifecycle_revisions_session_idx
  ON idea_lifecycle.idea_dossier_revisions (session_id, revision);

COMMENT ON TABLE idea_lifecycle.idea_sessions IS
  'Lifecycle aggregate root and three-slot quota unit; registration is explicit and idempotent.';
COMMENT ON TABLE idea_lifecycle.ideas IS
  'Completed dossier aggregate; editing eligibility ends exactly 168 elapsed hours after completion.';
COMMENT ON TABLE idea_lifecycle.idea_dossier_revisions IS
  'Immutable completed-dossier snapshots; parent deletion cascades without a delete-blocking trigger.';
COMMENT ON TABLE idea_lifecycle.idea_operation_keys IS
  'Session-scoped idempotency receipts containing hashes and result metadata, never dossier content.';

COMMIT;