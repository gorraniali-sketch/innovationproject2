CREATE TABLE public.idea_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'in_progress',
  current_step smallint NOT NULL DEFAULT 1,
  draft_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT idea_sessions_status_check
    CHECK (status IN ('in_progress', 'submitted')),
  CONSTRAINT idea_sessions_current_step_check
    CHECK (current_step BETWEEN 1 AND 3),
  CONSTRAINT idea_sessions_draft_data_object_check
    CHECK (jsonb_typeof(draft_data) = 'object'),
  CONSTRAINT idea_sessions_id_user_id_key UNIQUE (id, user_id)
);

CREATE TABLE public.ideas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL UNIQUE,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  theme text NOT NULL,
  problem text NOT NULL,
  affected_people text NOT NULL,
  possible_causes text NOT NULL,
  proposed_solution text NOT NULL,
  beneficiary_group text NOT NULL,
  expected_outcome text NOT NULL,
  implementation_barriers text NOT NULL,
  status text NOT NULL DEFAULT 'submitted',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ideas_session_owner_fkey
    FOREIGN KEY (session_id, user_id)
    REFERENCES public.idea_sessions (id, user_id)
    ON DELETE CASCADE,
  CONSTRAINT ideas_status_check
    CHECK (status IN ('submitted', 'archived')),
  CONSTRAINT ideas_theme_nonempty_check CHECK (theme ~ '[^[:space:]]'),
  CONSTRAINT ideas_problem_nonempty_check CHECK (problem ~ '[^[:space:]]'),
  CONSTRAINT ideas_affected_people_nonempty_check
    CHECK (affected_people ~ '[^[:space:]]'),
  CONSTRAINT ideas_possible_causes_nonempty_check
    CHECK (possible_causes ~ '[^[:space:]]'),
  CONSTRAINT ideas_proposed_solution_nonempty_check
    CHECK (proposed_solution ~ '[^[:space:]]'),
  CONSTRAINT ideas_beneficiary_group_nonempty_check
    CHECK (beneficiary_group ~ '[^[:space:]]'),
  CONSTRAINT ideas_expected_outcome_nonempty_check
    CHECK (expected_outcome ~ '[^[:space:]]'),
  CONSTRAINT ideas_implementation_barriers_nonempty_check
    CHECK (implementation_barriers ~ '[^[:space:]]')
);

CREATE INDEX idea_sessions_user_id_idx
  ON public.idea_sessions (user_id);
CREATE INDEX ideas_user_id_idx
  ON public.ideas (user_id);

CREATE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
  NEW.updated_at := pg_catalog.now();
  RETURN NEW;
END;
$function$;

CREATE TRIGGER idea_sessions_set_updated_at
  BEFORE UPDATE ON public.idea_sessions
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER ideas_set_updated_at
  BEFORE UPDATE ON public.ideas
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE FUNCTION public.sync_idea_session_status()
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

  UPDATE public.idea_sessions
  SET status = 'in_progress'
  WHERE id = OLD.session_id
    AND user_id = OLD.user_id
    AND status = 'submitted';

  IF NOT FOUND
     AND EXISTS (
       SELECT 1
       FROM public.idea_sessions
       WHERE id = OLD.session_id
     ) THEN
    RAISE EXCEPTION 'idea session cannot be reopened'
      USING ERRCODE = '23514';
  END IF;

  RETURN OLD;
END;
$function$;

CREATE TRIGGER ideas_sync_session_after_insert
  AFTER INSERT ON public.ideas
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_idea_session_status();

CREATE TRIGGER ideas_sync_session_after_delete
  AFTER DELETE ON public.ideas
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_idea_session_status();

REVOKE ALL ON FUNCTION public.set_updated_at()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_idea_session_status()
  FROM PUBLIC, anon, authenticated;

ALTER TABLE public.idea_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ideas ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON TABLE public.idea_sessions
  FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.ideas
  FROM PUBLIC, anon, authenticated;

GRANT SELECT, DELETE ON TABLE public.idea_sessions TO authenticated;
GRANT INSERT (user_id, current_step, draft_data)
  ON TABLE public.idea_sessions TO authenticated;
GRANT UPDATE (current_step, draft_data)
  ON TABLE public.idea_sessions TO authenticated;

GRANT SELECT, DELETE ON TABLE public.ideas TO authenticated;
GRANT INSERT (
  session_id,
  user_id,
  theme,
  problem,
  affected_people,
  possible_causes,
  proposed_solution,
  beneficiary_group,
  expected_outcome,
  implementation_barriers
)
  ON TABLE public.ideas TO authenticated;
GRANT UPDATE (
  theme,
  problem,
  affected_people,
  possible_causes,
  proposed_solution,
  beneficiary_group,
  expected_outcome,
  implementation_barriers
)
  ON TABLE public.ideas TO authenticated;

CREATE POLICY idea_sessions_select_own
  ON public.idea_sessions
  FOR SELECT
  TO authenticated
  USING ((SELECT auth.uid()) = user_id);

CREATE POLICY idea_sessions_insert_own
  ON public.idea_sessions
  FOR INSERT
  TO authenticated
  WITH CHECK (
    (SELECT auth.uid()) = user_id
    AND status = 'in_progress'
  );

CREATE POLICY idea_sessions_update_own_draft
  ON public.idea_sessions
  FOR UPDATE
  TO authenticated
  USING (
    (SELECT auth.uid()) = user_id
    AND status = 'in_progress'
  )
  WITH CHECK (
    (SELECT auth.uid()) = user_id
    AND status = 'in_progress'
  );

CREATE POLICY idea_sessions_delete_own
  ON public.idea_sessions
  FOR DELETE
  TO authenticated
  USING ((SELECT auth.uid()) = user_id);

CREATE POLICY ideas_select_own
  ON public.ideas
  FOR SELECT
  TO authenticated
  USING ((SELECT auth.uid()) = user_id);

CREATE POLICY ideas_insert_own_session_draft
  ON public.ideas
  FOR INSERT
  TO authenticated
  WITH CHECK (
    (SELECT auth.uid()) = user_id
    AND status = 'submitted'
    AND EXISTS (
      SELECT 1
      FROM public.idea_sessions AS session
      WHERE session.id = session_id
        AND session.user_id = (SELECT auth.uid())
        AND session.status = 'in_progress'
    )
  );

CREATE POLICY ideas_update_own
  ON public.ideas
  FOR UPDATE
  TO authenticated
  USING ((SELECT auth.uid()) = user_id)
  WITH CHECK (
    (SELECT auth.uid()) = user_id
    AND status IN ('submitted', 'archived')
    AND EXISTS (
      SELECT 1
      FROM public.idea_sessions AS session
      WHERE session.id = session_id
        AND session.user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY ideas_delete_own
  ON public.ideas
  FOR DELETE
  TO authenticated
  USING (
    (SELECT auth.uid()) = user_id
    AND EXISTS (
      SELECT 1
      FROM public.idea_sessions AS session
      WHERE session.id = session_id
        AND session.user_id = (SELECT auth.uid())
    )
  );
