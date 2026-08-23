-- Master Touch OS — 001
-- Extensions and shared enumerated types.

create extension if not exists pgcrypto;
create extension if not exists pg_trgm;

create type public.organization_status as enum ('active', 'suspended', 'archived');
create type public.membership_status as enum ('active', 'invited', 'suspended', 'removed');
create type public.employment_status as enum ('active', 'on_leave', 'probation', 'terminated', 'resigned');
create type public.project_status as enum ('draft', 'active', 'on_hold', 'completed', 'cancelled', 'archived');
create type public.project_priority as enum ('low', 'medium', 'high', 'critical');
create type public.risk_level as enum ('low', 'medium', 'high', 'critical');
create type public.stage_status as enum ('not_started', 'in_progress', 'blocked', 'completed', 'skipped', 'cancelled');
create type public.workflow_definition_status as enum ('draft', 'published', 'retired');
create type public.workflow_instance_status as enum ('pending', 'in_progress', 'completed', 'cancelled');
create type public.workflow_step_status as enum ('pending', 'ready', 'in_progress', 'completed', 'skipped', 'rejected', 'cancelled');
create type public.assignee_type as enum ('user', 'role', 'department', 'project_manager', 'unassigned');
create type public.approval_request_status as enum ('pending', 'in_progress', 'completed', 'cancelled');
create type public.approval_decision as enum ('pending', 'approved', 'approved_as_noted', 'resubmit', 'rejected', 'for_information');
create type public.approval_mode as enum ('sequential', 'parallel');
create type public.approver_type as enum ('user', 'role', 'department');
create type public.notification_priority as enum ('low', 'normal', 'high', 'urgent');
create type public.document_status as enum ('draft', 'submitted', 'under_review', 'approved', 'rejected', 'superseded', 'archived');
create type public.confidentiality_level as enum ('internal', 'confidential', 'restricted');
create type public.role_scope_type as enum ('organization', 'department', 'project');

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;
