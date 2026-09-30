# 13 — MVP Build Plan

## Objective

Prove one complete, correct loop instead of shipping shallow versions of every future module.

## v0.1 demo definition

A user can:

1. authenticate;
2. create/select a Client with tenant isolation;
3. link/configure a client Drive folder/Shared Drive reference;
4. populate minimal Client Brain (business/brand/audience/offers/regions);
5. upload/link a meeting recording/document;
6. queue local AI processing;
7. review proposed Facts/Rules/Decisions/Insights;
8. approve knowledge into Client Brain;
9. create/generate an Opportunity;
10. convert to Pauta with Definition of Ready;
11. create Content and a Revision;
12. validate active hard rules;
13. request client approval;
14. approve exact revision in portal;
15. schedule Publication and see it in Calendar;
16. preserve audit/history across the flow.

## Build increments

### Increment 0 — Repository/quality harness
- monorepo skeleton;
- formatting/lint/typecheck;
- test harness;
- local Supabase;
- CI;
- protected acceptance-test convention.

### Increment 1 — Identity + isolation
- Workspace/User/Membership/Client;
- RLS;
- internal/client shells;
- cross-tenant acceptance tests.

### Increment 2 — Client Brain basics
- Brand/Audience/Offer/Region;
- Source/Fact/Decision/Rule/Insight;
- proposed → approved workflow;
- knowledge UI.

### Increment 3 — AI queue/worker
- durable queue contract;
- local Python worker;
- model adapter;
- job center/status;
- idempotency tests.

### Increment 4 — Meeting intelligence
- Source file reference;
- transcription adapter;
- extraction schema;
- review screen;
- promotion to knowledge.

### Increment 5 — Marketing/content core
- Initiative;
- Opportunity;
- Pauta;
- Content;
- immutable Revision;
- rule validator.

### Increment 6 — Collaboration + portal
- ApprovalRequest/Decision;
- comments/thread basics;
- Client Portal Home/My Approvals;
- revision-approval acceptance tests.

### Increment 7 — Calendar/publication
- typed calendar projection;
- Publication schedule;
- internal + portal calendar views.

### Increment 8 — Drive sync minimum
- connection/file registry;
- manual/periodic sync;
- index/re-index hooks;
- failure states.

## Deferred but domain-compatible

- ProspectAccount/ProspectAudit commercial mode can be implemented after the kernel; v0.1 may create Clients directly.
- ServicePlan/ScopeEntitlement is required before automating request scope decisions; request management itself is scheduled for v0.2.
- Signal/metrics/experiments/templates are reserved LATER extensions.

## Explicitly not in v0.1

- production social publishing;
- full analytics suite;
- autonomous news publishing;
- image/video generation;
- capacity/financial engine;
- sophisticated CRM;
- social scraping;
- fine-tuning;
- external SaaS/multi-agency billing.
