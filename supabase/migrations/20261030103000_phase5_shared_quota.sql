BEGIN;

DO $preflight$
DECLARE
  v_role record;
BEGIN
  IF pg_catalog.to_regclass('public.idea_sessions') IS NULL
     OR pg_catalog.to_regclass('idea_lifecycle.idea_sessions') IS NULL
     OR pg_catalog.to_regclass('idea_lifecycle.idea_operation_keys') IS NULL THEN
    RAISE EXCEPTION 'Phase 4 lifecycle schema and legacy sessions must exist before shared quota installation';
  END IF;

  FOR v_role IN
    SELECT rolname, rolcanlogin, rolsuper, rolcreatedb,
           rolcreaterole, rolinherit, rolbypassrls
    FROM pg_catalog.pg_roles
    WHERE rolname IN (
      'idea_rpc_owner', 'idea_integrity_owner', 'idea_scheduler_owner'
    )
  LOOP
    IF v_role.rolcanlogin OR v_role.rolsuper OR v_role.rolcreatedb
       OR v_role.rolcreaterole OR v_role.rolinherit OR v_role.rolbypassrls THEN
      RAISE EXCEPTION 'Lifecycle role % has unexpected attributes', v_role.rolname;
    END IF;
  END LOOP;

  IF (SELECT count(*) FROM pg_catalog.pg_roles
      WHERE rolname IN (
        'idea_rpc_owner', 'idea_integrity_owner', 'idea_scheduler_owner'
      )) <> 3 THEN
    RAISE EXCEPTION 'All three approved lifecycle roles must exist';
  END IF;

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
    RAISE EXCEPTION 'Approved lifecycle roles must have no role memberships';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS relation
    JOIN pg_catalog.pg_roles AS owner_role
      ON owner_role.oid = relation.relowner
    WHERE relation.oid IN (
      'public.idea_sessions'::pg_catalog.regclass,
      'idea_lifecycle.idea_sessions'::pg_catalog.regclass,
      'idea_lifecycle.ideas'::pg_catalog.regclass
    )
      AND owner_role.rolname IN (
        'idea_rpc_owner', 'idea_integrity_owner', 'idea_scheduler_owner'
      )
  ) THEN
    RAISE EXCEPTION 'Lifecycle function-owner roles must not own session or idea tables';
  END IF;

  IF pg_catalog.to_regnamespace('idea_lifecycle') IS NULL THEN
    RAISE EXCEPTION 'Private lifecycle schema is missing';
  END IF;
  IF pg_catalog.to_regclass('idea_lifecycle.idea_account_quota') IS NOT NULL THEN
    RAISE EXCEPTION 'Quota table already exists; inspect migration history and reconcile before continuing';
  END IF;
END;
$preflight$;

-- Deploy during a write-maintenance window after draining active writers.
LOCK TABLE auth.users IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.idea_sessions IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE idea_lifecycle.idea_sessions IN SHARE ROW EXCLUSIVE MODE;

CREATE TABLE idea_lifecycle.idea_account_quota (
  user_id uuid PRIMARY KEY
    REFERENCES auth.users (id) ON DELETE CASCADE,
  registered_count bigint NOT NULL DEFAULT 0
    CONSTRAINT idea_account_quota_nonnegative CHECK (registered_count >= 0),
  integrity_blocked boolean NOT NULL DEFAULT false,
  integrity_detected_at timestamptz,
  integrity_details text,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  CONSTRAINT idea_account_quota_integrity_metadata_check
    CHECK (
      (integrity_blocked AND integrity_detected_at IS NOT NULL)
      OR NOT integrity_blocked
    )
);

