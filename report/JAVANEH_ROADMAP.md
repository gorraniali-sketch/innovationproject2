# Javaneh Social Innovation Platform
## Incremental Product & Engineering Roadmap

**Document purpose:** This roadmap defines how to continue the existing Javaneh repository and evolve it toward the AI-mentored social innovation platform described in the product specification. It is intended to live in the project source repository as the implementation reference for developers and AI coding agents.

**Delivery approach:** Incremental extension of the existing application. This is not a greenfield rebuild.

---

## 1. Mission and Target Product

Javaneh is a human-centered social innovation platform where individuals and groups identify social problems, understand their context and capacities, develop their own ideas through a structured process, and submit those ideas for human evaluation.

AI acts as a mentor. It helps participants think more clearly through guided questions, conceptual explanations, critical reflection, identification of assumptions, and organization of information. It must not take ownership of the creative process, decide what the participant should think, or generate and impose the participant's final idea.

The target platform brings together:

1. Existing account authentication and participant access.
2. A persistent, progressive idea-development journey.
3. AI-assisted mentorship, with resilient non-AI continuation.
4. Configurable classification into six thematic axes.
5. Participant, expert, and administrator workspaces.
6. Human-led evaluation and decision-making.
7. Secure data management, observability, and operational resilience.

## 2. Non-Negotiable Continuation Rules

These rules govern every implementation phase.

### 2.1 Continue from the existing repository

The current application is the starting point. Do not replace it with a new application, create a parallel frontend, or introduce a second authentication system.

The repository audit identifies the current stack as:

- Next.js App Router
- TypeScript
- React
- Tailwind CSS
- Supabase Auth
- Supabase PostgreSQL
- Supabase SSR clients and existing server actions
- Existing SQL migrations and RLS tests

Keep these technologies unless a demonstrated technical requirement justifies a documented change.

### 2.2 Preserve completed account and authentication work

The existing public landing page and account-authentication flow are established project components. They are not the subject of this roadmap's redesign.

**Do not rebuild, replace, or unnecessarily restyle:**

- The public landing page.
- Individual account sign-up.
- Sign-in and sign-out.
- Email confirmation and callback handling.
- Password reset and password update.
- Existing Supabase Auth configuration and session handling.

Relevant existing locations include:

- `src/app/page.tsx`
- `src/app/auth/`
- `src/app/auth/actions.ts`
- `src/app/auth/callback/`
- `src/lib/supabase/`
- `src/proxy.ts`

Only make changes to these areas when a new feature has a concrete integration requirement, a security issue is verified, or a regression must be fixed. Such changes must be narrowly scoped and must preserve existing behavior.

**Important distinction:** Account registration/authentication is not the same thing as the seven-stage idea-development journey. Do not interpret the product's seven-stage process as permission to rebuild the existing account-registration screens.

### 2.3 Preserve existing work before extending it

The repository audit reports that the current idea wizard has three UI steps and stores answers in React state, while the database already contains `idea_sessions` and `ideas` tables with ownership policies. Treat this as the verified baseline from the audit, but inspect the current branch before each implementation task.

Do not assume that a feature is complete merely because a table, route, component, or document exists. Verify whether it is connected and operational.

### 2.4 Make database changes additive and safe

- Do not casually edit or rewrite migrations that have already been applied.
- Prefer new, clearly named migrations.
- Preserve existing user and idea data.
- Introduce compatibility or backfill logic where required.
- Keep RLS enabled and test every new access path.
- Do not expose Supabase service-role credentials in client code.
- Do not weaken existing ownership policies to make a feature work.

### 2.5 Avoid unnecessary architectural expansion

Continue using the existing Next.js server-side patterns and Supabase integration. Introduce service modules and route handlers where they make business logic clearer, but do not create a separate backend application or a parallel API architecture without a documented need.

Avoid adding dependencies until the requirement and the existing platform's capabilities have been checked.

### 2.6 Human agency is a product requirement

AI may support reflection, ask questions, explain concepts, identify gaps, and organize participant-provided information. It must not:

- Choose an idea for a participant.
- Present its own generated solution as the participant's idea.
- silently rewrite a participant's meaning.
- submit or confirm a stage on the participant's behalf.
- make final evaluation or selection decisions.
- conceal uncertainty or present unsupported claims as facts.

Participants must review and explicitly confirm information before it becomes a confirmed stage or final dossier content.

---

## 3. Existing Repository Baseline

The latest supplied technical audit describes the repository as an early-stage prototype with a working authentication scaffold and an incomplete idea-management workflow.

### 3.1 Components to retain

| Existing component | Audit status | Roadmap treatment |
|---|---|---|
| Public landing page | Implemented | Preserve |
| Email/password sign-up | Implemented | Preserve |
| Sign-in and sign-out | Implemented | Preserve |
| Email confirmation and callback | Implemented | Preserve |
| Password reset/update | Implemented | Preserve |
| Supabase SSR session handling | Implemented | Preserve |
| Three-step idea wizard UI | Implemented, client-state only | Extend; do not discard without a migration plan |
| `idea_sessions` table | Implemented in SQL, not wired to wizard | Integrate and evolve safely |
| `ideas` table | Implemented in SQL, not wired to wizard | Integrate and evolve safely |
| Ownership RLS policies | Present in migrations | Preserve and extend |
| Auth validation tests | Present | Retain and expand |
| Database RLS tests | Present | Retain and expand |

