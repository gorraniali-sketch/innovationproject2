BEGIN;

GRANT CREATE ON SCHEMA public TO idea_rpc_owner;
GRANT CREATE ON SCHEMA idea_lifecycle TO idea_scheduler_owner;

DO $default_privileges$
DECLARE
  v_public_oid oid := 'public'::pg_catalog.regnamespace;
  v_lifecycle_oid oid := 'idea_lifecycle'::pg_catalog.regnamespace;
  v_api_roles oid[];
BEGIN
  SELECT pg_catalog.array_agg(role.oid)
  INTO v_api_roles
  FROM pg_catalog.pg_roles AS role
  WHERE role.rolname IN ('anon', 'authenticated', 'service_role');

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_default_acl AS defaults
    CROSS JOIN LATERAL pg_catalog.aclexplode(defaults.defaclacl) AS acl
    WHERE defaults.defaclnamespace IN (0, v_public_oid, v_lifecycle_oid)
      AND (acl.grantee = 0 OR acl.grantee = ANY(v_api_roles))
  ) THEN
    RAISE EXCEPTION 'Unexpected PUBLIC/API default privileges exist in lifecycle schemas; inspect all object creators before continuing';
  END IF;

  EXECUTE pg_catalog.format(
    'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated, service_role',
    current_user
  );
  EXECUTE pg_catalog.format(
    'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role',
    current_user
  );
  EXECUTE pg_catalog.format(
    'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA idea_lifecycle REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated, service_role',
    current_user
  );
  EXECUTE pg_catalog.format(
    'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA idea_lifecycle REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role',
    current_user
  );
END;
$default_privileges$;

CREATE FUNCTION idea_lifecycle.guard_idea_lifecycle_timestamps()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $function$
BEGIN
  IF TG_OP = 'UPDATE'
     AND (NEW.completed_at IS DISTINCT FROM OLD.completed_at
          OR NEW.edit_deadline_at IS DISTINCT FROM OLD.edit_deadline_at) THEN
    RAISE EXCEPTION 'completion and editing deadline timestamps are immutable'
      USING ERRCODE = '23514';
  END IF;

  IF NEW.submitted_at IS DISTINCT FROM OLD.submitted_at THEN
    IF OLD.submitted_at IS NOT NULL
       OR NEW.submitted_at IS NULL
       OR current_user <> 'idea_scheduler_owner'
       OR NEW.submitted_at > pg_catalog.clock_timestamp()
       OR NEW.submitted_at < NEW.edit_deadline_at THEN
      RAISE EXCEPTION 'submission timestamp is write-once and scheduler-controlled'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

CREATE TRIGGER lifecycle_ideas_timestamp_guard
  BEFORE UPDATE OF completed_at, edit_deadline_at, submitted_at
  ON idea_lifecycle.ideas
  FOR EACH ROW EXECUTE FUNCTION idea_lifecycle.guard_idea_lifecycle_timestamps();