DO $bootstrap_visibility$
BEGIN
    EXECUTE pg_catalog.format(
      'GRANT SELECT (user_id) ON TABLE idea_lifecycle.idea_sessions TO %I',
      current_user
    );
    EXECUTE pg_catalog.format(
      'CREATE POLICY phase5_lifecycle_quota_bootstrap_visibility ON idea_lifecycle.idea_sessions FOR SELECT TO %I USING (true)',
      current_user
    );
    EXECUTE pg_catalog.format(
      'GRANT SELECT (user_id) ON TABLE public.idea_sessions TO %I',
      current_user
    );
    EXECUTE pg_catalog.format(
      'CREATE POLICY phase5_legacy_quota_bootstrap_visibility ON public.idea_sessions FOR SELECT TO %I USING (true)',
      current_user
    );
  END;
  $bootstrap_visibility$;

COMMENT ON TABLE idea_lifecycle.idea_account_quota IS
  'Shared account quota across legacy and lifecycle sessions. Count intentionally has no upper bound for bootstrap compatibility.';

WITH all_sessions AS (
  SELECT session.user_id
  FROM public.idea_sessions AS session
  UNION ALL
  SELECT session.user_id
  FROM idea_lifecycle.idea_sessions AS session
), session_counts AS (
  SELECT all_sessions.user_id, pg_catalog.count(*)::bigint AS registered_count
  FROM all_sessions
  GROUP BY all_sessions.user_id
)
INSERT INTO idea_lifecycle.idea_account_quota (user_id, registered_count)
SELECT auth_user.id, coalesce(session_counts.registered_count, 0)
FROM auth.users AS auth_user
LEFT JOIN session_counts ON session_counts.user_id = auth_user.id;

DO $seed_check$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM auth.users AS auth_user
    LEFT JOIN idea_lifecycle.idea_account_quota AS quota
      ON quota.user_id = auth_user.id
    WHERE quota.user_id IS NULL
  ) OR EXISTS (
    SELECT 1
    FROM idea_lifecycle.idea_account_quota AS quota
    LEFT JOIN auth.users AS auth_user ON auth_user.id = quota.user_id
    WHERE auth_user.id IS NULL
  ) OR EXISTS (
    SELECT 1
    FROM idea_lifecycle.idea_account_quota AS quota
    LEFT JOIN (
      SELECT sessions.user_id, pg_catalog.count(*)::bigint AS session_count
      FROM (
        SELECT user_id FROM public.idea_sessions
        UNION ALL
        SELECT user_id FROM idea_lifecycle.idea_sessions
      ) AS sessions
      GROUP BY sessions.user_id
    ) AS actual ON actual.user_id = quota.user_id
    WHERE quota.registered_count <> coalesce(actual.session_count, 0)
  ) THEN
    RAISE EXCEPTION 'Shared quota bootstrap verification failed';
  END IF;
END;
$seed_check$;

CREATE FUNCTION idea_lifecycle.provision_account_quota()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
BEGIN
  INSERT INTO idea_lifecycle.idea_account_quota (user_id, registered_count)
  VALUES (NEW.id, 0);
  RETURN NEW;
END;
$function$;

CREATE FUNCTION idea_lifecycle.reserve_account_quota()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
  v_count bigint;
  v_blocked boolean;
BEGIN
  PERFORM 1
  FROM idea_lifecycle.idea_account_quota AS quota
  WHERE quota.user_id = NEW.user_id
  FOR UPDATE NOWAIT;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'account quota row is missing; reconcile account before registration'
      USING ERRCODE = '23503';
  END IF;

  UPDATE idea_lifecycle.idea_account_quota AS quota
  SET registered_count = quota.registered_count + 1,
      updated_at = pg_catalog.clock_timestamp()
  WHERE quota.user_id = NEW.user_id
    AND quota.integrity_blocked = false
    AND quota.registered_count < 3
  RETURNING quota.registered_count INTO v_count;

  IF FOUND THEN
    RETURN NEW;
  END IF;

  SELECT quota.registered_count, quota.integrity_blocked
  INTO v_count, v_blocked
  FROM idea_lifecycle.idea_account_quota AS quota
  WHERE quota.user_id = NEW.user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'account quota row is missing; reconcile account before registration'
      USING ERRCODE = '23503';
  ELSIF v_blocked THEN
    RAISE EXCEPTION 'account quota is blocked pending integrity review'
      USING ERRCODE = '55000';
  ELSE
    RAISE EXCEPTION 'account has reached the three-session quota'
      USING ERRCODE = '23514';
  END IF;