### 3.2 Main verified gaps

The audit reports that the current application does not yet provide:

- Durable idea drafts or a connected idea-submission flow.
- Seven-stage progress persistence.
- Version history.
- AI provider integration or AI mentor orchestration.
- AI availability detection and fallback control.
- Formal six-axis classification.
- Group membership and group-based idea ownership.
- Expert roles, assignments, or evaluation workflows.
- An administrator role or dashboard.
- File/object storage workflows.
- End-to-end tests for the idea journey.
- A production deployment and CI/CD configuration.

These are the principal areas of new development.

### 3.3 Existing files that should be inspected before implementation

Start with the actual current contents of:

1. `src/app/ideas/new/idea-wizard.tsx`
2. `src/app/ideas/new/page.tsx`
3. `src/lib/supabase/server.ts`
4. `src/lib/supabase/client.ts`
5. `src/lib/supabase/env.ts`
6. `src/app/auth/actions.ts` (for integration awareness only; do not rebuild auth)
7. `supabase/migrations/20261024090000_initial_idea_schema.sql`
8. `supabase/migrations/20261024090800_revoke_service_role_idea_access.sql`
9. `supabase/tests/database/idea_rls_test.sql`
10. `README.md` and `package.json`

The audit is a snapshot, not a substitute for inspecting the current branch. If the code has changed since the audit, the repository takes precedence and this roadmap must be updated accordingly.

---

## 4. Target Participant Journey

The target idea-development journey contains seven stages:

| Stage | Name | Intended outcome |
|---|---|---|
| 1 | Define the Problem | A clear, participant-owned description of the social problem |
| 2 | Identify Social Capacities | An account of relevant people, assets, relationships, capabilities, and local resources |
| 3 | Develop and Expand Ideas | A set of explored directions and a participant-selected concept |
| 4 | Design the Implementation Plan | A structured explanation of how the idea could be put into practice |
| 5 | Initial Feasibility and Resilience Check | An initial examination of feasibility, risks, constraints, and resilience |
| 6 | Prepare the Idea Dossier | A coherent, participant-reviewed proposal assembled from confirmed work |
| 7 | Human Review and Judging | Expert review and authorized human decision-making |

### 4.1 Do not confuse journey stages with account registration

The existing account sign-up and authentication flow remains intact.

The product specification groups Stages 1 and 2 within an initial registration process. This roadmap preserves that conceptual boundary while avoiding a rebuild of the existing website account-registration experience.

Implementation must first map the current wizard fields and screens to the target journey. Reuse existing inputs and UI where they are suitable. Add only the missing fields, interactions, and stage boundaries. Do not create duplicate forms simply because the target model uses seven stages.

### 4.2 Stage gating

- A participant can work on the currently available stage.
- A stage is not complete merely because its fields have been opened or populated.
- The participant reviews and explicitly confirms the stage.
- A confirmed stage is persisted before the next stage is unlocked.
- A participant can revisit earlier stages according to the product's editing rules.
- Editing confirmed content creates a new version or revision record rather than silently destroying the previous confirmed state.
- The platform clearly distinguishes draft, pending synchronization, confirmed, submitted, and returned-for-revision states where applicable.

### 4.3 Classification boundary

After the initial registration process represented by Stages 1 and 2 has been completed and confirmed, the platform should classify the idea into one of six thematic axes.

The six official axis names, definitions, and criteria have not been supplied in the source specification. Keep them configurable and inactive as formal categories until the product owner provides the authoritative taxonomy. Do not invent their names.

---

## 5. Implementation Roadmap

The phases below are ordered by dependency. A phase is complete only when its acceptance criteria pass.

## Phase 0 — Repository Verification and Change Protection

**Objective:** Establish the exact current state and protect completed work before extending the platform.

### Tasks

- Inspect the current branch, working tree, and recent commits.
- Review the existing wizard, database migrations, RLS policies, Supabase helpers, and tests.
- Run the existing lint, test, type-check, and production build commands.
- Record any differences between the supplied audit and the current repository.
- Identify which existing wizard fields map to Stages 1 and 2 and which, if any, already represent later-stage content.
- Identify whether any persistence work has been added since the audit.
- Create a concise baseline note in the repository documenting verified behavior and known gaps.

### Constraints

- Do not change the account-registration or authentication flow.
- Do not perform broad refactoring during baseline verification.
- Do not modify production data or apply schema changes during inspection.

### Acceptance criteria

- The current repository state is documented.
- Existing checks have a recorded baseline result.
- Existing authentication behavior is verified and protected by regression checks.
- A field-to-stage mapping for the current idea wizard is documented.
- No existing feature has been replaced or removed.

