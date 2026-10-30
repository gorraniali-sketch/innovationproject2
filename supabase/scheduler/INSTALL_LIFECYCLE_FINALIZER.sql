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
\if :{?expected_cron_session_user}
\else
  \echo 'Set expected_cron_session_user to the login identity observed in the successful canary.'
  \quit 3
\endif
\if :{?canary_nonce}
\else
  \echo 'Set canary_nonce to the nonce persisted by the successful scheduler canary.'
  \quit 3
\endif

SELECT (
  pg_catalog.current_database() = :'expected_database_name'
  AND EXISTS (
    SELECT 1 FROM pg_catalog.pg_database AS database
    WHERE database.datname = pg_catalog.current_database()
      AND database.oid = :'expected_database_oid'::oid
  )
  AND pg_catalog.current_setting('cron.database_name', true)
      = :'expected_database_name'
  AND pg_catalog.current_setting('shared_preload_libraries', true) LIKE '%pg_cron%'
  AND EXISTS (
    SELECT 1
    FROM pg_catalog.pg_extension AS extension
    WHERE extension.extname = 'pg_cron'
  )
  AND EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles AS role
    WHERE role.rolname = 'idea_scheduler_owner'
      AND NOT role.rolcanlogin AND NOT role.rolsuper
      AND NOT role.rolcreatedb AND NOT role.rolcreaterole
      AND NOT role.rolinherit AND NOT role.rolbypassrls
  )
  AND has_schema_privilege('idea_scheduler_owner', 'public', 'USAGE')
  AND has_function_privilege(
    'idea_scheduler_owner',
    'public.finalize_expired_dossiers(integer)', 'EXECUTE'
  )
  AND has_column_privilege(
    'idea_scheduler_owner', 'idea_lifecycle.idea_sessions', 'state', 'UPDATE'
  )
  AND has_column_privilege(
    'idea_scheduler_owner', 'idea_lifecycle.ideas', 'submitted_at', 'UPDATE'
  )
  AND pg_catalog.pg_get_userbyid((
    SELECT procedure.proowner FROM pg_catalog.pg_proc AS procedure
    WHERE procedure.oid =
      'public.finalize_expired_dossiers(integer)'::pg_catalog.regprocedure
  )) = 'idea_scheduler_owner'
  AND EXISTS (
    SELECT 1
    FROM idea_lifecycle.scheduler_canary_evidence AS evidence
    JOIN cron.job AS job
      ON job.jobname = 'idea-lifecycle-canary'
     AND job.username = 'idea_scheduler_owner'
     AND job.command LIKE '%' || evidence.nonce::text || '%'
    JOIN cron.job_run_details AS run
      ON run.jobid = job.jobid
     AND run.status = 'succeeded'
     AND run.start_time <= evidence.executed_at
     AND run.end_time >= evidence.executed_at
    WHERE evidence.nonce = :'canary_nonce'::uuid
      AND evidence.database_oid = :'expected_database_oid'::oid
      AND evidence.database_name = :'expected_database_name'
      AND evidence.session_user_name = :'expected_cron_session_user'
      AND evidence.successful
      AND evidence.invoker_current_user = 'idea_scheduler_owner'
      AND evidence.definer_current_user = 'idea_scheduler_owner'
  )
  AND NOT EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'idea-lifecycle-finalizer'
  )
) AS finalizer_preflight_passed
\gset

\if :finalizer_preflight_passed
\else
  \echo 'Finalizer preflight failed. No finalizer job was scheduled.'
  \quit 3
\endif

BEGIN;
GRANT USAGE ON SCHEMA cron TO idea_scheduler_owner;
GRANT EXECUTE ON FUNCTION cron.schedule(text, text, text)
  TO idea_scheduler_owner;
SET LOCAL ROLE idea_scheduler_owner;

SELECT cron.schedule(
  'idea-lifecycle-finalizer',
  '* * * * *',
  'SELECT public.finalize_expired_dossiers(100);'
);

RESET ROLE;
REVOKE EXECUTE ON FUNCTION cron.schedule(text, text, text)
  FROM idea_scheduler_owner;
REVOKE USAGE ON SCHEMA cron FROM idea_scheduler_owner;

SELECT EXISTS (
  SELECT 1 FROM cron.job
  WHERE jobname = 'idea-lifecycle-finalizer'
    AND username = 'idea_scheduler_owner'
    AND command = 'SELECT public.finalize_expired_dossiers(100);'
    AND schedule = '* * * * *'
) AS finalizer_job_stored_correctly
\gset

\if :finalizer_job_stored_correctly
  COMMIT;
  \echo 'Finalizer job is stored. Verify its first successful cron.job_run_details row and due-row outcome before declaring activation complete.'
\else
  ROLLBACK;
  \echo 'Finalizer job metadata did not match; the transaction was rolled back.'
  \quit 3
\endif