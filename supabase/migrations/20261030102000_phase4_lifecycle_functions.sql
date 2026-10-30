BEGIN;

DO $dependencies$
BEGIN
  IF pg_catalog.to_regnamespace('extensions') IS NULL
     OR pg_catalog.to_regprocedure('extensions.digest(bytea,text)') IS NULL THEN
    RAISE EXCEPTION 'Phase 4 requires pgcrypto digest(bytea,text) in schema extensions; inspect the installed extension namespace before applying';
  END IF;
END;
$dependencies$;

GRANT EXECUTE ON FUNCTION extensions.digest(bytea, text)
  TO idea_rpc_owner;

CREATE FUNCTION idea_lifecycle.is_valid_dossier(p_dossier jsonb)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
  v_key text;
BEGIN
  IF pg_catalog.jsonb_typeof(p_dossier) IS DISTINCT FROM 'object'
     OR (p_dossier - ARRAY[
       'theme', 'problem', 'affected_people', 'possible_causes',
       'proposed_solution', 'beneficiary_group', 'expected_outcome',
       'implementation_barriers'
     ]) <> '{}'::jsonb
     OR NOT (p_dossier ?& ARRAY[
       'theme', 'problem', 'affected_people', 'possible_causes',
       'proposed_solution', 'beneficiary_group', 'expected_outcome',
       'implementation_barriers'
     ]) THEN
    RETURN false;
  END IF;

  FOREACH v_key IN ARRAY ARRAY[
    'theme', 'problem', 'affected_people', 'possible_causes',
    'proposed_solution', 'beneficiary_group', 'expected_outcome',
    'implementation_barriers'
  ] LOOP
     IF pg_catalog.jsonb_typeof(p_dossier -> v_key) IS DISTINCT FROM 'string'
       OR (p_dossier ->> v_key) !~ '[^[:space:]]' THEN
      RETURN false;
    END IF;
  END LOOP;

  RETURN true;
END;
$function$;

CREATE FUNCTION idea_lifecycle.assert_aggregate_integrity(p_session_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
  v_state text;
  v_idea_id uuid;
  v_owner_id uuid;
  v_dossier jsonb;
  v_revision bigint;
  v_completed_at timestamptz;
  v_edit_deadline_at timestamptz;
  v_submitted_at timestamptz;
  v_snapshot_count bigint;
  v_min_revision bigint;
  v_max_revision bigint;
  v_initial_count bigint;
  v_edit_count bigint;
  v_latest_dossier jsonb;
BEGIN
  SELECT session.state
  INTO v_state
  FROM idea_lifecycle.idea_sessions AS session
  WHERE session.id = p_session_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT count(*)
  INTO v_snapshot_count
  FROM idea_lifecycle.idea_dossier_revisions AS snapshot
  WHERE snapshot.session_id = p_session_id;

  IF v_state = 'registered_draft' THEN
    IF EXISTS (
      SELECT 1 FROM idea_lifecycle.ideas AS idea
      WHERE idea.session_id = p_session_id
    ) OR v_snapshot_count <> 0 THEN
      RAISE EXCEPTION 'registered_draft must not have a completed dossier or snapshots'
        USING ERRCODE = '23514';
    END IF;
    RETURN;
  END IF;

    SELECT idea.id, idea.user_id, idea.dossier,
      idea.dossier_revision, idea.completed_at,
      idea.edit_deadline_at, idea.submitted_at
    INTO v_idea_id, v_owner_id, v_dossier, v_revision,
    v_completed_at, v_edit_deadline_at, v_submitted_at
  FROM idea_lifecycle.ideas AS idea
  WHERE idea.session_id = p_session_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'completed lifecycle state requires exactly one dossier'
      USING ERRCODE = '23514';
  END IF;

  IF EXISTS (
    SELECT 1 FROM idea_lifecycle.ideas AS idea
    WHERE idea.session_id = p_session_id AND idea.id <> v_idea_id
  ) THEN
    RAISE EXCEPTION 'lifecycle session has more than one dossier'
      USING ERRCODE = '23514';
  END IF;

    IF (v_state = 'editing_window' AND v_submitted_at IS NOT NULL)
      OR (v_state = 'submitted_for_evaluation'
        AND (v_submitted_at IS NULL OR v_submitted_at < v_edit_deadline_at)) THEN
    RAISE EXCEPTION 'dossier submission timestamp does not match lifecycle state'
      USING ERRCODE = '23514';
  END IF;

  SELECT count(*), min(snapshot.revision), max(snapshot.revision),
         count(*) FILTER (WHERE snapshot.snapshot_kind = 'initial'),
         count(*) FILTER (WHERE snapshot.snapshot_kind = 'edit')
  INTO v_snapshot_count, v_min_revision, v_max_revision,
       v_initial_count, v_edit_count
  FROM idea_lifecycle.idea_dossier_revisions AS snapshot
  WHERE snapshot.idea_id = v_idea_id
    AND snapshot.session_id = p_session_id
    AND snapshot.owner_id = v_owner_id;

  IF v_snapshot_count <> v_revision
     OR v_min_revision IS DISTINCT FROM 1
     OR v_max_revision IS DISTINCT FROM v_revision
     OR v_initial_count <> 1
     OR v_edit_count <> v_revision - 1 THEN
    RAISE EXCEPTION 'dossier snapshots must be contiguous and match the current revision'
      USING ERRCODE = '23514';
  END IF;

  SELECT snapshot.dossier
  INTO v_latest_dossier
  FROM idea_lifecycle.idea_dossier_revisions AS snapshot
  WHERE snapshot.idea_id = v_idea_id
    AND snapshot.revision = v_revision;

  IF v_latest_dossier IS DISTINCT FROM v_dossier THEN
    RAISE EXCEPTION 'current dossier differs from its latest immutable snapshot'
      USING ERRCODE = '23514';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (
      SELECT snapshot.revision, snapshot.captured_at,
             pg_catalog.lag(snapshot.captured_at) OVER (
               ORDER BY snapshot.revision
             ) AS previous_captured_at
      FROM idea_lifecycle.idea_dossier_revisions AS snapshot
      WHERE snapshot.idea_id = v_idea_id
    ) AS ordered_snapshots
    WHERE (ordered_snapshots.revision = 1
           AND ordered_snapshots.captured_at IS DISTINCT FROM v_completed_at)
       OR (ordered_snapshots.revision > 1
           AND ordered_snapshots.captured_at < ordered_snapshots.previous_captured_at)
       OR ordered_snapshots.captured_at > pg_catalog.clock_timestamp()
  ) THEN
    RAISE EXCEPTION 'dossier snapshot timestamps are inconsistent with completion and revision order'
      USING ERRCODE = '23514';
  END IF;