**Deliverable:** A verified implementation baseline and a safe change plan.

---

## Phase 1 — Connect the Existing Idea Wizard to Durable Persistence

**Objective:** Turn the existing in-memory wizard into a reliable draft and submission workflow without redesigning the account-registration experience.

This is the first major implementation phase because all later capabilities depend on trustworthy idea data.

### Tasks

1. Define a typed application-level representation of the current idea draft.
2. Connect the existing wizard to the current `idea_sessions` table.
3. Load the authenticated participant's existing in-progress session when appropriate.
4. Save draft changes through server-verified Supabase operations.
5. Persist the current step and validated draft payload.
6. Restore the draft after refresh, navigation, or a later sign-in.
7. Connect final submission to the existing `ideas` table, preserving its ownership and integrity constraints.
8. Prevent duplicate submissions and conflicting session/idea states.
9. Provide clear save status and actionable error messages.
10. Preserve the existing wizard's usable UI and field semantics unless a specific change is required for persistence.

### Data and behavior requirements

- The authenticated user's identity must be derived and verified server-side.
- Never trust a client-supplied `user_id` as the authorization boundary.
- Validate all submitted fields on the server.
- Keep the existing RLS ownership model.
- Treat the database as the authoritative source for successfully saved drafts.
- Make submission operations safe against retries.
- Do not mark a session submitted until the final idea record is successfully created.
- Ensure the UI does not report a save as successful before the server confirms it.

### Acceptance criteria

- A participant can start an idea and save a draft.
- Refreshing or reopening the application does not erase a successfully saved draft.
- A participant cannot read or modify another participant's draft.
- Final submission creates one valid idea record.
- Repeated submission attempts do not create duplicate ideas.
- Existing authentication flows continue to work unchanged.

**Deliverable:** A working, database-connected idea workflow using the existing schema as its starting point.

---

## Phase 2 — Establish the Seven-Stage Domain and Progress Model

**Objective:** Evolve the current three-step wizard into the seven-stage idea-development journey while reusing existing screens and data wherever possible.

### Tasks

- Define a canonical stage model in TypeScript and PostgreSQL.
- Map the existing wizard fields to the appropriate target stages.
- Identify genuinely missing information for each stage.
- Extend the UI progressively instead of replacing the entire wizard at once.
- Implement stage status, completion requirements, and explicit participant confirmation.
- Persist the active stage and completed-stage status.
- Add server-side rules preventing access to stages that have not been unlocked.
- Support returning to previously completed stages under defined editing rules.
- Add a participant-facing progress tracker.
- Ensure stage transitions are transactional or otherwise recoverable.

### Suggested stage states

Use a small, explicit state model. The final names may be adjusted during schema design, but the meanings must remain distinct:

- `not_started`
- `in_progress`
- `pending_confirmation`
- `confirmed`
- `needs_revision`
- `locked`

Do not rely only on a client-side step number to determine whether a participant has completed a stage.

### Schema evolution

The existing `idea_sessions.current_step` constraint is limited to steps 1–3 according to the audit. Do not simply change application code to write values 1–7 while leaving the database constraint unchanged.

Use a new migration to introduce the seven-stage model. A normalized stage table is preferable when it provides clearer status, timestamps, validation, and version relationships. Preserve compatibility with existing `idea_sessions` and `ideas` records through a deliberate mapping or backfill plan.

The final schema design must avoid two competing sources of truth for stage progress.

### Acceptance criteria

- The participant journey exposes all seven stages in the intended order.
- Existing information is mapped and retained.
- A confirmed stage is durably stored.
- The next stage is unlocked only after the required confirmation.
- Progress is restored correctly after a new session.
- Editing a confirmed stage does not silently erase its previous confirmed version.
- Existing records remain valid after migrations.

**Deliverable:** A persistent seven-stage idea-development workflow.

---

## Phase 3 — Data Resilience, Autosave, and Version History

**Objective:** Prevent loss of participant work during network interruptions, browser closure, or failed requests.

### Tasks

- Implement debounced autosave for editable draft content.
- Preserve unsynchronized edits locally when the network is unavailable.
- Use a clear synchronization queue or equivalent controlled mechanism.
- Display the state of each draft: saved, pending sync, or failed.
- Retry transient failures with bounded backoff.
- Make synchronization idempotent.
- Detect stale writes and avoid overwriting newer confirmed data.
- Add version records for confirmed revisions.
- Record who made a change and when.
- Provide a safe recovery path when local and server versions conflict.
- Clear local sensitive draft data after confirmed synchronization or sign-out according to the application's privacy policy.

### Required data lifecycle

`Participant Input → Local Draft Preservation → Backend Validation → Database Transaction → Save Confirmation → Next Stage Unlock`

The UI must distinguish local preservation from server-confirmed persistence. A locally cached value must never be presented as a database-confirmed save.

### Acceptance criteria

