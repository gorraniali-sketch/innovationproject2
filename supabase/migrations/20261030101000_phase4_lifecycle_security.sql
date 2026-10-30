BEGIN;

REVOKE ALL ON SCHEMA idea_lifecycle
  FROM PUBLIC, anon, authenticated, service_role,
       idea_rpc_owner, idea_integrity_owner, idea_scheduler_owner;
GRANT USAGE ON SCHEMA idea_lifecycle
  TO idea_rpc_owner, idea_integrity_owner, idea_scheduler_owner;
GRANT USAGE ON SCHEMA auth, extensions TO idea_rpc_owner;
GRANT EXECUTE ON FUNCTION auth.uid(), auth.jwt()
  TO idea_rpc_owner;
GRANT USAGE ON SCHEMA public TO authenticated, idea_scheduler_owner;

REVOKE ALL PRIVILEGES ON TABLE
  idea_lifecycle.idea_sessions,
  idea_lifecycle.ideas,
  idea_lifecycle.idea_dossier_revisions,
  idea_lifecycle.idea_operation_keys
  FROM PUBLIC, anon, authenticated, service_role,
       idea_rpc_owner, idea_integrity_owner, idea_scheduler_owner;

GRANT SELECT ON TABLE
  idea_lifecycle.idea_sessions,
  idea_lifecycle.ideas
  TO idea_rpc_owner;
GRANT SELECT (
  session_id, owner_id, operation, operation_key, request_hash, result_revision
)
  ON TABLE idea_lifecycle.idea_operation_keys TO idea_rpc_owner;
GRANT INSERT (user_id, draft_data, registration_key, registration_hash)
  ON TABLE idea_lifecycle.idea_sessions TO idea_rpc_owner;
GRANT UPDATE (state, current_step, draft_data, draft_revision)
  ON TABLE idea_lifecycle.idea_sessions TO idea_rpc_owner;
GRANT DELETE ON TABLE idea_lifecycle.idea_sessions TO idea_rpc_owner;
GRANT INSERT (
  session_id, user_id, dossier, dossier_revision, completed_at, edit_deadline_at
)
  ON TABLE idea_lifecycle.ideas TO idea_rpc_owner;
GRANT UPDATE (dossier, dossier_revision)
  ON TABLE idea_lifecycle.ideas TO idea_rpc_owner;
GRANT INSERT (
  idea_id, session_id, owner_id, revision, snapshot_kind, dossier, captured_at
)
  ON TABLE idea_lifecycle.idea_dossier_revisions TO idea_rpc_owner;
GRANT INSERT (
  session_id, owner_id, operation, operation_key, request_hash, result_revision
)
  ON TABLE idea_lifecycle.idea_operation_keys TO idea_rpc_owner;

GRANT SELECT (
  id, state
)
  ON TABLE idea_lifecycle.idea_sessions TO idea_integrity_owner;
GRANT SELECT (
  id, session_id, user_id, dossier, dossier_revision,
  completed_at, edit_deadline_at, submitted_at
)
  ON TABLE idea_lifecycle.ideas TO idea_integrity_owner;
GRANT SELECT (
  idea_id, session_id, owner_id, revision, snapshot_kind, dossier, captured_at
)
  ON TABLE idea_lifecycle.idea_dossier_revisions TO idea_integrity_owner;
GRANT SELECT (id, state), UPDATE (state)
  ON TABLE idea_lifecycle.idea_sessions TO idea_scheduler_owner;
GRANT SELECT (id, session_id, edit_deadline_at, submitted_at),
      UPDATE (submitted_at)
  ON TABLE idea_lifecycle.ideas TO idea_scheduler_owner;

ALTER TABLE idea_lifecycle.idea_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE idea_lifecycle.idea_sessions FORCE ROW LEVEL SECURITY;
ALTER TABLE idea_lifecycle.ideas ENABLE ROW LEVEL SECURITY;
ALTER TABLE idea_lifecycle.ideas FORCE ROW LEVEL SECURITY;
ALTER TABLE idea_lifecycle.idea_dossier_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE idea_lifecycle.idea_dossier_revisions FORCE ROW LEVEL SECURITY;
ALTER TABLE idea_lifecycle.idea_operation_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE idea_lifecycle.idea_operation_keys FORCE ROW LEVEL SECURITY;

CREATE POLICY lifecycle_sessions_rpc_select
  ON idea_lifecycle.idea_sessions
  FOR SELECT TO idea_rpc_owner
  USING (user_id = (SELECT auth.uid()));
CREATE POLICY lifecycle_sessions_rpc_insert
  ON idea_lifecycle.idea_sessions
  FOR INSERT TO idea_rpc_owner
  WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY lifecycle_sessions_rpc_update
  ON idea_lifecycle.idea_sessions
  FOR UPDATE TO idea_rpc_owner
  USING (
    user_id = (SELECT auth.uid())
    AND state IN ('registered_draft', 'editing_window')
  )
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND state IN ('registered_draft', 'editing_window')
  );