END;
$function$;

CREATE FUNCTION idea_lifecycle.check_aggregate_integrity_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
  v_session_id uuid;
BEGIN
  IF TG_TABLE_NAME = 'idea_sessions' THEN
    v_session_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END;
  ELSIF TG_TABLE_NAME = 'ideas'
     OR TG_TABLE_NAME = 'idea_dossier_revisions'
     OR TG_TABLE_NAME = 'idea_operation_keys' THEN
    v_session_id := CASE
      WHEN TG_OP = 'DELETE' THEN OLD.session_id
      ELSE NEW.session_id
    END;
  ELSE
    RAISE EXCEPTION 'unexpected relation for lifecycle integrity trigger';
  END IF;

  PERFORM idea_lifecycle.assert_aggregate_integrity(v_session_id);
  RETURN NULL;
END;
$function$;

CREATE FUNCTION idea_lifecycle.reject_revision_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $function$
BEGIN
  RAISE EXCEPTION 'completed dossier revision snapshots are immutable'
    USING ERRCODE = '55000';
END;
$function$;

CREATE FUNCTION idea_lifecycle.enforce_session_state_transition()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $function$
BEGIN
  IF NEW.state = OLD.state THEN
    RETURN NEW;
  END IF;

  IF OLD.state = 'registered_draft'
     AND NEW.state = 'editing_window'
     AND current_user = 'idea_rpc_owner' THEN
    RETURN NEW;
  END IF;

  IF OLD.state = 'editing_window'
     AND NEW.state = 'submitted_for_evaluation'
     AND current_user = 'idea_scheduler_owner'
     AND EXISTS (
       SELECT 1
       FROM idea_lifecycle.ideas AS idea
       WHERE idea.session_id = OLD.id
         AND idea.submitted_at IS NULL
         AND idea.edit_deadline_at <= pg_catalog.clock_timestamp()
     ) THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'lifecycle state transition is not permitted for this function owner'
    USING ERRCODE = '23514';
END;
$function$;