- A temporary internet interruption does not immediately destroy unsaved work.
- Pending changes are synchronized when connectivity returns.
- Failed synchronization is visible and recoverable.
- Repeated retries do not create duplicate versions or submissions.
- Confirmed revisions can be inspected and restored according to authorization rules.
- Participants can understand whether their work is saved or still pending.

**Deliverable:** A resilient draft and revision system.

---

## Phase 4 — AI Mentor Foundation and Provider Integration

**Objective:** Introduce AI mentorship as a controlled backend capability without making the application dependent on AI availability.

### Tasks

1. Select and document the AI provider and model configuration.
2. Store provider credentials only in server-side environment variables.
3. Create a backend-only AI integration module.
4. Add a mentor orchestration layer that receives the participant's current stage and approved context.
5. Define versioned system prompts and stage-specific mentor instructions.
6. Define structured request and response schemas.
7. Validate model output before returning it to the frontend.
8. Add request timeouts, bounded retries, rate limits, and token/cost controls.
9. Record operational metadata without unnecessarily storing sensitive prompt content.
10. Add tests for valid, malformed, delayed, unavailable, and rate-limited provider responses.

### AI mentor behavior

The mentor should:

- Ask open and relevant questions.
- Help clarify the participant's own statements.
- Explain concepts when needed.
- Identify assumptions and missing information.
- Encourage consideration of affected people and context.
- Help organize participant-provided material.
- Point out contradictions respectfully.
- Make uncertainty explicit.

The mentor must not:

- Select the final idea.
- invent facts about a community or its needs.
- silently replace participant-authored content.
- claim that an idea is feasible without evidence.
- confirm stages or submit a dossier.
- make expert or administrative decisions.

### Context management

Send only the context needed for the current interaction, such as:

- Current stage and its purpose.
- Participant-confirmed information from relevant earlier stages.
- The current participant message.
- Relevant conversation history, subject to a defined context limit.

Do not send the entire account record or unrelated personal data to the model.

### Acceptance criteria

- All AI requests pass through trusted server-side code.
- No provider key is exposed to the browser.
- Responses are schema-validated before use.
- AI behavior follows the human-agency rules.
- AI failures do not corrupt participant data.
- AI calls are logged with useful operational metadata and controlled cost.

**Deliverable:** A secure, testable AI mentor service.

---

## Phase 5 — AI Availability, Circuit Breaker, and Non-AI Continuation

**Objective:** Ensure that AI outages do not make the platform unusable.

### Scope clarification

The product specification describes static forms as a fallback for AI-powered conversational registration. This does not authorize rebuilding the existing account-registration pages. The existing sign-up, sign-in, email confirmation, and password flows remain unchanged.

For the idea journey, implement fallback behavior according to the stage and interaction type. Do not silently convert every later-stage workflow into a registration form.

### Tasks

- Add an AI health/availability check on the backend.
- Implement a circuit breaker with defined closed, open, and half-open states.
- Detect timeouts, provider errors, rate limits, and repeated failures.
- Switch the relevant AI-assisted interaction to a non-AI path when necessary.
- Provide static structured prompts, guidance text, or stage forms where appropriate.
- Keep all participant input connected to the same validation and persistence rules.
- Allow a participant to save and resume if a stage cannot reasonably continue without AI.
- Retry AI recovery in a controlled way.
- Restore AI mode when the provider is healthy, without losing the participant's work.
- Display clearly whether the participant is using AI-assisted or non-AI mode.

### Required behavior

- Static/non-AI mode must not require an AI API connection.
- Both modes must use the same trusted backend validation and persistence rules.
- Fallback must never bypass authorization or stage-confirmation rules.
- AI recovery must not duplicate messages, stages, or submissions.
- The participant must not lose work when the system changes modes.

### Acceptance criteria

- Simulated provider outage activates the intended fallback.
- The participant can continue or safely save and resume.
- The fallback path stores data correctly.
- Recovery returns the service to AI mode without data loss.
- The circuit breaker prevents repeated calls to a failing provider.
- Mode changes are observable by administrators.

**Deliverable:** An AI-assisted platform with graceful non-AI operation.

---

## Phase 6 — Six-Axis Thematic Classification

**Objective:** Classify an idea into one of six official thematic axes after the initial two-stage process has been completed and confirmed.

### Prerequisite

The six official thematic axes have not been named or defined in the supplied product specification. Do not invent the taxonomy.

Before enabling production classification, obtain:

- Official axis names.
- Definitions and boundaries.
- Inclusion and exclusion criteria.
- Representative examples.
- Rules for ambiguous or cross-cutting ideas.
- Whether one primary axis or multiple axes may be assigned.

### Tasks after the taxonomy is approved

- Create a configurable `thematic_axes` table.
- Store official names, descriptions, active status, and taxonomy version.
- Implement a backend classification service.
- Provide the classifier only with the confirmed information needed for classification.
- Require structured output containing the selected axis, rationale, and confidence where supported.
- Validate every returned axis against the active taxonomy.
- Store the classification result and taxonomy version.
- Support manual administrator correction.
- Preserve classification history.
- Define a review path for low-confidence or ambiguous cases.

