BEGIN;

CREATE TABLE idea_lifecycle.scheduler_canary_evidence (
  nonce uuid PRIMARY KEY,
  database_oid oid NOT NULL,
  database_name text NOT NULL,
  session_user_name text NOT NULL,
  invoker_current_user text NOT NULL,
  definer_current_user text NOT NULL,
  executed_at timestamptz NOT NULL,
  successful boolean NOT NULL DEFAULT true,
  CONSTRAINT scheduler_canary_success_check CHECK (successful)
);

ALTER TABLE idea_lifecycle.scheduler_canary_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE idea_lifecycle.scheduler_canary_evidence FORCE ROW LEVEL SECURITY;

CREATE POLICY scheduler_canary_scheduler_insert
  ON idea_lifecycle.scheduler_canary_evidence
  FOR INSERT TO idea_scheduler_owner
  WITH CHECK (
    database_oid = (
      SELECT database.oid
      FROM pg_catalog.pg_database AS database
      WHERE database.datname = pg_catalog.current_database()
    )
    AND database_name = pg_catalog.current_database()
    AND invoker_current_user = 'idea_scheduler_owner'
    AND definer_current_user = 'idea_scheduler_owner'
  );
CREATE POLICY scheduler_canary_integrity_read
  ON idea_lifecycle.scheduler_canary_evidence
  FOR SELECT TO idea_integrity_owner
  USING (true);

GRANT SELECT (
  nonce, database_oid, database_name, session_user_name,
  invoker_current_user, definer_current_user, executed_at, successful
)
  ON TABLE idea_lifecycle.scheduler_canary_evidence TO idea_integrity_owner;
GRANT INSERT (
  nonce, database_oid, database_name, session_user_name,
  invoker_current_user, definer_current_user, executed_at, successful
)
  ON TABLE idea_lifecycle.scheduler_canary_evidence TO idea_scheduler_owner;

CREATE FUNCTION idea_lifecycle.write_scheduler_canary(
  p_nonce uuid,
  p_database_oid oid,
  p_database_name text,
  p_session_user text,
  p_invoker_current_user text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
BEGIN
  IF p_nonce IS NULL
     OR p_database_oid IS DISTINCT FROM (
       SELECT database.oid
       FROM pg_catalog.pg_database AS database
       WHERE database.datname = pg_catalog.current_database()
     )
     OR p_database_name IS DISTINCT FROM pg_catalog.current_database()
     OR p_invoker_current_user IS DISTINCT FROM 'idea_scheduler_owner'
     OR current_user IS DISTINCT FROM 'idea_scheduler_owner' THEN
    RAISE EXCEPTION 'scheduler canary execution identity or target database mismatch'
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO idea_lifecycle.scheduler_canary_evidence (
    nonce, database_oid, database_name, session_user_name,
    invoker_current_user, definer_current_user, executed_at, successful
  ) VALUES (
    p_nonce, p_database_oid, p_database_name, p_session_user,
    p_invoker_current_user, current_user, pg_catalog.clock_timestamp(), true
  ) ON CONFLICT (nonce) DO NOTHING;
END;
$function$;

CREATE FUNCTION public.capture_lifecycle_scheduler_canary(p_nonce uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
  v_database_oid oid;
BEGIN
  SELECT database.oid INTO v_database_oid
  FROM pg_catalog.pg_database AS database
  WHERE database.datname = pg_catalog.current_database();

  PERFORM idea_lifecycle.write_scheduler_canary(
    p_nonce,
    v_database_oid,
    pg_catalog.current_database(),
    session_user::text,
    current_user::text
  );
END;
$function$;

GRANT CREATE ON SCHEMA public TO idea_scheduler_owner;
GRANT CREATE ON SCHEMA idea_lifecycle TO idea_scheduler_owner;

ALTER FUNCTION idea_lifecycle.write_scheduler_canary(uuid, oid, text, text, text)
  OWNER TO idea_scheduler_owner;
ALTER FUNCTION public.capture_lifecycle_scheduler_canary(uuid)
  OWNER TO idea_scheduler_owner;

REVOKE CREATE ON SCHEMA public FROM idea_scheduler_owner;
REVOKE CREATE ON SCHEMA idea_lifecycle FROM idea_scheduler_owner;

REVOKE ALL ON FUNCTION idea_lifecycle.write_scheduler_canary(uuid, oid, text, text, text)
  FROM PUBLIC, anon, authenticated, service_role,
       idea_rpc_owner, idea_integrity_owner;
GRANT EXECUTE ON FUNCTION idea_lifecycle.write_scheduler_canary(uuid, oid, text, text, text)
  TO idea_scheduler_owner;
REVOKE ALL ON FUNCTION public.capture_lifecycle_scheduler_canary(uuid)
  FROM PUBLIC, anon, authenticated, service_role,
       idea_rpc_owner, idea_integrity_owner;
GRANT EXECUTE ON FUNCTION public.capture_lifecycle_scheduler_canary(uuid)
  TO idea_scheduler_owner;

COMMIT;