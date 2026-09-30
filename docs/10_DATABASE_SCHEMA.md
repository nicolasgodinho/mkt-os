# 10 — Database Schema Blueprint

This is a logical schema, not the final migration. Exact columns may evolve without changing domain semantics.

## Identity

### workspaces
`id, name, slug, status, created_at`

### users
Application profile linked to auth identity.

### workspace_memberships
`workspace_id, user_id, role, capabilities, status`

### clients
`id, workspace_id, name, slug, status, owner_id, created_at`

### client_memberships
`client_id, user_id, role, capabilities, status`

## Commercial (LATER)

### prospect_accounts
`workspace_id, name, website?, status, owner_id?, converted_client_id?`

### prospect_audits
`prospect_account_id, status, source_refs, findings_json, created_at`

Conversion preserves research provenance when creating a Client. These tables may be deferred from v0.1.

## Strategy

### goals
`client_id, title, metric_definition?, target?, period_start?, period_end?, status`

### initiatives
`client_id, kind, name, status, start_at?, end_at?, owner_id`

### audiences / offers / regions / brand_profiles
Structured client context with provenance/update history where necessary.

## Knowledge

### sources
`client_id, type, title, trust_level, uri/file_id?, occurred_at?, valid_from?, valid_until?, metadata`

### facts
`client_id, statement, status, source_id, valid_from?, valid_until?, approved_by?`

### decisions
`client_id, statement, rationale?, source_id, decided_at, owner_id`

### rules
`client_id, type, statement, scope_type, scope_id?, priority, status, effective_from?, effective_until?, supersedes_rule_id?, source_id, approved_by`

### insights
`client_id, statement, confidence?, evidence_refs, status`

### hypotheses
`client_id, statement, success_metric?, status`

### examples
`client_id, kind, object_ref, notes, status`

## Operations

### service_plans
`client_id, name, status, starts_at?, ends_at?, source_file_id?, version`

### scope_entitlements
`service_plan_id, service_type, limit_value?, limit_unit?, period?, sla_json?, revision_limit?, exceptions_json?`

### requests
`client_id, type, title, description, status, requested_date?, urgency_reason?, submitted_by, owner_id?`

### projects
`client_id, initiative_id?, name, status, owner_id, start_at?, due_at?`

### deliverables
`project_id, type, title, status, owner_id, due_at?`

### tasks
`deliverable_id?, project_id, title, status, assignee_id?, due_at?`

### change_requests
`request_id?, project_id?, description, commercial_status, status`

## Content

### opportunities
`client_id, initiative_id?, type, title, reason, status, confidence?, expires_at?, evidence_refs, score_json`

### pautas
`client_id, initiative_id?, opportunity_id?, title, status, objective, audience_refs, pillar?, angle?, message?, cta?, source_refs, ready_state`

### contents
`client_id, pauta_id, channel, format, title, status, owner_id, working_payload_json, current_revision_id?`

### content_revisions
`content_id, revision_number, payload_json, created_by, created_at, immutable_hash`

### assets
`client_id, content_id?, revision_id?, drive_file_id, type, mime_type, status, metadata`

### publications
`content_id, revision_id, channel, profile_id?, scheduled_at?, published_at?, remote_id?, remote_url?, status, metrics_sync_state`

## Collaboration

### meetings
`client_id, title, starts_at, ends_at?, participant_json, recording_file_id?, transcript_source_id?, processing_status, owner_id?`

### threads
Polymorphic target: `target_type, target_id, visibility(internal|client)`.

### comments
`thread_id, author_id, body, created_at, edited_at?`

### approval_requests
`client_id, target_type, target_version_id, status, requested_by, requested_at, due_at?`

### approval_assignments
`approval_request_id, approver_user_id, required, status`

### approval_decisions
`approval_request_id, approver_user_id, decision, comment?, decided_at`

### notifications
`user_id, type, target_ref, read_at?, action_required, created_at`

## Platform

### file_records
`workspace_id, client_id?, drive_file_id, mime_type, revision/change marker, sync_status, index_status, metadata`

### integration_connections
`workspace_id, client_id?, provider, status, scopes, credential_ref, last_success_at?, last_error?`

### jobs
See AI job contract; also supports non-AI background jobs.

### domain_events
Immutable event envelope.

### outbox_records
Transactional delivery records for downstream consumers.

### audit_logs
Critical action audit trail.

### search_documents
Normalized lexical/vector-search records pointing back to source/domain entities.

## RLS design principle

All client-owned rows carry `workspace_id` and/or resolvable `client_id`; policies use memberships/capabilities. Avoid policies that depend on user-controlled client IDs without membership verification.


## LATER intelligence/template tables (reserved, not v0.1 required)

`signals`, `metric_definitions`, `metric_observations`, `experiments`, `research_artifacts`, `brand_token_sets`, `content_templates`.

Their detailed migrations are intentionally deferred until the corresponding module ExecPlan; they must reference existing Client/Source/Initiative/Content entities rather than creating parallel client/content models.