### Acceptance criteria

- No unapproved or invented axis can be stored.
- Classification occurs only at the intended journey boundary.
- The classification result is traceable to a taxonomy version.
- Administrators can correct an assignment.
- Reclassification does not erase previous decisions.
- Uncertain classifications can be flagged for human review.

**Deliverable:** A configurable, auditable six-axis classification system.

---

## Phase 7 — Participant Dashboard and Idea Workspace

**Objective:** Give participants a clear place to manage their ideas and understand their progress.

### Tasks

Build on the existing authenticated application shell. Do not create a separate participant account system.

The participant workspace should include:

- Profile summary using existing authenticated identity.
- Idea overview.
- Seven-stage progress tracker.
- Current stage and next required action.
- Completed and locked stages.
- Draft and synchronization status.
- AI mentor interaction where available.
- Non-AI continuation when required.
- Confirmed version history.
- Idea dossier preview.
- Submission status.
- Evaluation status and permitted feedback.
- Relevant notifications.

### UX requirements

A participant should always be able to tell:

1. Which stage they are working on.
2. What they have completed.
3. What remains.
4. Which information has been saved.
5. Whether AI or non-AI mode is active.
6. What action is required next.

### Acceptance criteria

- Dashboard data comes from authorized server-side queries.
- A participant sees only ideas they are permitted to access.
- Progress and save states match the database.
- Navigation respects stage access rules.
- The existing brand and Persian RTL experience are preserved.

**Deliverable:** A functional participant workspace.

---

## Phase 8 — Groups and Collective Participation

**Objective:** Support group participation without introducing organizations as a separate registration type.

### Product rules

There are two participant registration types:

- Individual.
- Group.

A group is represented by a designated representative who manages the group's interaction with the platform. An organization may be recorded as an affiliation or identity attribute, but it is not a third registration type.

### Tasks

- Add group records and group-member relationships.
- Associate one designated representative with each group.
- Define membership roles and membership status.
- Define how a group owns or is associated with an idea.
- Define who can edit, confirm, and submit group work.
- Enforce group-level authorization in server logic and RLS.
- Preserve an audit trail of membership and representative changes.
- Define how invited members authenticate using the existing account system.

### Acceptance criteria

- An individual can continue to create and own an individual idea.
- A group can be associated with an idea through a clear ownership model.
- The designated representative can perform permitted group actions.
- Non-members cannot access group-private data.
- Membership changes are auditable.
- No separate organization registration type is introduced.

**Deliverable:** Secure individual and group participation.

---

## Phase 9 — Expert Roles and Human Evaluation

**Objective:** Implement the human review and judging process. AI must not replace this process.

### Tasks

- Introduce server-enforced roles for participants, experts, and administrators.
- Create review assignments linking authorized experts to submitted ideas.
- Define evaluation criteria and scoring ranges with the product owner.
- Build an expert dashboard for assigned ideas.
- Provide a structured dossier viewer.
- Allow experts to submit scores, comments, and recommendations.
- Track pending, in-progress, submitted, and completed reviews.
- Support multiple reviewers if required.
- Provide an authorized process for consolidating evaluation results.
- Record final decisions as human decisions with traceable actors and timestamps.
- Define conflict-of-interest and reassignment procedures if required by the operating model.

### Important controls

- Role checks must happen on the server and in database policies where applicable.
- Hiding a button in the UI is not authorization.
- Experts must not access unassigned ideas unless explicitly authorized.
- Participants must not modify submitted expert evaluations.
- AI may assist with organizing information but cannot assign final scores or select winners.

### Acceptance criteria

- Only authorized experts can access their assigned reviews.
- Evaluations are stored with reviewer identity and timestamps.
- Review status is visible to authorized users.
- Final decisions are attributable to authorized human decision-makers.
- RLS and server-side tests cover every evaluation access path.

**Deliverable:** A complete human-led evaluation workflow.

---

## Phase 10 — Administrative Control Center

**Objective:** Provide authorized administrators with operational and business control over the platform.

### Modules

1. **Platform Overview**
   - Participant and idea counts.
   - Stage completion overview.
   - Submission and evaluation status.
   - Operational alerts.

2. **Participant Management**
   - Participant search and profile inspection.
   - Account status and role management.
   - Individual/group relationships.

3. **Idea Management**
   - Idea search and filtering.
   - Stage and submission status.
   - Authorized inspection and moderation actions.
   - Version and change history.

4. **Six-Axis Classification Management**
   - Taxonomy configuration.
   - Classification inspection and correction.
   - Uncertain classification queue.

5. **AI Service Monitoring**
   - Provider availability.
   - Request success/failure rates.
   - Latency and rate-limit events.
   - Token/cost metrics where available.
   - Circuit-breaker state.

6. **Fallback Management**
   - Current fallback status.
   - Static/non-AI guidance configuration where appropriate.
   - Fallback and recovery event history.