CREATE OR REPLACE FUNCTION public.register_idea(
  p_registration_key uuid,
  p_registration_data jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_blocked boolean;
  v_request_hash bytea;
  v_existing_id uuid;
  v_existing_hash bytea;
  v_existing_state text;
  v_existing_revision bigint;
  v_session_id uuid;
BEGIN
  IF v_user_id IS NULL
     OR (auth.jwt() ->> 'role') IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'authenticated identity is required' USING ERRCODE = '42501';
  END IF;
  IF p_registration_key IS NULL
     OR pg_catalog.jsonb_typeof(p_registration_data) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'registration key and object-valued registration data are required'
      USING ERRCODE = '22023';
  END IF;

  SELECT quota.integrity_blocked INTO v_blocked
  FROM idea_lifecycle.idea_account_quota AS quota
  WHERE quota.user_id = v_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'account quota row is missing; reconcile account before registration'
      USING ERRCODE = '23503';
  END IF;

  v_request_hash := extensions.digest(
    pg_catalog.convert_to(
      pg_catalog.jsonb_build_object(
        'registration_data', p_registration_data
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  SELECT session.id, session.registration_hash, session.state,
         session.draft_revision
  INTO v_existing_id, v_existing_hash, v_existing_state, v_existing_revision
  FROM idea_lifecycle.idea_sessions AS session
  WHERE session.user_id = v_user_id
    AND session.registration_key = p_registration_key;

  IF FOUND THEN
    IF v_existing_hash IS DISTINCT FROM v_request_hash THEN
      RAISE EXCEPTION 'registration key was already used with different data'
        USING ERRCODE = '23505';
    END IF;
    RETURN pg_catalog.jsonb_build_object(
      'session_id', v_existing_id,
      'state', v_existing_state,
      'revision', v_existing_revision,
      'replayed', true
    );
  END IF;

  IF v_blocked THEN
    RAISE EXCEPTION 'account quota is blocked pending integrity review'
      USING ERRCODE = '55000';
  END IF;

  INSERT INTO idea_lifecycle.idea_sessions (
    user_id, draft_data, registration_key, registration_hash
  ) VALUES (
    v_user_id, p_registration_data, p_registration_key, v_request_hash
  ) RETURNING id INTO v_session_id;

  RETURN pg_catalog.jsonb_build_object(
    'session_id', v_session_id,
    'state', 'registered_draft',
    'revision', 0,
    'replayed', false
  );
END;
$function$;
ALTER FUNCTION idea_lifecycle.guard_idea_lifecycle_timestamps()
  OWNER TO idea_scheduler_owner;

GRANT SELECT (
  idea_id, session_id, owner_id, revision, snapshot_kind, dossier, captured_at
)
  ON TABLE idea_lifecycle.idea_dossier_revisions TO idea_rpc_owner;

CREATE POLICY lifecycle_revisions_rpc_select
  ON idea_lifecycle.idea_dossier_revisions
  FOR SELECT TO idea_rpc_owner
  USING (owner_id = (SELECT auth.uid()));
REVOKE ALL ON FUNCTION idea_lifecycle.guard_idea_lifecycle_timestamps()
  FROM PUBLIC, anon, authenticated, service_role,
       idea_rpc_owner, idea_integrity_owner, idea_scheduler_owner;
REVOKE ALL ON FUNCTION extensions.digest(bytea, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION extensions.digest(bytea, text)
  TO idea_rpc_owner;

CREATE OR REPLACE FUNCTION public.save_registered_draft(
  p_session_id uuid,
  p_expected_revision bigint,
  p_idempotency_key uuid,
  p_draft_data jsonb,
  p_current_step smallint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_quota_user_id uuid;
  v_session idea_lifecycle.idea_sessions%ROWTYPE;
  v_request_hash bytea;
  v_prior_hash bytea;
  v_prior_revision bigint;
  v_new_revision bigint;
BEGIN
  IF v_user_id IS NULL
     OR (auth.jwt() ->> 'role') IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'authenticated identity is required' USING ERRCODE = '42501';
  END IF;
  IF p_session_id IS NULL OR p_expected_revision IS NULL
     OR p_idempotency_key IS NULL OR p_current_step IS NULL
     OR pg_catalog.jsonb_typeof(p_draft_data) IS DISTINCT FROM 'object'
     OR p_current_step NOT BETWEEN 1 AND 3 THEN
    RAISE EXCEPTION 'invalid draft operation input' USING ERRCODE = '22023';
  END IF;

  SELECT quota.user_id INTO v_quota_user_id
  FROM idea_lifecycle.idea_account_quota AS quota
  WHERE quota.user_id = v_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'account quota row is missing' USING ERRCODE = '23503';
  END IF;

  SELECT * INTO v_session
  FROM idea_lifecycle.idea_sessions AS session
  WHERE session.id = p_session_id AND session.user_id = v_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'idea session not found' USING ERRCODE = '42501';
  END IF;

  v_request_hash := extensions.digest(
    pg_catalog.convert_to(pg_catalog.jsonb_build_object(
      'operation', 'save_registered_draft',
      'session_id', p_session_id,
      'expected_revision', p_expected_revision,
      'draft_data', p_draft_data,
      'current_step', p_current_step
    )::text, 'UTF8'),
    'sha256'
  );

  SELECT operation.request_hash, operation.result_revision
  INTO v_prior_hash, v_prior_revision
  FROM idea_lifecycle.idea_operation_keys AS operation
  WHERE operation.session_id = p_session_id
    AND operation.owner_id = v_user_id
    AND operation.operation = 'save_registered_draft'
    AND operation.operation_key = p_idempotency_key;
  IF FOUND THEN
    IF v_prior_hash IS DISTINCT FROM v_request_hash THEN
      RAISE EXCEPTION 'idempotency key was reused with different input'
        USING ERRCODE = '23505';
    END IF;
    RETURN pg_catalog.jsonb_build_object(
      'session_id', p_session_id, 'revision', v_prior_revision, 'replayed', true
    );
  END IF;

  IF v_session.state <> 'registered_draft' THEN
    RAISE EXCEPTION 'only registered drafts can be saved' USING ERRCODE = '55000';
  END IF;
  IF v_session.draft_revision <> p_expected_revision THEN
    RAISE EXCEPTION 'draft revision is stale' USING ERRCODE = '40001';
  END IF;

  v_new_revision := v_session.draft_revision + 1;
  UPDATE idea_lifecycle.idea_sessions
  SET draft_data = p_draft_data,
      current_step = p_current_step,
      draft_revision = v_new_revision
  WHERE id = p_session_id;

  INSERT INTO idea_lifecycle.idea_operation_keys (
    session_id, owner_id, operation, operation_key, request_hash, result_revision
  ) VALUES (
    p_session_id, v_user_id, 'save_registered_draft', p_idempotency_key,
    v_request_hash, v_new_revision
  );

  RETURN pg_catalog.jsonb_build_object(
    'session_id', p_session_id, 'revision', v_new_revision, 'replayed', false
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.complete_dossier(
  p_session_id uuid,
  p_expected_draft_revision bigint,
  p_idempotency_key uuid,
  p_dossier jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_quota_user_id uuid;
  v_session idea_lifecycle.idea_sessions%ROWTYPE;
  v_request_hash bytea;
  v_prior_hash bytea;
  v_prior_revision bigint;
  v_idea_id uuid;
  v_now timestamptz;
BEGIN
  IF v_user_id IS NULL
     OR (auth.jwt() ->> 'role') IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'authenticated identity is required' USING ERRCODE = '42501';
  END IF;
  IF p_session_id IS NULL OR p_expected_draft_revision IS NULL
     OR p_idempotency_key IS NULL
     OR NOT idea_lifecycle.is_valid_dossier(p_dossier) THEN
    RAISE EXCEPTION 'invalid dossier completion input' USING ERRCODE = '22023';
  END IF;

  SELECT quota.user_id INTO v_quota_user_id
  FROM idea_lifecycle.idea_account_quota AS quota
  WHERE quota.user_id = v_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'account quota row is missing' USING ERRCODE = '23503';
  END IF;

  SELECT * INTO v_session
  FROM idea_lifecycle.idea_sessions AS session
  WHERE session.id = p_session_id AND session.user_id = v_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'idea session not found' USING ERRCODE = '42501';
  END IF;

  v_request_hash := extensions.digest(
    pg_catalog.convert_to(pg_catalog.jsonb_build_object(
      'operation', 'complete_dossier',
      'session_id', p_session_id,
      'expected_draft_revision', p_expected_draft_revision,
      'dossier', p_dossier
    )::text, 'UTF8'),
    'sha256'
  );

  SELECT operation.request_hash, operation.result_revision
  INTO v_prior_hash, v_prior_revision
  FROM idea_lifecycle.idea_operation_keys AS operation
  WHERE operation.session_id = p_session_id
    AND operation.owner_id = v_user_id
    AND operation.operation = 'complete_dossier'
    AND operation.operation_key = p_idempotency_key;
  IF FOUND THEN
    IF v_prior_hash IS DISTINCT FROM v_request_hash THEN
      RAISE EXCEPTION 'idempotency key was reused with different input'
        USING ERRCODE = '23505';
    END IF;
    SELECT idea.id INTO v_idea_id
    FROM idea_lifecycle.ideas AS idea
    WHERE idea.session_id = p_session_id AND idea.user_id = v_user_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'completion receipt has no corresponding dossier'
        USING ERRCODE = '23514';
    END IF;
    RETURN pg_catalog.jsonb_build_object(
      'session_id', p_session_id, 'idea_id', v_idea_id,
      'revision', v_prior_revision, 'replayed', true
    );
  END IF;

  IF v_session.state <> 'registered_draft'
     OR v_session.draft_revision <> p_expected_draft_revision THEN
    RAISE EXCEPTION 'draft state or revision is stale' USING ERRCODE = '40001';
  END IF;

  v_now := pg_catalog.clock_timestamp();
  INSERT INTO idea_lifecycle.ideas (
    session_id, user_id, dossier, dossier_revision,
    completed_at, edit_deadline_at
  ) VALUES (
    p_session_id, v_user_id, p_dossier, 1,
    v_now, v_now + INTERVAL '168 hours'
  ) RETURNING id INTO v_idea_id;

  INSERT INTO idea_lifecycle.idea_dossier_revisions (
    idea_id, session_id, owner_id, revision, snapshot_kind, dossier, captured_at
  ) VALUES (
    v_idea_id, p_session_id, v_user_id, 1, 'initial', p_dossier, v_now
  );

  UPDATE idea_lifecycle.idea_sessions
  SET state = 'editing_window'
  WHERE id = p_session_id;

  INSERT INTO idea_lifecycle.idea_operation_keys (
    session_id, owner_id, operation, operation_key, request_hash, result_revision
  ) VALUES (
    p_session_id, v_user_id, 'complete_dossier', p_idempotency_key,
    v_request_hash, 1
  );

  RETURN pg_catalog.jsonb_build_object(
    'session_id', p_session_id, 'idea_id', v_idea_id,
    'revision', 1, 'replayed', false
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.edit_dossier(
  p_session_id uuid,
  p_expected_dossier_revision bigint,
  p_idempotency_key uuid,
  p_dossier jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_quota_user_id uuid;
  v_session idea_lifecycle.idea_sessions%ROWTYPE;
  v_idea idea_lifecycle.ideas%ROWTYPE;
  v_request_hash bytea;
  v_prior_hash bytea;
  v_prior_revision bigint;
  v_new_revision bigint;
  v_now timestamptz;
BEGIN
  IF v_user_id IS NULL
     OR (auth.jwt() ->> 'role') IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'authenticated identity is required' USING ERRCODE = '42501';
  END IF;
  IF p_session_id IS NULL OR p_expected_dossier_revision IS NULL
     OR p_idempotency_key IS NULL
     OR NOT idea_lifecycle.is_valid_dossier(p_dossier) THEN
    RAISE EXCEPTION 'invalid dossier edit input' USING ERRCODE = '22023';
  END IF;

  SELECT quota.user_id INTO v_quota_user_id
  FROM idea_lifecycle.idea_account_quota AS quota
  WHERE quota.user_id = v_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'account quota row is missing' USING ERRCODE = '23503';
  END IF;

  SELECT * INTO v_session
  FROM idea_lifecycle.idea_sessions AS session
  WHERE session.id = p_session_id AND session.user_id = v_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'idea session not found' USING ERRCODE = '42501';
  END IF;

  v_request_hash := extensions.digest(
    pg_catalog.convert_to(pg_catalog.jsonb_build_object(
      'operation', 'edit_dossier',
      'session_id', p_session_id,
      'expected_dossier_revision', p_expected_dossier_revision,
      'dossier', p_dossier
    )::text, 'UTF8'),
    'sha256'
  );

  SELECT operation.request_hash, operation.result_revision
  INTO v_prior_hash, v_prior_revision
  FROM idea_lifecycle.idea_operation_keys AS operation
  WHERE operation.session_id = p_session_id
    AND operation.owner_id = v_user_id
    AND operation.operation = 'edit_dossier'
    AND operation.operation_key = p_idempotency_key;
  IF FOUND THEN
    IF v_prior_hash IS DISTINCT FROM v_request_hash THEN
      RAISE EXCEPTION 'idempotency key was reused with different input'
        USING ERRCODE = '23505';
    END IF;
    RETURN pg_catalog.jsonb_build_object(
      'session_id', p_session_id, 'revision', v_prior_revision, 'replayed', true
    );
  END IF;

  IF v_session.state <> 'editing_window' THEN
    RAISE EXCEPTION 'dossier is not in its editing window' USING ERRCODE = '55000';
  END IF;

  SELECT * INTO v_idea
  FROM idea_lifecycle.ideas AS idea
  WHERE idea.session_id = p_session_id AND idea.user_id = v_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'completed dossier not found' USING ERRCODE = '42501';
  END IF;

  v_now := pg_catalog.clock_timestamp();
  IF v_now >= v_idea.edit_deadline_at OR v_idea.submitted_at IS NOT NULL THEN
    RAISE EXCEPTION 'dossier editing deadline has passed' USING ERRCODE = '55000';
  END IF;
  IF v_idea.dossier_revision <> p_expected_dossier_revision THEN
    RAISE EXCEPTION 'dossier revision is stale' USING ERRCODE = '40001';
  END IF;

  v_new_revision := v_idea.dossier_revision + 1;
  UPDATE idea_lifecycle.ideas
  SET dossier = p_dossier, dossier_revision = v_new_revision
  WHERE id = v_idea.id;

  INSERT INTO idea_lifecycle.idea_dossier_revisions (
    idea_id, session_id, owner_id, revision, snapshot_kind, dossier, captured_at
  ) VALUES (
    v_idea.id, p_session_id, v_user_id, v_new_revision, 'edit', p_dossier, v_now
  );

  INSERT INTO idea_lifecycle.idea_operation_keys (
    session_id, owner_id, operation, operation_key, request_hash, result_revision
  ) VALUES (
    p_session_id, v_user_id, 'edit_dossier', p_idempotency_key,
    v_request_hash, v_new_revision
  );

  RETURN pg_catalog.jsonb_build_object(
    'session_id', p_session_id, 'revision', v_new_revision, 'replayed', false
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.permanently_delete_idea(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_quota_user_id uuid;
  v_session_id uuid;
BEGIN
  IF v_user_id IS NULL
     OR (auth.jwt() ->> 'role') IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'authenticated identity is required' USING ERRCODE = '42501';
  END IF;

  SELECT quota.user_id INTO v_quota_user_id
  FROM idea_lifecycle.idea_account_quota AS quota
  WHERE quota.user_id = v_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'account quota row is missing' USING ERRCODE = '23503';
  END IF;

  SELECT session.id INTO v_session_id
  FROM idea_lifecycle.idea_sessions AS session
  WHERE session.id = p_session_id AND session.user_id = v_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('deleted', false);
  END IF;

  PERFORM 1
  FROM idea_lifecycle.ideas AS idea
  WHERE idea.session_id = p_session_id AND idea.user_id = v_user_id
  FOR UPDATE;

  DELETE FROM idea_lifecycle.idea_sessions AS session
  WHERE session.id = p_session_id AND session.user_id = v_user_id;

  RETURN pg_catalog.jsonb_build_object('deleted', true);
END;
$function$;

CREATE FUNCTION public.delete_my_legacy_idea_session(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_quota_user_id uuid;
  v_session_id uuid;
BEGIN
  IF v_user_id IS NULL
     OR (auth.jwt() ->> 'role') IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'authenticated identity is required' USING ERRCODE = '42501';
  END IF;

  SELECT quota.user_id INTO v_quota_user_id
  FROM idea_lifecycle.idea_account_quota AS quota
  WHERE quota.user_id = v_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'account quota row is missing' USING ERRCODE = '23503';
  END IF;

  SELECT session.id INTO v_session_id
  FROM public.idea_sessions AS session
  WHERE session.id = p_session_id AND session.user_id = v_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('deleted', false);
  END IF;

  PERFORM pg_catalog.set_config(
    'app.idea_auth_cleanup_user_id', v_user_id::text, true
  );
  DELETE FROM public.idea_sessions AS session
  WHERE session.id = p_session_id AND session.user_id = v_user_id;
  PERFORM pg_catalog.set_config('app.idea_auth_cleanup_user_id', '', true);

  RETURN pg_catalog.jsonb_build_object('deleted', true);
END;
$function$;

CREATE FUNCTION public.list_my_idea_sessions()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_result jsonb;
BEGIN
  IF v_user_id IS NULL
     OR (auth.jwt() ->> 'role') IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'authenticated identity is required' USING ERRCODE = '42501';
  END IF;

  SELECT coalesce(
    pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'session_id', session.id,
      'state', session.state,
      'current_step', session.current_step,
      'draft_revision', session.draft_revision,
      'dossier_revision', idea.dossier_revision,
      'completed_at', idea.completed_at,
      'edit_deadline_at', idea.edit_deadline_at,
      'submitted_at', idea.submitted_at,
      'created_at', session.created_at,
      'updated_at', session.updated_at
    ) ORDER BY session.created_at DESC, session.id), '[]'::jsonb)
  INTO v_result
  FROM idea_lifecycle.idea_sessions AS session
  LEFT JOIN idea_lifecycle.ideas AS idea ON idea.session_id = session.id
  WHERE session.user_id = v_user_id;

  RETURN v_result;
END;
$function$;

CREATE FUNCTION public.get_my_idea_session(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_session idea_lifecycle.idea_sessions%ROWTYPE;
  v_idea idea_lifecycle.ideas%ROWTYPE;
BEGIN
  IF v_user_id IS NULL
     OR (auth.jwt() ->> 'role') IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'authenticated identity is required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_session
  FROM idea_lifecycle.idea_sessions AS session
  WHERE session.id = p_session_id AND session.user_id = v_user_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_idea
  FROM idea_lifecycle.ideas AS idea
  WHERE idea.session_id = v_session.id AND idea.user_id = v_user_id;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'session_id', v_session.id,
      'state', v_session.state,
      'current_step', v_session.current_step,
      'draft_revision', v_session.draft_revision,
      'draft_data', CASE WHEN v_session.state = 'registered_draft'
        THEN v_session.draft_data ELSE NULL END,
      'dossier', NULL,
      'dossier_revision', NULL,
      'completed_at', NULL,
      'edit_deadline_at', NULL,
      'submitted_at', NULL
    );
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'session_id', v_session.id,
    'state', v_session.state,
    'current_step', v_session.current_step,
    'draft_revision', v_session.draft_revision,
    'draft_data', CASE WHEN v_session.state = 'registered_draft'
      THEN v_session.draft_data ELSE NULL END,
    'dossier', v_idea.dossier,
    'dossier_revision', v_idea.dossier_revision,
    'completed_at', v_idea.completed_at,
    'edit_deadline_at', v_idea.edit_deadline_at,
    'submitted_at', v_idea.submitted_at
  );
END;
$function$;

CREATE FUNCTION public.list_my_idea_dossier_revisions(
  p_session_id uuid,
  p_after_revision bigint DEFAULT 0,
  p_limit integer DEFAULT 20
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_result jsonb;
BEGIN
  IF v_user_id IS NULL
     OR (auth.jwt() ->> 'role') IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'authenticated identity is required' USING ERRCODE = '42501';
  END IF;
  IF p_session_id IS NULL OR p_after_revision IS NULL
     OR p_after_revision < 0 OR p_limit IS NULL
     OR p_limit < 1 OR p_limit > 100 THEN
    RAISE EXCEPTION 'invalid revision pagination input' USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM idea_lifecycle.idea_sessions AS session
    WHERE session.id = p_session_id AND session.user_id = v_user_id
  ) THEN
    RETURN NULL;
  END IF;

  WITH page AS (
    SELECT snapshot.revision, snapshot.snapshot_kind,
           snapshot.dossier, snapshot.captured_at,
           pg_catalog.row_number() OVER (ORDER BY snapshot.revision) AS ordinal
    FROM idea_lifecycle.idea_dossier_revisions AS snapshot
    WHERE snapshot.session_id = p_session_id
      AND snapshot.owner_id = v_user_id
      AND snapshot.revision > p_after_revision
    ORDER BY snapshot.revision
    LIMIT p_limit + 1
  )
  SELECT pg_catalog.jsonb_build_object(
    'items', coalesce(
      pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'revision', page.revision,
        'snapshot_kind', page.snapshot_kind,
        'dossier', page.dossier,
        'captured_at', page.captured_at
      ) ORDER BY page.revision) FILTER (WHERE page.ordinal <= p_limit),
      '[]'::jsonb
    ),
    'next_after_revision', max(page.revision)
      FILTER (WHERE page.ordinal <= p_limit),
    'has_more', count(*) > p_limit
  ) INTO v_result
  FROM page;

  RETURN v_result;
END;
$function$;

ALTER FUNCTION public.register_idea(uuid, jsonb) OWNER TO idea_rpc_owner;
ALTER FUNCTION public.save_registered_draft(uuid, bigint, uuid, jsonb, smallint)
  OWNER TO idea_rpc_owner;
ALTER FUNCTION public.complete_dossier(uuid, bigint, uuid, jsonb)
  OWNER TO idea_rpc_owner;
ALTER FUNCTION public.edit_dossier(uuid, bigint, uuid, jsonb)
  OWNER TO idea_rpc_owner;
ALTER FUNCTION public.permanently_delete_idea(uuid) OWNER TO idea_rpc_owner;
ALTER FUNCTION public.delete_my_legacy_idea_session(uuid) OWNER TO idea_rpc_owner;
ALTER FUNCTION public.list_my_idea_sessions() OWNER TO idea_rpc_owner;
ALTER FUNCTION public.get_my_idea_session(uuid) OWNER TO idea_rpc_owner;
ALTER FUNCTION public.list_my_idea_dossier_revisions(uuid, bigint, integer)
  OWNER TO idea_rpc_owner;

REVOKE CREATE ON SCHEMA public FROM idea_rpc_owner;
REVOKE CREATE ON SCHEMA idea_lifecycle FROM idea_scheduler_owner;

REVOKE ALL ON FUNCTION public.register_idea(uuid, jsonb)
  FROM PUBLIC, anon, service_role, idea_integrity_owner, idea_scheduler_owner;
REVOKE ALL ON FUNCTION public.save_registered_draft(uuid, bigint, uuid, jsonb, smallint)
  FROM PUBLIC, anon, service_role, idea_integrity_owner, idea_scheduler_owner;
REVOKE ALL ON FUNCTION public.complete_dossier(uuid, bigint, uuid, jsonb)
  FROM PUBLIC, anon, service_role, idea_integrity_owner, idea_scheduler_owner;
REVOKE ALL ON FUNCTION public.edit_dossier(uuid, bigint, uuid, jsonb)
  FROM PUBLIC, anon, service_role, idea_integrity_owner, idea_scheduler_owner;
REVOKE ALL ON FUNCTION public.permanently_delete_idea(uuid)
  FROM PUBLIC, anon, service_role, idea_integrity_owner, idea_scheduler_owner;
REVOKE ALL ON FUNCTION public.delete_my_legacy_idea_session(uuid)
  FROM PUBLIC, anon, service_role, idea_integrity_owner, idea_scheduler_owner;
REVOKE ALL ON FUNCTION public.list_my_idea_sessions()
  FROM PUBLIC, anon, service_role, idea_integrity_owner, idea_scheduler_owner;
REVOKE ALL ON FUNCTION public.get_my_idea_session(uuid)
  FROM PUBLIC, anon, service_role, idea_integrity_owner, idea_scheduler_owner;
REVOKE ALL ON FUNCTION public.list_my_idea_dossier_revisions(uuid, bigint, integer)
  FROM PUBLIC, anon, service_role, idea_integrity_owner, idea_scheduler_owner;
GRANT EXECUTE ON FUNCTION public.register_idea(uuid, jsonb),
  public.save_registered_draft(uuid, bigint, uuid, jsonb, smallint),
  public.complete_dossier(uuid, bigint, uuid, jsonb),
  public.edit_dossier(uuid, bigint, uuid, jsonb),
  public.permanently_delete_idea(uuid),
  public.delete_my_legacy_idea_session(uuid),
  public.list_my_idea_sessions(),
  public.get_my_idea_session(uuid),
  public.list_my_idea_dossier_revisions(uuid, bigint, integer)
  TO authenticated;

REVOKE DELETE ON TABLE public.idea_sessions FROM PUBLIC, anon, service_role;
REVOKE DELETE ON TABLE public.idea_sessions FROM authenticated;

COMMENT ON FUNCTION public.delete_my_legacy_idea_session(uuid) IS
  'Quota-first owner deletion for legacy sessions; no operation receipt is created.';
COMMENT ON FUNCTION public.list_my_idea_dossier_revisions(uuid, bigint, integer) IS
  'Owner-scoped revision history with a hard maximum page size of 100.';

DO $effective_privileges$
DECLARE
  v_api_role text;
  v_rpc_signature text;
BEGIN
  FOREACH v_api_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF has_table_privilege(
         v_api_role, 'idea_lifecycle.idea_account_quota', 'SELECT'
       ) OR has_table_privilege(
         v_api_role, 'idea_lifecycle.idea_account_quota', 'INSERT'
       ) OR has_table_privilege(
         v_api_role, 'idea_lifecycle.idea_account_quota', 'UPDATE'
       ) OR has_table_privilege(
         v_api_role, 'idea_lifecycle.idea_account_quota', 'DELETE'
       ) THEN
      RAISE EXCEPTION 'API role % has effective quota-table access', v_api_role;
    END IF;
  END LOOP;

  FOREACH v_rpc_signature IN ARRAY ARRAY[
    'public.register_idea(uuid,jsonb)',
    'public.save_registered_draft(uuid,bigint,uuid,jsonb,smallint)',
    'public.complete_dossier(uuid,bigint,uuid,jsonb)',
    'public.edit_dossier(uuid,bigint,uuid,jsonb)',
    'public.permanently_delete_idea(uuid)',
    'public.delete_my_legacy_idea_session(uuid)',
    'public.list_my_idea_sessions()',
    'public.get_my_idea_session(uuid)',
    'public.list_my_idea_dossier_revisions(uuid,bigint,integer)'
  ] LOOP
    IF has_function_privilege('anon', v_rpc_signature, 'EXECUTE')
       OR has_function_privilege('service_role', v_rpc_signature, 'EXECUTE') THEN
      RAISE EXCEPTION 'anon or service_role can execute lifecycle RPC %',
        v_rpc_signature;
    END IF;
  END LOOP;
END;
$effective_privileges$;

COMMIT;