CREATE POLICY lifecycle_sessions_rpc_delete
  ON idea_lifecycle.idea_sessions
  FOR DELETE TO idea_rpc_owner
  USING (user_id = (SELECT auth.uid()));
CREATE POLICY lifecycle_sessions_integrity_visibility
  ON idea_lifecycle.idea_sessions
  FOR SELECT TO idea_integrity_owner
  USING (true);
CREATE POLICY lifecycle_sessions_scheduler_select
  ON idea_lifecycle.idea_sessions
  FOR SELECT TO idea_scheduler_owner
  USING (state = 'editing_window');
CREATE POLICY lifecycle_sessions_scheduler_update
  ON idea_lifecycle.idea_sessions
  FOR UPDATE TO idea_scheduler_owner
  USING (state = 'editing_window')
  WITH CHECK (state = 'submitted_for_evaluation');

CREATE POLICY lifecycle_ideas_rpc_select
  ON idea_lifecycle.ideas
  FOR SELECT TO idea_rpc_owner
  USING (user_id = (SELECT auth.uid()));
CREATE POLICY lifecycle_ideas_rpc_insert
  ON idea_lifecycle.ideas
  FOR INSERT TO idea_rpc_owner
  WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY lifecycle_ideas_rpc_update
  ON idea_lifecycle.ideas
  FOR UPDATE TO idea_rpc_owner
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY lifecycle_ideas_integrity_visibility
  ON idea_lifecycle.ideas
  FOR SELECT TO idea_integrity_owner
  USING (true);
CREATE POLICY lifecycle_ideas_scheduler_select
  ON idea_lifecycle.ideas
  FOR SELECT TO idea_scheduler_owner
  USING (
    submitted_at IS NULL
    AND edit_deadline_at <= pg_catalog.clock_timestamp()
  );
CREATE POLICY lifecycle_ideas_scheduler_update
  ON idea_lifecycle.ideas
  FOR UPDATE TO idea_scheduler_owner
  USING (
    submitted_at IS NULL
    AND edit_deadline_at <= pg_catalog.clock_timestamp()
  )
  WITH CHECK (submitted_at IS NOT NULL);

CREATE POLICY lifecycle_revisions_rpc_insert
  ON idea_lifecycle.idea_dossier_revisions
  FOR INSERT TO idea_rpc_owner
  WITH CHECK (owner_id = (SELECT auth.uid()));
CREATE POLICY lifecycle_revisions_integrity_visibility
  ON idea_lifecycle.idea_dossier_revisions
  FOR SELECT TO idea_integrity_owner
  USING (true);

CREATE POLICY lifecycle_operation_keys_rpc_select
  ON idea_lifecycle.idea_operation_keys
  FOR SELECT TO idea_rpc_owner
  USING (owner_id = (SELECT auth.uid()));
CREATE POLICY lifecycle_operation_keys_rpc_insert
  ON idea_lifecycle.idea_operation_keys
  FOR INSERT TO idea_rpc_owner
  WITH CHECK (owner_id = (SELECT auth.uid()));

CREATE TRIGGER lifecycle_sessions_set_updated_at
  BEFORE UPDATE ON idea_lifecycle.idea_sessions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER lifecycle_ideas_set_updated_at
  BEFORE UPDATE ON idea_lifecycle.ideas
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Preserve timestamp behavior while preventing API roles from calling triggers directly.
REVOKE ALL ON FUNCTION public.set_updated_at()
  FROM PUBLIC, anon, authenticated, service_role,
       idea_rpc_owner, idea_integrity_owner, idea_scheduler_owner;
REVOKE ALL ON FUNCTION public.sync_idea_session_status()
  FROM PUBLIC, anon, authenticated, service_role,
       idea_rpc_owner, idea_integrity_owner, idea_scheduler_owner;

    -- Keep the legacy sync triggers attached only to the legacy public table pair.
    -- Their data transition is not safe to retire until a separate mapping/cutover is approved.

COMMENT ON POLICY lifecycle_sessions_integrity_visibility
  ON idea_lifecycle.idea_sessions IS
  'Integrity checks need cross-owner visibility, but idea_integrity_owner has SELECT only on explicitly granted columns.';
COMMENT ON POLICY lifecycle_ideas_integrity_visibility
  ON idea_lifecycle.ideas IS
  'Integrity checks need cross-owner visibility, but idea_integrity_owner has SELECT only on explicitly granted columns.';
COMMENT ON POLICY lifecycle_revisions_integrity_visibility
  ON idea_lifecycle.idea_dossier_revisions IS
  'Integrity checks need cross-owner visibility, but idea_integrity_owner has SELECT only on explicitly granted columns.';

COMMENT ON FUNCTION public.sync_idea_session_status() IS
  'Legacy-only trigger function. Its existing triggers remain attached to legacy public tables during staged coexistence; new lifecycle tables do not use it.';

COMMIT;