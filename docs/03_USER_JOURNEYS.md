# 03 — User Journeys

## Journey A — Prospect to active client

`ProspectAccount research → ProspectAudit/context → commercial close → convert to Client → memberships/invite → Drive linked → intake/documents → kickoff meeting → AI extraction → human validation → Marketing Genome/Client Brain → goals → initial initiatives → Ready`

### Success condition
A client can enter productive work without recreating research already collected during sales.

## Journey B — Marketing/content loop

`Signal → Opportunity → Review → Pauta → Brief completeness → Content execution → Revision → Internal review → Client approval if required → Schedule → Publication → Performance snapshots → Insight proposal → Human validation → Knowledge/Guideline → future planning`

### Important branching
- Opportunity can be dismissed/watched instead of converted.
- Pauta can create multiple Content items.
- Content can create multiple Publications.
- Publication failure does not mutate approved revision.

## Journey C — Client request

`Portal request → Triage → ServicePlan/ScopeEntitlement check → Accept / Out-of-scope / Reject → Plan → Project/Deliverable/Task → Production → Review/Approval → Done`

If out of scope: create `ChangeRequest`, do not silently add work.

## Journey D — Meeting intelligence

`Meeting/recording → Source created → transcription job → structured extraction → proposed Facts/Rules/Decisions/Insights/Tasks → human review → accepted objects enter Client Brain → downstream revalidation/event if needed`

No permanent Rule/Fact is silently created from model inference.

## Journey E — Client approval

`Notification → Portal My Approvals → open revision preview → contextual comments → approve or request changes → immutable decision logged → if changed later, new revision requires new approval according to policy`

## Journey F — AI-assisted content suggestion

`Client context + active rules + goals + relevant performance + evidence → generate Opportunity/Pauta candidates → show why/evidence/confidence → human converts candidate → brief → generation assistance → deterministic rule validation → human/approval policy → publication`

## Journey G — Local AI worker unavailable

`User requests AI job → queue persists → UI shows queued/offline → portal remains functional → worker reconnects → lease job → execute → write result atomically → realtime/status update`.

No core client operation requires the local GPU to be online.