CREATE TRIGGER lifecycle_revisions_immutable_update
  BEFORE UPDATE ON idea_lifecycle.idea_dossier_revisions
  FOR EACH ROW EXECUTE FUNCTION idea_lifecycle.reject_revision_update();
CREATE TRIGGER lifecycle_sessions_state_transition
  BEFORE UPDATE OF state ON idea_lifecycle.idea_sessions
  FOR EACH ROW EXECUTE FUNCTION idea_lifecycle.enforce_session_state_transition();

CREATE CONSTRAINT TRIGGER lifecycle_sessions_integrity_check
  AFTER INSERT OR UPDATE OR DELETE ON idea_lifecycle.idea_sessions
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION idea_lifecycle.check_aggregate_integrity_trigger();
CREATE CONSTRAINT TRIGGER lifecycle_ideas_integrity_check
  AFTER INSERT OR UPDATE OR DELETE ON idea_lifecycle.ideas
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION idea_lifecycle.check_aggregate_integrity_trigger();
CREATE CONSTRAINT TRIGGER lifecycle_revisions_integrity_check
  AFTER INSERT OR UPDATE OR DELETE ON idea_lifecycle.idea_dossier_revisions
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION idea_lifecycle.check_aggregate_integrity_trigger();
CREATE CONSTRAINT TRIGGER lifecycle_operation_keys_integrity_check
  AFTER INSERT OR UPDATE OR DELETE ON idea_lifecycle.idea_operation_keys
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION idea_lifecycle.check_aggregate_integrity_trigger();