7. **Expert and Evaluation Management**
   - Expert records and permissions.
   - Review assignment.
   - Evaluation progress.
   - Decision history.

8. **Technical System Health**
   - Application errors.
   - Database and storage health indicators.
   - Background task status if introduced.
   - Synchronization failures.

9. **Security and Audit Logs**
   - Role and permission changes.
   - Administrative actions.
   - Sensitive data access events where appropriate.
   - Authentication/security events.

10. **Global Configuration**
    - Feature flags.
    - Approved taxonomy configuration.
    - AI model/provider settings that can safely be managed at runtime.
    - Operational thresholds.

### Acceptance criteria

- The admin area is protected by server-side role checks.
- Administrative actions are audited.
- Sensitive secrets are never displayed.
- Dashboard metrics are derived from reliable data.
- Admin access does not depend solely on client-side navigation restrictions.

**Deliverable:** A secure administrative control center.

---

## Phase 11 — File Storage and Idea Dossier

**Objective:** Support a durable, reviewable dossier and any approved supporting attachments.

### Tasks

- Define the dossier's canonical structure and required sections.
- Generate the dossier from confirmed stage data, not unconfirmed draft text.
- Let the participant review and confirm the dossier before submission.
- Store generated files in Supabase Storage when file output is required.
- Define private buckets and signed/authorized access.
- Validate file type, size, and ownership for uploads.
- Store file metadata and relationships in PostgreSQL.
- Preserve dossier versions.
- Ensure experts can access only dossiers associated with their authorized assignments.

### Acceptance criteria

- Dossier content is traceable to confirmed stage versions.
- A participant can review the dossier before submission.
- Private files are not publicly accessible by default.
- File access is authorized and auditable.
- Regenerating a dossier does not silently overwrite a previously submitted version.

**Deliverable:** A participant-confirmed, versioned idea dossier.

---

## Phase 12 — Security, Quality, Observability, and Production Readiness

**Objective:** Make the expanded platform reliable and maintainable.

### Security

- Review all authenticated routes and private operations.
- Enforce role and ownership checks server-side.
- Extend RLS policies and database tests.
- Validate all client input on the server.
- Protect AI endpoints against abuse and excessive usage.
- Apply rate limits to sensitive operations.
- Keep secrets server-side.
- Review logging to prevent accidental exposure of personal data or credentials.
- Audit storage policies and signed URL lifetimes.
- Test cross-user and cross-role access denial.

### Testing

Maintain and extend the existing test foundation.

Required coverage:

- Existing authentication regression tests.
- Draft creation, save, load, and resume.
- Stage validation and stage unlocking.
- Version creation and restoration.
- Duplicate submission protection.
- RLS ownership and group membership.
- Expert assignment and evaluation permissions.
- AI response validation.
- AI timeout, rate-limit, and provider outage behavior.
- Circuit-breaker and fallback transitions.
- Classification validation.
- Dossier generation and access control.
- End-to-end participant journey.

### Observability

Introduce structured operational logging and monitoring for:

- Application errors.
- Database operation failures.
- Draft synchronization failures.
- AI provider requests and failures.
- Fallback activations and recoveries.
- Classification errors.
- Evaluation workflow events.
- Administrative/security events.

Avoid logging unnecessary participant content. Define retention and access policies for operational logs.

### Performance

Optimize based on measurements, not assumptions.

- Avoid unnecessary client-side JavaScript.
- Keep database queries scoped and indexed.
- Paginate administrative lists.
- Avoid repeated AI calls for unchanged inputs.
- Use bounded context windows.
- Cache only data that is safe and useful to cache.
- Measure page performance, API latency, database latency, and AI costs.
- Add background processing only when an actual workload requires it.

### Deployment and operations

- Select and document the production hosting configuration.
- Define environment variables and secret management.
- Configure separate development, staging, and production environments.
- Add CI checks for lint, type checking, tests, and build.
- Define a safe database migration procedure.
- Establish backup and restore expectations.
- Document rollback and incident-response procedures.

### Acceptance criteria

- Critical participant and administrative flows have automated tests.
- Authorization boundaries are tested at both application and database levels.
- Monitoring can identify failures in persistence, AI, and fallback behavior.
- Production secrets are not committed to source control.
- Migrations can be applied and verified safely.
- A documented deployment and recovery process exists.

**Deliverable:** A tested, observable, and deployable platform.

---

## 6. Proposed Data Model Evolution

The current database contains `idea_sessions` and `ideas`. These are useful starting points, but the target platform requires additional entities.

The following is a conceptual target model, not permission to create every table immediately. Implement entities in the phase where they become necessary. Final columns, constraints, and cardinalities must be designed against the actual migrations and business rules.