END;
$function$;

CREATE FUNCTION idea_lifecycle.release_account_quota()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
  v_count bigint;
BEGIN
  PERFORM 1
  FROM idea_lifecycle.idea_account_quota AS quota
  WHERE quota.user_id = OLD.user_id
  FOR UPDATE NOWAIT;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'account quota row is missing during ordinary session deletion'
      USING ERRCODE = '23503';
  END IF;

  UPDATE idea_lifecycle.idea_account_quota AS quota
  SET registered_count = quota.registered_count - 1,
      updated_at = pg_catalog.clock_timestamp()
  WHERE quota.user_id = OLD.user_id
    AND quota.registered_count > 0
  RETURNING quota.registered_count INTO v_count;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'account quota counter is already zero during session deletion'
      USING ERRCODE = '23514';
  END IF;

  RETURN OLD;
END;
$function$;

CREATE FUNCTION idea_lifecycle.cleanup_auth_user_before_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
  v_count bigint;
  v_remaining bigint;
BEGIN
  PERFORM 1
  FROM idea_lifecycle.idea_account_quota AS quota
  WHERE quota.user_id = OLD.id
  FOR UPDATE NOWAIT;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'account quota row is missing during Auth-user deletion'
      USING ERRCODE = '23503';
  END IF;

  PERFORM pg_catalog.set_config(
    'app.idea_auth_cleanup_user_id', OLD.id::text, true
  );

  DELETE FROM public.idea_sessions AS session
  WHERE session.user_id = OLD.id;

  DELETE FROM idea_lifecycle.idea_sessions AS session
  WHERE session.user_id = OLD.id;

  SELECT quota.registered_count INTO v_count
  FROM idea_lifecycle.idea_account_quota AS quota
  WHERE quota.user_id = OLD.id;

  SELECT
    (SELECT pg_catalog.count(*) FROM public.idea_sessions WHERE user_id = OLD.id)
    +
    (SELECT pg_catalog.count(*)
     FROM idea_lifecycle.idea_sessions WHERE user_id = OLD.id)
  INTO v_remaining;

  IF v_remaining <> 0 OR v_count <> 0 THEN
    RAISE EXCEPTION 'Auth cleanup did not remove all sessions and release quota'
      USING ERRCODE = '23514';
  END IF;

  DELETE FROM idea_lifecycle.idea_account_quota AS quota
  WHERE quota.user_id = OLD.id
    AND quota.registered_count = 0;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Auth cleanup could not delete the empty quota row'
      USING ERRCODE = '23514';
  END IF;

  PERFORM pg_catalog.set_config('app.idea_auth_cleanup_user_id', '', true);
  RETURN OLD;
END;
$function$;

CREATE FUNCTION idea_lifecycle.reject_session_identity_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $function$
BEGIN
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION 'session identity and ownership are immutable'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE FUNCTION idea_lifecycle.reject_session_truncate()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $function$
BEGIN
  RAISE EXCEPTION 'TRUNCATE is prohibited on quota-accounted session tables'
    USING ERRCODE = '42501';
END;
$function$;

CREATE OR REPLACE FUNCTION public.sync_idea_session_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.idea_sessions
    SET status = 'submitted'
    WHERE id = NEW.session_id
      AND user_id = NEW.user_id
      AND status = 'in_progress';

    IF NOT FOUND THEN
      RAISE EXCEPTION 'idea session is not available for submission'
        USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
  END IF;

  IF pg_catalog.current_setting('app.idea_auth_cleanup_user_id', true)
       = OLD.user_id::text THEN
    RETURN OLD;
  END IF;

  UPDATE public.idea_sessions
  SET status = 'in_progress'
  WHERE id = OLD.session_id
    AND user_id = OLD.user_id
    AND status = 'submitted';

  IF NOT FOUND
     AND EXISTS (
       SELECT 1 FROM public.idea_sessions
       WHERE id = OLD.session_id
     ) THEN
    RAISE EXCEPTION 'idea session cannot be reopened'
      USING ERRCODE = '23514';
  END IF;

  RETURN OLD;
