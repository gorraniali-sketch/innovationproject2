\set ON_ERROR_STOP on

\if :{?expected_database_name}
\else
  \echo 'Set expected_database_name to the explicitly approved target database.'
  \quit 3
\endif
\if :{?expected_database_oid}
\else
  \echo 'Set expected_database_oid from the approved target database preflight.'
  \quit 3
\endif
\if :{?canary_nonce}
\else
  \echo 'Set canary_nonce to a fresh UUID for this validation run.'
  \quit 3
\endif

SELECT (
  pg_catalog.current_database() = :'expected_database_name'
  AND EXISTS (
    SELECT 1 FROM pg_catalog.pg_database AS database
    WHERE database.datname = pg_catalog.current_database()
      AND database.oid = :'expected_database_oid'::oid
  )
  AND EXISTS (
    SELECT 1 FROM pg_catalog.pg_extension AS extension
    WHERE extension.extname = 'pg_cron'
  )
  AND pg_catalog.to_regnamespace('cron') IS NOT NULL
  AND pg_catalog.to_regclass('cron.job') IS NOT NULL
  AND pg_catalog.to_regclass('cron.job_run_details') IS NOT NULL
  AND pg_catalog.to_regprocedure('cron.schedule(text,text,text)') IS NOT NULL
  AND pg_catalog.current_setting('shared_preload_libraries', true) LIKE '%pg_cron%'
  AND pg_catalog.current_setting('cron.database_name', true)
      = :'expected_database_name'
  AND EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles AS role
    WHERE role.rolname = 'idea_scheduler_owner'
      AND NOT role.rolcanlogin AND NOT role.rolsuper
      AND NOT role.rolcreatedb AND NOT role.rolcreaterole
      AND NOT role.rolinherit AND NOT role.rolbypassrls
  )
  AND pg_catalog.pg_get_userbyid((
    SELECT procedure.proowner
    FROM pg_catalog.pg_proc AS procedure
    WHERE procedure.oid =
      'public.finalize_expired_dossiers(integer)'::pg_catalog.regprocedure
  )) = 'idea_scheduler_owner'
  AND has_function_privilege(
    'idea_scheduler_owner', 'cron.schedule(text,text,text)', 'EXECUTE'
  )
  AND has_function_privilege(
    'idea_scheduler_owner', 'public.capture_lifecycle_scheduler_canary(uuid)', 'EXECUTE'
  )
  AND NOT EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'idea-lifecycle-canary'
  )
) AS preflight_passed
\gset

\if :preflight_passed
\else
  \echo 'Scheduler canary preflight failed. No job was scheduled.'
  \quit 3
\endif

BEGIN;
GRANT USAGE ON SCHEMA cron TO idea_scheduler_owner;
GRANT EXECUTE ON FUNCTION cron.schedule(text, text, text)
  TO idea_scheduler_owner;

SELECT (
  has_schema_privilege('idea_scheduler_owner', 'cron', 'USAGE')
  AND has_function_privilege(
    'idea_scheduler_owner', 'cron.schedule(text,text,text)', 'EXECUTE'
  )
) AS canary_scheduler_privileges_ready
\gset

\if :canary_scheduler_privileges_ready
\else
  ROLLBACK;
  \echo 'Scheduler role lacks the exact cron scheduling privileges.'
  \quit 3
\endif

SET LOCAL ROLE idea_scheduler_owner;

SELECT cron.schedule(
  'idea-lifecycle-canary',
  '* * * * *',
  'SELECT public.capture_lifecycle_scheduler_canary(''' || :'canary_nonce' || '''::uuid);'
);

RESET ROLE;
REVOKE EXECUTE ON FUNCTION cron.schedule(text, text, text)
  FROM idea_scheduler_owner;
REVOKE USAGE ON SCHEMA cron FROM idea_scheduler_owner;
COMMIT;

\echo 'Canary scheduled only. Verify persisted evidence and a successful cron.job_run_details row, then unschedule this canary.'