| Entity | Purpose | Introduced in |
|---|---|---|
| `profiles` | Application profile, role, and participant metadata linked to Supabase Auth | Roles/workspace phase |
| `groups` | Collective participant identity and representative | Phase 8 |
| `group_members` | Membership and group-level permissions | Phase 8 |
| `ideas` | Main idea record and ownership relationship | Phase 1 onward |
| `idea_sessions` | Draft/session state, retained and evolved safely | Phase 1 |
| `idea_stages` | Seven-stage status and confirmed stage state | Phase 2 |
| `idea_versions` | Immutable or append-only confirmed revisions | Phase 3 |
| `conversations` | AI mentor conversation/session metadata | Phase 4 |
| `conversation_messages` | Participant and mentor messages | Phase 4 |
| `thematic_axes` | Configurable official six-axis taxonomy | Phase 6 |
| `idea_classifications` | Classification result, confidence, rationale, and taxonomy version | Phase 6 |
| `review_assignments` | Assignment of ideas to experts | Phase 9 |
| `evaluations` | Expert scores, comments, and review outcomes | Phase 9 |
| `dossiers` | Generated and participant-confirmed dossier versions | Phase 11 |
| `stored_files` | Metadata for private storage objects | Phase 11 |
| `audit_logs` | Traceable administrative and security-sensitive events | Phases 8–12 |

### 6.1 Core relationship model

At a conceptual level:

`Profiles / Groups → Ideas → Idea Stages → Idea Versions`

Supporting relationships:

- An idea may belong to an individual profile or a group, according to an explicit ownership model.
- An idea has seven stage records or an equivalent normalized representation.
- A stage may have multiple versions.
- An idea may have conversations associated with relevant stages.
- An idea may have a classification history.
- An idea may have one or more review assignments.
- Review assignments may produce evaluations.
- A dossier is generated from confirmed idea and stage data.
- Audit records reference the actor and the relevant operation.

### 6.2 Data model rules

- Do not permanently assume one user can own only one idea.
- Do not encode group participation as a separate organization registration type.
- Keep authentication identity separate from application roles and participant type.
- Use foreign keys and constraints to protect relationships.
- Use explicit status values and timestamps.
- Preserve historical decisions and confirmed revisions.
- Add indexes based on actual query patterns.
- Apply RLS to every private table.
- Do not rely on obscured IDs or UI filtering as access control.

---

## 7. Suggested Application Module Structure

The current repository uses `src/app`, `src/lib`, and `supabase`. Extend that structure incrementally rather than moving everything into a new architecture.

An illustrative future organization is:

```text
src/
  app/
    auth/                         # Existing: preserve
    ideas/
      new/                        # Existing wizard: extend
    participant/
      dashboard/
      ideas/
      stages/
    expert/
      dashboard/
      evaluations/
    admin/
      dashboard/
      participants/
      ideas/
      classification/
      ai-monitoring/
      evaluations/
      settings/
    api/
      ai/
      ideas/
      stages/
      classification/
      evaluations/
  components/
    participant/
    expert/
    admin/
    stages/
    mentor/
    shared/
  lib/
    supabase/                     # Existing helpers: preserve and extend
    ideas/
    stages/
    persistence/
    ai/
      providers/
      mentor/
      classification/
      resilience/
    authorization/
    evaluations/
    dossiers/
    monitoring/
  types/
    database/
    domain/
supabase/
  migrations/
  tests/
tests/
  unit/
  integration/
  e2e/
```

This is a target organizational guide, not a requirement to create empty folders immediately. Create modules when their implementation begins. Keep existing file paths working unless a deliberate, tested refactor is approved.

---

## 8. API and Server-Side Design Principles

The current project uses Next.js server actions and route handlers. Continue this pattern where appropriate.

New operations should be organized around domain responsibilities, for example:

- Idea draft creation and retrieval.
- Draft updates and final submission.
- Stage validation and confirmation.
- Version retrieval and restoration.
- AI mentor interaction.
- AI health and fallback status.
- Thematic classification.
- Group membership and ownership.
- Expert assignment and evaluation.
- Dossier generation and retrieval.
- Administrative operations.

For every operation:

1. Authenticate the caller server-side.
2. Authorize the action against the relevant record and role.
3. Validate input with a shared schema.
4. Execute the operation using the server-side Supabase client.
5. Rely on RLS as an additional database boundary.
6. Return a predictable, typed result.
7. Log operational failures without leaking sensitive data.
8. Make retryable writes idempotent where possible.

Do not create public endpoints for internal AI provider credentials or privileged database operations.

---

## 9. Delivery Order and Dependency Map

The recommended implementation sequence is:

```text
Phase 0: Verify repository and protect existing work
        |
        v
Phase 1: Persist the existing idea wizard
        |
        v
Phase 2: Seven-stage domain and progress model
        |
        v
Phase 3: Autosave, offline resilience, and version history
        |
        +------------------------------+
        |                              |
        v                              v
Phase 4: AI mentor foundation     Phase 6: Taxonomy preparation
        |                              |
        v                              |
Phase 5: AI fallback and recovery      |
        |                              |
        +---------------+--------------+
                        |
                        v
Phase 7: Participant workspace
                        |
                        v
Phase 8: Group participation
                        |
                        v
Phase 9: Expert evaluation
                        |
                        v
Phase 10: Administrative control center
                        |
                        v
Phase 11: Dossier and file storage
                        |
                        v
Phase 12: Production hardening and operations
```