END;
$function$;

CREATE FUNCTION idea_lifecycle.reconcile_account_quota(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
  v_stored bigint;
  v_legacy bigint;
  v_lifecycle bigint;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'user id is required for internal reconciliation'
      USING ERRCODE = '22023';
  END IF;

  SELECT quota.registered_count
  INTO v_stored
  FROM idea_lifecycle.idea_account_quota AS quota
  WHERE quota.user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('status', 'missing_quota_row');
  END IF;

  SELECT pg_catalog.count(*) INTO v_legacy
  FROM public.idea_sessions AS session
  WHERE session.user_id = p_user_id;

  SELECT pg_catalog.count(*) INTO v_lifecycle
  FROM idea_lifecycle.idea_sessions AS session
  WHERE session.user_id = p_user_id;

  IF v_stored <> v_legacy + v_lifecycle THEN
    UPDATE idea_lifecycle.idea_account_quota
    SET integrity_blocked = true,
        integrity_detected_at = pg_catalog.clock_timestamp(),
        integrity_details = pg_catalog.format(
          'stored=%s legacy=%s lifecycle=%s',
          v_stored, v_legacy, v_lifecycle
        ),
        updated_at = pg_catalog.clock_timestamp()
    WHERE user_id = p_user_id;

    RETURN pg_catalog.jsonb_build_object(
      'status', 'blocked_mismatch',
      'stored_count', v_stored,
      'observed_count', v_legacy + v_lifecycle
    );
  END IF;

  -- A clean comparison never clears a prior integrity block automatically.
  RETURN pg_catalog.jsonb_build_object(
    'status', 'consistent',
    'stored_count', v_stored
  );
END;
$function$;

ALTER TABLE idea_lifecycle.idea_account_quota ENABLE ROW LEVEL SECURITY;
ALTER TABLE idea_lifecycle.idea_account_quota FORCE ROW LEVEL SECURITY;

CREATE POLICY account_quota_rpc_select
  ON idea_lifecycle.idea_account_quota
  FOR SELECT TO idea_rpc_owner
  USING (
    user_id = (SELECT auth.uid())
    OR user_id::text = pg_catalog.current_setting(
      'app.idea_auth_cleanup_user_id', true
    )
  );
CREATE POLICY account_quota_rpc_update
  ON idea_lifecycle.idea_account_quota
  FOR UPDATE TO idea_rpc_owner
  USING (
    user_id = (SELECT auth.uid())
    OR user_id::text = pg_catalog.current_setting(
      'app.idea_auth_cleanup_user_id', true
    )
  )
  WITH CHECK (
    user_id = (SELECT auth.uid())
    OR user_id::text = pg_catalog.current_setting(
      'app.idea_auth_cleanup_user_id', true
    )
  );
CREATE POLICY account_quota_rpc_cleanup_delete
  ON idea_lifecycle.idea_account_quota
  FOR DELETE TO idea_rpc_owner
  USING (
    user_id::text = pg_catalog.current_setting(
      'app.idea_auth_cleanup_user_id', true
    )
  );
CREATE POLICY account_quota_integrity_select
  ON idea_lifecycle.idea_account_quota
  FOR SELECT TO idea_integrity_owner
  USING (true);
CREATE POLICY account_quota_integrity_insert
  ON idea_lifecycle.idea_account_quota
  FOR INSERT TO idea_integrity_owner
  WITH CHECK (true);
CREATE POLICY account_quota_integrity_update
  ON idea_lifecycle.idea_account_quota
  FOR UPDATE TO idea_integrity_owner
  USING (true)
  WITH CHECK (true);

DO $quota_verify_visibility$
BEGIN
  EXECUTE pg_catalog.format(
    'GRANT SELECT (user_id, registered_count) ON TABLE idea_lifecycle.idea_account_quota TO %I',
    current_user
  );
  EXECUTE pg_catalog.format(
    'CREATE POLICY phase5_quota_final_verify ON idea_lifecycle.idea_account_quota FOR SELECT TO %I USING (true)',
    current_user
  );
END;
$quota_verify_visibility$;

CREATE POLICY legacy_sessions_quota_owner_select
  ON public.idea_sessions
  FOR SELECT TO idea_rpc_owner
  USING (
    user_id = (SELECT auth.uid())
    OR user_id::text = pg_catalog.current_setting(
      'app.idea_auth_cleanup_user_id', true
    )
  );
CREATE POLICY legacy_sessions_quota_owner_delete
  ON public.idea_sessions
  FOR DELETE TO idea_rpc_owner
  USING (
    user_id = (SELECT auth.uid())
    OR user_id::text = pg_catalog.current_setting(
      'app.idea_auth_cleanup_user_id', true
    )
  );
CREATE POLICY legacy_sessions_integrity_select
  ON public.idea_sessions
  FOR SELECT TO idea_integrity_owner
  USING (true);
CREATE POLICY lifecycle_sessions_quota_owner_select
  ON idea_lifecycle.idea_sessions
  FOR SELECT TO idea_rpc_owner
  USING (
    user_id = (SELECT auth.uid())
    OR user_id::text = pg_catalog.current_setting(
      'app.idea_auth_cleanup_user_id', true
    )
  );
CREATE POLICY lifecycle_sessions_quota_owner_delete
  ON idea_lifecycle.idea_sessions
  FOR DELETE TO idea_rpc_owner
  USING (
    user_id = (SELECT auth.uid())
    OR user_id::text = pg_catalog.current_setting(
      'app.idea_auth_cleanup_user_id', true
    )
  );
CREATE POLICY lifecycle_sessions_integrity_select
  ON idea_lifecycle.idea_sessions
  FOR SELECT TO idea_integrity_owner
  USING (true);

REVOKE ALL ON SCHEMA idea_lifecycle
  FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA idea_lifecycle
  TO idea_rpc_owner, idea_integrity_owner;
GRANT USAGE ON SCHEMA public TO idea_rpc_owner, idea_integrity_owner;
GRANT USAGE ON SCHEMA auth TO idea_rpc_owner, idea_integrity_owner;

REVOKE ALL ON TABLE idea_lifecycle.idea_account_quota
  FROM PUBLIC, anon, authenticated, service_role,
       idea_rpc_owner, idea_integrity_owner, idea_scheduler_owner;
GRANT SELECT (user_id, registered_count, integrity_blocked)
  ON TABLE idea_lifecycle.idea_account_quota TO idea_rpc_owner;
GRANT UPDATE (registered_count, updated_at)
  ON TABLE idea_lifecycle.idea_account_quota TO idea_rpc_owner;
GRANT DELETE ON TABLE idea_lifecycle.idea_account_quota TO idea_rpc_owner;
GRANT SELECT (
  user_id, registered_count, integrity_blocked,
  integrity_detected_at, integrity_details
)
  ON TABLE idea_lifecycle.idea_account_quota TO idea_integrity_owner;
GRANT INSERT (user_id)
  ON TABLE idea_lifecycle.idea_account_quota TO idea_integrity_owner;
GRANT UPDATE (
  integrity_blocked, integrity_detected_at, integrity_details, updated_at
)
  ON TABLE idea_lifecycle.idea_account_quota TO idea_integrity_owner;

GRANT SELECT (id, user_id), DELETE
  ON TABLE public.idea_sessions TO idea_rpc_owner;
GRANT SELECT (id, user_id), DELETE
  ON TABLE idea_lifecycle.idea_sessions TO idea_rpc_owner;
GRANT SELECT (id, user_id)
  ON TABLE public.idea_sessions TO idea_integrity_owner;
GRANT SELECT (id, user_id)
  ON TABLE idea_lifecycle.idea_sessions TO idea_integrity_owner;

REVOKE DELETE ON TABLE public.idea_sessions FROM authenticated;
REVOKE TRUNCATE ON TABLE
  public.idea_sessions, idea_lifecycle.idea_sessions,
  idea_lifecycle.idea_account_quota
  FROM PUBLIC, anon, authenticated, service_role,
       idea_rpc_owner, idea_integrity_owner, idea_scheduler_owner;

GRANT CREATE ON SCHEMA idea_lifecycle TO idea_rpc_owner, idea_integrity_owner;

ALTER FUNCTION idea_lifecycle.provision_account_quota() OWNER TO idea_integrity_owner;
ALTER FUNCTION idea_lifecycle.reserve_account_quota() OWNER TO idea_rpc_owner;
ALTER FUNCTION idea_lifecycle.release_account_quota() OWNER TO idea_rpc_owner;
ALTER FUNCTION idea_lifecycle.cleanup_auth_user_before_delete()
  OWNER TO idea_rpc_owner;
ALTER FUNCTION idea_lifecycle.reconcile_account_quota(uuid)
  OWNER TO idea_integrity_owner;
ALTER FUNCTION idea_lifecycle.reject_session_identity_update()
  OWNER TO idea_rpc_owner;
ALTER FUNCTION idea_lifecycle.reject_session_truncate()
  OWNER TO idea_rpc_owner;

REVOKE CREATE ON SCHEMA idea_lifecycle FROM idea_rpc_owner, idea_integrity_owner;

REVOKE ALL ON FUNCTION idea_lifecycle.provision_account_quota()
  FROM PUBLIC, anon, authenticated, service_role,
       idea_rpc_owner, idea_scheduler_owner;
REVOKE ALL ON FUNCTION idea_lifecycle.reserve_account_quota()
  FROM PUBLIC, anon, authenticated, service_role,
       idea_integrity_owner, idea_scheduler_owner;
REVOKE ALL ON FUNCTION idea_lifecycle.release_account_quota()
  FROM PUBLIC, anon, authenticated, service_role,
       idea_integrity_owner, idea_scheduler_owner;
REVOKE ALL ON FUNCTION idea_lifecycle.cleanup_auth_user_before_delete()
  FROM PUBLIC, anon, authenticated, service_role,
       idea_integrity_owner, idea_scheduler_owner;
REVOKE ALL ON FUNCTION idea_lifecycle.reconcile_account_quota(uuid)
  FROM PUBLIC, anon, authenticated, service_role,
       idea_rpc_owner, idea_scheduler_owner;
GRANT EXECUTE ON FUNCTION idea_lifecycle.reconcile_account_quota(uuid)
  TO idea_integrity_owner;

CREATE TRIGGER auth_users_provision_idea_quota
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION idea_lifecycle.provision_account_quota();
CREATE TRIGGER auth_users_cleanup_idea_quota
  BEFORE DELETE ON auth.users
  FOR EACH ROW EXECUTE FUNCTION idea_lifecycle.cleanup_auth_user_before_delete();

CREATE TRIGGER legacy_idea_sessions_reserve_quota
  AFTER INSERT ON public.idea_sessions
  FOR EACH ROW EXECUTE FUNCTION idea_lifecycle.reserve_account_quota();
CREATE TRIGGER legacy_idea_sessions_release_quota
  BEFORE DELETE ON public.idea_sessions
  FOR EACH ROW EXECUTE FUNCTION idea_lifecycle.release_account_quota();
CREATE TRIGGER lifecycle_idea_sessions_reserve_quota
  AFTER INSERT ON idea_lifecycle.idea_sessions
  FOR EACH ROW EXECUTE FUNCTION idea_lifecycle.reserve_account_quota();
CREATE TRIGGER lifecycle_idea_sessions_release_quota
  BEFORE DELETE ON idea_lifecycle.idea_sessions
  FOR EACH ROW EXECUTE FUNCTION idea_lifecycle.release_account_quota();

CREATE TRIGGER legacy_idea_sessions_identity_immutable
  BEFORE UPDATE OF id, user_id ON public.idea_sessions
  FOR EACH ROW EXECUTE FUNCTION idea_lifecycle.reject_session_identity_update();
CREATE TRIGGER lifecycle_idea_sessions_identity_immutable
  BEFORE UPDATE OF id, user_id ON idea_lifecycle.idea_sessions
  FOR EACH ROW EXECUTE FUNCTION idea_lifecycle.reject_session_identity_update();
CREATE TRIGGER legacy_idea_sessions_no_truncate
  BEFORE TRUNCATE ON public.idea_sessions
  FOR EACH STATEMENT EXECUTE FUNCTION idea_lifecycle.reject_session_truncate();
CREATE TRIGGER lifecycle_idea_sessions_no_truncate
  BEFORE TRUNCATE ON idea_lifecycle.idea_sessions
  FOR EACH STATEMENT EXECUTE FUNCTION idea_lifecycle.reject_session_truncate();
CREATE TRIGGER quota_no_truncate
  BEFORE TRUNCATE ON idea_lifecycle.idea_account_quota
  FOR EACH STATEMENT EXECUTE FUNCTION idea_lifecycle.reject_session_truncate();

REVOKE ALL ON FUNCTION idea_lifecycle.reject_session_identity_update()
  FROM PUBLIC, anon, authenticated, service_role,
       idea_rpc_owner, idea_integrity_owner, idea_scheduler_owner;
REVOKE ALL ON FUNCTION idea_lifecycle.reject_session_truncate()
  FROM PUBLIC, anon, authenticated, service_role,
       idea_rpc_owner, idea_integrity_owner, idea_scheduler_owner;

-- Keep the old registration/deletion API unavailable during the migration gap;
-- the next migration reinstalls these grants on quota-aware replacements.
REVOKE ALL ON FUNCTION public.register_idea(uuid, jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.permanently_delete_idea(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

DO $final_verify$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM auth.users AS auth_user
    LEFT JOIN idea_lifecycle.idea_account_quota AS quota
      ON quota.user_id = auth_user.id
    WHERE quota.user_id IS NULL
  ) OR EXISTS (
    SELECT 1
    FROM idea_lifecycle.idea_account_quota AS quota
    LEFT JOIN auth.users AS auth_user ON auth_user.id = quota.user_id
    WHERE auth_user.id IS NULL
  ) OR EXISTS (
    SELECT 1
    FROM idea_lifecycle.idea_account_quota AS quota
    LEFT JOIN (
      SELECT sessions.user_id, pg_catalog.count(*)::bigint AS session_count
      FROM (
        SELECT user_id FROM public.idea_sessions
        UNION ALL
        SELECT user_id FROM idea_lifecycle.idea_sessions
      ) AS sessions
      GROUP BY sessions.user_id
    ) AS actual ON actual.user_id = quota.user_id
    WHERE quota.registered_count <> coalesce(actual.session_count, 0)
  ) THEN
    RAISE EXCEPTION 'Quota rows or counts do not match Auth users and both session tables after trigger installation';
  END IF;
END;
$final_verify$;

DO $remove_bootstrap_visibility$
BEGIN
  DROP POLICY phase5_lifecycle_quota_bootstrap_visibility
    ON idea_lifecycle.idea_sessions;
  DROP POLICY phase5_legacy_quota_bootstrap_visibility
    ON public.idea_sessions;
  EXECUTE pg_catalog.format(
    'REVOKE SELECT (user_id) ON TABLE idea_lifecycle.idea_sessions FROM %I',
    current_user
  );
  EXECUTE pg_catalog.format(
    'REVOKE SELECT (user_id) ON TABLE public.idea_sessions FROM %I',
    current_user
  );
END;
$remove_bootstrap_visibility$;

DO $remove_quota_verify_visibility$
BEGIN
  DROP POLICY phase5_quota_final_verify
    ON idea_lifecycle.idea_account_quota;
  EXECUTE pg_catalog.format(
    'REVOKE SELECT (user_id, registered_count) ON TABLE idea_lifecycle.idea_account_quota FROM %I',
    current_user
  );
END;
$remove_quota_verify_visibility$;

COMMIT;