CREATE FUNCTION public.register_idea(
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
  v_request_hash bytea;
  v_existing_id uuid;
  v_existing_hash bytea;
  v_existing_state text;
  v_existing_revision bigint;
  v_session_id uuid;
  v_session_count bigint;
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

  v_request_hash := extensions.digest(
    pg_catalog.convert_to(
      pg_catalog.jsonb_build_object(
        'registration_data', p_registration_data
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  -- The same per-account lock serializes registration and permanent deletion.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_user_id::text, 0)
  );

    -- Resolve an identical retry before checking the three-session quota.
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

  SELECT count(*) INTO v_session_count
  FROM idea_lifecycle.idea_sessions AS session
  WHERE session.user_id = v_user_id;

  IF v_session_count >= 3 THEN
    RAISE EXCEPTION 'an account may have at most three registered ideas'
      USING ERRCODE = '23514';
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

CREATE FUNCTION public.save_registered_draft(
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

  -- Session locking serializes receipt lookup and revision changes.
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

  -- A matching receipt wins over stale revision/state checks on retries.
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
    RAISE EXCEPTION 'only registered drafts can be saved'
      USING ERRCODE = '55000';
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

CREATE FUNCTION public.complete_dossier(
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

  -- Lock the aggregate root before looking up its session-scoped receipt.
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

  -- Idempotent success is returned before rechecking state or draft revision.
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

  IF v_session.state <> 'registered_draft' THEN
    RAISE EXCEPTION 'only registered drafts can be completed'
      USING ERRCODE = '55000';
  END IF;
  IF v_session.draft_revision <> p_expected_draft_revision THEN
    RAISE EXCEPTION 'draft revision is stale' USING ERRCODE = '40001';
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

CREATE FUNCTION public.edit_dossier(
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

  -- Always lock session before idea; receipt replay precedes deadline checks.
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
    RAISE EXCEPTION 'dossier is not in its editing window'
      USING ERRCODE = '55000';
  END IF;

  -- Capture database time only after both session and dossier locks are held.
  SELECT * INTO v_idea
  FROM idea_lifecycle.ideas AS idea
  WHERE idea.session_id = p_session_id AND idea.user_id = v_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'completed dossier not found' USING ERRCODE = '23514';
  END IF;

  v_now := pg_catalog.clock_timestamp();
  IF v_now >= v_idea.edit_deadline_at OR v_idea.submitted_at IS NOT NULL THEN
    RAISE EXCEPTION 'dossier editing deadline has passed'
      USING ERRCODE = '55000';
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

CREATE FUNCTION public.permanently_delete_idea(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_session_id uuid;
  v_idea_id uuid;
BEGIN
    IF v_user_id IS NULL
      OR (auth.jwt() ->> 'role') IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'authenticated identity is required' USING ERRCODE = '42501';
  END IF;
  IF p_session_id IS NULL THEN
    RAISE EXCEPTION 'session id is required' USING ERRCODE = '22023';
  END IF;

  -- Take the same account lock as registration before session and idea locks.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_user_id::text, 0)
  );

  SELECT session.id INTO v_session_id
  FROM idea_lifecycle.idea_sessions AS session
  WHERE session.id = p_session_id AND session.user_id = v_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('deleted', false);
  END IF;

  SELECT idea.id INTO v_idea_id
  FROM idea_lifecycle.ideas AS idea
  WHERE idea.session_id = p_session_id AND idea.user_id = v_user_id
  FOR UPDATE;

  DELETE FROM idea_lifecycle.idea_sessions AS session
  WHERE session.id = p_session_id AND session.user_id = v_user_id;

  RETURN pg_catalog.jsonb_build_object('deleted', true);
END;
$function$;

CREATE FUNCTION public.finalize_expired_dossiers(p_batch_size integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
  v_completed integer := 0;
  v_session_id uuid;
  v_session_state text;
  v_idea_id uuid;
  v_deadline timestamptz;
  v_submitted_at timestamptz;
  v_now timestamptz;
  v_rows integer;
BEGIN
  IF p_batch_size IS NULL OR p_batch_size < 1 OR p_batch_size > 100 THEN
    RAISE EXCEPTION 'batch size must be between 1 and 100'
      USING ERRCODE = '22023';
  END IF;

  WHILE v_completed < p_batch_size LOOP
    v_session_id := NULL;

    -- Lock only one session; its idea is locked and finalized before the next iteration.
    SELECT session.id
    INTO v_session_id
    FROM idea_lifecycle.idea_sessions AS session
    JOIN idea_lifecycle.ideas AS idea
      ON idea.session_id = session.id
    WHERE session.state = 'editing_window'
      AND idea.submitted_at IS NULL
      AND idea.edit_deadline_at <= pg_catalog.clock_timestamp()
    ORDER BY session.id
    LIMIT 1
    FOR UPDATE OF session SKIP LOCKED;

    IF NOT FOUND THEN
      EXIT;
    END IF;

    SELECT idea.id, idea.edit_deadline_at, idea.submitted_at
    INTO v_idea_id, v_deadline, v_submitted_at
    FROM idea_lifecycle.ideas AS idea
    WHERE idea.session_id = v_session_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'locked lifecycle session has no corresponding dossier'
        USING ERRCODE = '23514';
    END IF;

    SELECT session.state
    INTO v_session_state
    FROM idea_lifecycle.idea_sessions AS session
    WHERE session.id = v_session_id;

    v_now := pg_catalog.clock_timestamp();
    IF v_session_state = 'editing_window'
       AND v_submitted_at IS NULL
       AND v_deadline <= v_now THEN
      UPDATE idea_lifecycle.idea_sessions
      SET state = 'submitted_for_evaluation'
      WHERE id = v_session_id
        AND state = 'editing_window';
      GET DIAGNOSTICS v_rows = ROW_COUNT;
      IF v_rows <> 1 THEN
        RAISE EXCEPTION 'finalizer failed to transition its locked session'
          USING ERRCODE = '40001';
      END IF;

      UPDATE idea_lifecycle.ideas
      SET submitted_at = v_now
      WHERE id = v_idea_id
        AND submitted_at IS NULL;
      GET DIAGNOSTICS v_rows = ROW_COUNT;
      IF v_rows <> 1 THEN
        RAISE EXCEPTION 'finalizer failed to timestamp its locked dossier'
          USING ERRCODE = '40001';
      END IF;

      v_completed := v_completed + 1;
    END IF;
  END LOOP;

  RETURN v_completed;
END;
$function$;

GRANT EXECUTE ON FUNCTION idea_lifecycle.is_valid_dossier(jsonb)
  TO idea_rpc_owner;
GRANT EXECUTE ON FUNCTION idea_lifecycle.assert_aggregate_integrity(uuid)
  TO idea_integrity_owner;

-- Temporary CREATE grants permit explicit function ownership transfer only.
GRANT CREATE ON SCHEMA idea_lifecycle TO idea_rpc_owner, idea_integrity_owner;
GRANT CREATE ON SCHEMA idea_lifecycle TO idea_scheduler_owner;
GRANT CREATE ON SCHEMA public TO idea_rpc_owner, idea_scheduler_owner;

ALTER FUNCTION idea_lifecycle.is_valid_dossier(jsonb) OWNER TO idea_rpc_owner;
ALTER FUNCTION idea_lifecycle.assert_aggregate_integrity(uuid)
  OWNER TO idea_integrity_owner;
ALTER FUNCTION idea_lifecycle.check_aggregate_integrity_trigger()
  OWNER TO idea_integrity_owner;
ALTER FUNCTION idea_lifecycle.reject_revision_update() OWNER TO idea_integrity_owner;
ALTER FUNCTION idea_lifecycle.enforce_session_state_transition()
  OWNER TO idea_rpc_owner;
ALTER FUNCTION public.register_idea(uuid, jsonb) OWNER TO idea_rpc_owner;
ALTER FUNCTION public.save_registered_draft(uuid, bigint, uuid, jsonb, smallint)
  OWNER TO idea_rpc_owner;
ALTER FUNCTION public.complete_dossier(uuid, bigint, uuid, jsonb)
  OWNER TO idea_rpc_owner;
ALTER FUNCTION public.edit_dossier(uuid, bigint, uuid, jsonb)
  OWNER TO idea_rpc_owner;
ALTER FUNCTION public.permanently_delete_idea(uuid) OWNER TO idea_rpc_owner;
ALTER FUNCTION public.finalize_expired_dossiers(integer)
  OWNER TO idea_scheduler_owner;

REVOKE CREATE ON SCHEMA idea_lifecycle
  FROM idea_rpc_owner, idea_integrity_owner, idea_scheduler_owner;
REVOKE CREATE ON SCHEMA public FROM idea_rpc_owner, idea_scheduler_owner;

REVOKE ALL ON FUNCTION idea_lifecycle.is_valid_dossier(jsonb)
  FROM PUBLIC, anon, authenticated, service_role,
       idea_integrity_owner, idea_scheduler_owner;
GRANT EXECUTE ON FUNCTION idea_lifecycle.is_valid_dossier(jsonb)
  TO idea_rpc_owner;
REVOKE ALL ON FUNCTION idea_lifecycle.assert_aggregate_integrity(uuid)
  FROM PUBLIC, anon, authenticated, service_role,
       idea_rpc_owner, idea_scheduler_owner;
GRANT EXECUTE ON FUNCTION idea_lifecycle.assert_aggregate_integrity(uuid)
  TO idea_integrity_owner;
REVOKE ALL ON FUNCTION idea_lifecycle.check_aggregate_integrity_trigger()
  FROM PUBLIC, anon, authenticated, service_role,
       idea_rpc_owner, idea_scheduler_owner;
GRANT EXECUTE ON FUNCTION idea_lifecycle.check_aggregate_integrity_trigger()
  TO idea_integrity_owner;
REVOKE ALL ON FUNCTION idea_lifecycle.reject_revision_update()
  FROM PUBLIC, anon, authenticated, service_role,
       idea_rpc_owner, idea_integrity_owner, idea_scheduler_owner;
REVOKE ALL ON FUNCTION idea_lifecycle.enforce_session_state_transition()
  FROM PUBLIC, anon, authenticated, service_role,
       idea_rpc_owner, idea_integrity_owner, idea_scheduler_owner;

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
REVOKE ALL ON FUNCTION public.finalize_expired_dossiers(integer)
  FROM PUBLIC, anon, authenticated, service_role,
       idea_rpc_owner, idea_integrity_owner;
GRANT EXECUTE ON FUNCTION public.register_idea(uuid, jsonb),
  public.save_registered_draft(uuid, bigint, uuid, jsonb, smallint),
  public.complete_dossier(uuid, bigint, uuid, jsonb),
  public.edit_dossier(uuid, bigint, uuid, jsonb),
  public.permanently_delete_idea(uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_expired_dossiers(integer)
  TO idea_scheduler_owner;

COMMENT ON FUNCTION public.register_idea(uuid, jsonb) IS
  'Idempotently registers one account-owned lifecycle session; registration_data is stored as the initial opaque draft object.';
COMMENT ON FUNCTION public.permanently_delete_idea(uuid) IS
  'Serializes with account registration before locking the session and dossier; all dependent lifecycle data is permanently cascaded.';
COMMENT ON FUNCTION idea_lifecycle.assert_aggregate_integrity(uuid) IS
  'Deferred, cross-table invariant checker. Its NOLOGIN owner has only restricted SELECT columns and explicit RLS visibility.';
COMMENT ON FUNCTION public.finalize_expired_dossiers(integer) IS
  'Processes one due session at a time: lock one session SKIP LOCKED, lock its idea, recheck with database time, finalize atomically, then select the next session.';

COMMIT;