Some work can proceed in parallel after its prerequisites are met. For example, taxonomy requirements can be gathered while persistence is being implemented, but production classification must wait for approved axis definitions.

---

## 10. Definition of Done

A feature is not complete merely because its UI renders.

Every feature must satisfy the relevant items below:

- [ ] The requirement and user-facing behavior are documented.
- [ ] Existing functionality that must remain unchanged has been identified.
- [ ] The current implementation has been inspected before editing.
- [ ] Data structures and migrations are reviewed.
- [ ] Server-side authentication and authorization are enforced.
- [ ] Input validation is performed on the server.
- [ ] RLS and database constraints are appropriate.
- [ ] Loading, empty, success, and error states are handled.
- [ ] Network failure and retry behavior are considered.
- [ ] Sensitive data and secrets are protected.
- [ ] Relevant unit, integration, database, or end-to-end tests pass.
- [ ] Lint, type checking, and production build pass.
- [ ] Documentation is updated.
- [ ] No unrelated existing feature has been redesigned or removed.

---

## 11. Working Protocol for AI Coding Agents

Any AI coding agent or developer continuing this repository must follow these instructions.

### Before making a change

1. Read this roadmap.
2. Inspect the relevant existing files and current Git state.
3. Trace the existing behavior from UI to server action/service to database.
4. Check whether a similar helper, type, table, or component already exists.
5. Identify the smallest change that satisfies the task.
6. State which files and migrations are expected to change.

### While implementing

- Work incrementally.
- Preserve existing authentication and registration behavior.
- Reuse existing Supabase clients and validation helpers.
- Keep privileged operations on the server.
- Add migrations rather than rewriting applied migrations.
- Do not fabricate the six thematic axes.
- Do not add a second authentication mechanism.
- Do not let AI make participant or evaluator decisions.
- Do not silently discard participant data.
- Do not add unrelated UI redesigns or dependencies.

### After implementing

1. Review the diff for unrelated changes.
2. Run relevant tests, lint, type checking, and build.
3. Test authorization and data ownership.
4. Verify that existing sign-up, sign-in, confirmation, and password recovery still work if shared code was touched.
5. Summarize the files changed, migrations added, behavior implemented, and checks performed.
6. Identify remaining gaps honestly.

### Change-control rule

If a requested implementation appears to require changing a protected existing component, first explain why the change is necessary and propose the smallest safe modification. Do not silently rebuild the component.

---

## 12. Immediate Next Development Task

**Start with Phase 0, then implement Phase 1.**

The next coding task is not to redesign registration, add an AI chatbot, or build the admin dashboard. It is to connect the existing idea wizard to the database already prepared for it.

The first implementation cycle should:

1. Inspect the current wizard and the existing `idea_sessions` and `ideas` migrations.
2. Confirm the exact mapping between current form fields and the current database schema.
3. Implement secure draft creation, retrieval, and saving.
4. Restore saved drafts when the participant returns.
5. Implement a safe final submission path.
6. Add tests for ownership, persistence, and duplicate prevention.
7. Verify that the existing account-authentication flow remains unchanged.

Once this foundation works, the seven-stage model, version history, AI mentorship, classification, dashboards, and evaluation can be introduced without building on fragile in-memory state.

---

## 13. Product Decisions Still Required

The following items are intentionally left open because the supplied specifications do not define them sufficiently. They must be resolved before the corresponding feature is finalized.

| Decision | Needed before |
|---|---|
| Official names, definitions, and criteria of the six thematic axes | Phase 6 |
| Exact field-level content and validation rules for each of the seven stages | Phase 2 |
| Whether participants may create multiple ideas and under what limits | Phase 1/2 |
| Detailed individual/group idea ownership and editing rules | Phase 8 |
| Group invitation and membership approval process | Phase 8 |
| Expert evaluation criteria, score ranges, and weighting | Phase 9 |
| Number of reviewers and final decision procedure | Phase 9 |
| Dossier format and required attachments | Phase 11 |
| AI provider, model, budget limits, and data-retention policy | Phase 4 |
| Operational hosting, backup, and recovery requirements | Phase 12 |

Do not invent these decisions in code. Use configurable structures where appropriate and request product-owner confirmation when a decision affects data integrity or workflow behavior.

---

## 14. Final Direction

Javaneh must evolve from its current authenticated prototype into a persistent, human-centered social innovation platform through controlled, incremental development.

The project should retain its existing landing page, account-registration and authentication system, Supabase foundation, and working components. Development should first make the existing idea workflow durable, then introduce the seven-stage process, resilience, AI mentorship, classification, participant and expert workspaces, administration, and human-led evaluation.

The defining product principle remains:

**Participants own their ideas and decisions. AI supports their thinking. The platform preserves their work. Human experts evaluate proposals. Administrators oversee the system.**

Every technical decision should reinforce that model without needlessly replacing work that has already been completed.
