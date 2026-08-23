-- Master Touch OS — 011
-- Atomic RPCs for numbering, projects, workflows, and approvals.

create or replace function public.protect_sensitive_profile_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.is_platform_admin is distinct from new.is_platform_admin
     and not public.is_platform_admin() then
    raise exception 'FORBIDDEN';
  end if;
  return new;
end;
$$;

create trigger profiles_protect_sensitive
  before update on public.profiles
  for each row execute function public.protect_sensitive_profile_fields();

create or replace function public.generate_project_code(p_organization_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prefix text;
  v_value integer;
begin
  if not public.has_permission('project.create', p_organization_id) then
    raise exception 'FORBIDDEN';
  end if;

  insert into public.project_counters (organization_id, prefix, next_value)
  values (p_organization_id, 'MT-PRJ', 1)
  on conflict (organization_id) do update
    set next_value = public.project_counters.next_value + 1
  returning prefix, next_value into v_prefix, v_value;

  return v_prefix || '-' || lpad(v_value::text, 4, '0');
end;
$$;

create or replace function public.create_project(
  p_organization_id uuid,
  p_name_ar text,
  p_name_en text,
  p_description text default null,
  p_client_id uuid default null,
  p_project_manager_id uuid default null,
  p_priority public.project_priority default 'medium',
  p_start_date date default null,
  p_planned_end_date date default null,
  p_location text default null,
  p_template_id uuid default null
)
returns public.projects
language plpgsql
security definer
set search_path = public
as $$
declare
  v_project public.projects;
  v_code text;
  v_template uuid;
  v_item record;
  v_dept uuid;
begin
  if not public.has_permission('project.create', p_organization_id) then
    raise exception 'FORBIDDEN';
  end if;

  v_code := public.generate_project_code(p_organization_id);

  insert into public.projects (
    organization_id, project_code, name_ar, name_en, description, client_id,
    project_manager_id, status, priority, start_date, planned_end_date,
    location, created_by
  ) values (
    p_organization_id, v_code, p_name_ar, p_name_en, p_description, p_client_id,
    p_project_manager_id, 'active', p_priority, p_start_date, p_planned_end_date,
    p_location, auth.uid()
  ) returning * into v_project;

  if p_project_manager_id is not null then
    insert into public.project_members (
      organization_id, project_id, profile_id, role_label, is_active
    ) values (
      p_organization_id, v_project.id, p_project_manager_id, 'project_manager', true
    ) on conflict (project_id, profile_id) do nothing;
  end if;

  select t.id into v_template
  from public.project_stage_templates t
  where t.id = coalesce(p_template_id, t.id)
    and t.is_active = true
    and (t.organization_id = p_organization_id or t.organization_id is null)
  order by case when t.id = p_template_id then 0 when t.is_default then 1 else 2 end
  limit 1;

  if v_template is not null then
    for v_item in
      select *
      from public.project_stage_template_items
      where template_id = v_template
      order by sequence
    loop
      select d.id into v_dept
      from public.departments d
      where d.organization_id = p_organization_id
        and d.code = v_item.department_code
      limit 1;

      insert into public.project_stages (
        organization_id, project_id, template_item_id, name_ar, name_en, sequence,
        department_id, requires_approval, sla_hours, risk_level
      ) values (
        p_organization_id, v_project.id, v_item.id, v_item.name_ar, v_item.name_en,
        v_item.sequence, v_dept, v_item.requires_approval, v_item.sla_hours, v_item.risk_level
      );
    end loop;
  end if;

  perform public.log_audit(
    p_organization_id,
    'project.created',
    'project',
    v_project.id,
    null,
    to_jsonb(v_project)
  );
  perform public.emit_domain_event(
    p_organization_id,
    'project.created',
    'project',
    v_project.id,
    jsonb_build_object('project_code', v_project.project_code)
  );

  return v_project;
end;
$$;

create or replace function public.start_workflow(
  p_organization_id uuid,
  p_definition_id uuid,
  p_entity_type text,
  p_entity_id uuid
)
returns public.workflow_instances
language plpgsql
security definer
set search_path = public
as $$
declare
  v_version public.workflow_versions;
  v_instance public.workflow_instances;
  v_step record;
  v_first boolean := true;
begin
  if not public.has_permission('workflow.start', p_organization_id) then
    raise exception 'FORBIDDEN';
  end if;

  if exists (
    select 1
    from public.workflow_instances i
    where i.organization_id = p_organization_id
      and i.definition_id = p_definition_id
      and i.entity_type = p_entity_type
      and i.entity_id = p_entity_id
      and i.status in ('pending', 'in_progress')
  ) then
    raise exception 'CONFLICT';
  end if;

  select *
  into v_version
  from public.workflow_versions
  where definition_id = p_definition_id
    and status = 'published'
  order by version_number desc
  limit 1;

  if v_version.id is null then
    raise exception 'NOT_FOUND';
  end if;

  insert into public.workflow_instances (
    organization_id, definition_id, version_id, entity_type, entity_id, status, started_by
  ) values (
    p_organization_id, p_definition_id, v_version.id, p_entity_type, p_entity_id, 'in_progress', auth.uid()
  ) returning * into v_instance;

  for v_step in
    select *
    from public.workflow_steps
    where version_id = v_version.id
    order by sequence
  loop
    insert into public.workflow_instance_steps (
      organization_id, instance_id, step_id, step_key, sequence, status,
      assigned_user_id, assigned_role_id, assigned_department_id,
      due_at, warning_at
    ) values (
      p_organization_id,
      v_instance.id,
      v_step.id,
      v_step.key,
      v_step.sequence,
      case when v_first then 'ready' else 'pending' end,
      v_step.assigned_user_id,
      v_step.assigned_role_id,
      v_step.assigned_department_id,
      case when v_first and v_step.sla_hours is not null
        then timezone('utc', now()) + make_interval(hours => v_step.sla_hours)
      end,
      case when v_first and v_step.warning_hours is not null
        then timezone('utc', now()) + make_interval(hours => v_step.warning_hours)
      end
    );
    v_first := false;
  end loop;

  perform public.log_audit(p_organization_id, 'workflow.started', 'workflow_instance', v_instance.id, null, to_jsonb(v_instance));
  perform public.emit_domain_event(p_organization_id, 'workflow.started', 'workflow_instance', v_instance.id, '{}'::jsonb);
  return v_instance;
end;
$$;

create or replace function public.complete_workflow_step(
  p_instance_step_id uuid,
  p_outcome text
)
returns public.workflow_instance_steps
language plpgsql
security definer
set search_path = public
as $$
declare
  v_step public.workflow_instance_steps;
  v_def public.workflow_steps;
  v_instance public.workflow_instances;
  v_next public.workflow_instance_steps;
  v_target public.workflow_instance_steps;
begin
  if p_outcome not in ('complete', 'reject', 'resubmit') then
    raise exception 'VALIDATION';
  end if;

  select * into v_step
  from public.workflow_instance_steps
  where id = p_instance_step_id
  for update;

  if v_step.id is null then
    raise exception 'NOT_FOUND';
  end if;

  if not (
    public.has_permission('workflow.advance', v_step.organization_id)
    or public.has_permission('workflow.manage', v_step.organization_id)
  ) then
    raise exception 'FORBIDDEN';
  end if;

  if v_step.status not in ('ready', 'in_progress') then
    raise exception 'CONFLICT';
  end if;

  select * into v_instance
  from public.workflow_instances
  where id = v_step.instance_id
  for update;

  if v_instance.status in ('completed', 'cancelled') then
    raise exception 'CONFLICT';
  end if;

  select * into v_def from public.workflow_steps where id = v_step.step_id;

  if p_outcome = 'reject' then
    update public.workflow_instance_steps
    set status = 'rejected', completed_at = timezone('utc', now()), completed_by = auth.uid()
    where id = v_step.id
    returning * into v_step;

    if v_def.on_reject_step_key is null then
      update public.workflow_instance_steps
      set status = 'cancelled'
      where instance_id = v_instance.id
        and id <> v_step.id
        and status in ('pending', 'ready', 'in_progress');

      update public.workflow_instances
      set status = 'cancelled', completed_at = timezone('utc', now())
      where id = v_instance.id;
    else
      select * into v_target
      from public.workflow_instance_steps
      where instance_id = v_instance.id and step_key = v_def.on_reject_step_key
      for update;

      if v_target.id is null then
        raise exception 'VALIDATION';
      end if;

      update public.workflow_instance_steps
      set status = 'ready', started_at = timezone('utc', now())
      where id = v_target.id;
    end if;
  elsif p_outcome = 'resubmit' then
    if v_def.on_resubmit_step_key is null then
      raise exception 'VALIDATION';
    end if;

    update public.workflow_instance_steps
    set status = 'completed', completed_at = timezone('utc', now()), completed_by = auth.uid()
    where id = v_step.id
    returning * into v_step;

    update public.workflow_instance_steps s
    set status = case when s.step_key = v_def.on_resubmit_step_key then 'ready' else 'pending' end,
        completed_at = null,
        completed_by = null
    where s.instance_id = v_instance.id
      and s.sequence >= (
        select sequence from public.workflow_instance_steps
        where instance_id = v_instance.id and step_key = v_def.on_resubmit_step_key
      )
      and s.sequence < v_step.sequence;
  else
    update public.workflow_instance_steps
    set status = 'completed', completed_at = timezone('utc', now()), completed_by = auth.uid()
    where id = v_step.id
      and status in ('ready', 'in_progress')
    returning * into v_step;

    if v_step.id is null then
      raise exception 'CONFLICT';
    end if;

    select * into v_next
    from public.workflow_instance_steps
    where instance_id = v_instance.id
      and sequence > v_step.sequence
      and status = 'pending'
    order by sequence
    limit 1;

    if v_next.id is null then
      update public.workflow_instances
      set status = 'completed', completed_at = timezone('utc', now())
      where id = v_instance.id;
    else
      update public.workflow_instance_steps
      set status = 'ready', started_at = timezone('utc', now())
      where id = v_next.id;
    end if;
  end if;

  perform public.log_audit(
    v_step.organization_id,
    'workflow.step.completed',
    'workflow_instance_step',
    v_step.id,
    null,
    jsonb_build_object('outcome', p_outcome)
  );
  perform public.emit_domain_event(
    v_step.organization_id,
    'workflow.step.completed',
    'workflow_instance_step',
    v_step.id,
    jsonb_build_object('outcome', p_outcome)
  );

  return v_step;
end;
$$;

create or replace function public.submit_approval_decision(
  p_step_id uuid,
  p_official_code text,
  p_comment text default null
)
returns public.approval_actions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_step public.approval_steps;
  v_request public.approval_requests;
  v_decision public.approval_decision;
  v_action public.approval_actions;
  v_next public.approval_steps;
begin
  if p_official_code not in ('A', 'B', 'C', 'D', 'E') then
    raise exception 'VALIDATION';
  end if;

  v_decision := case p_official_code
    when 'A' then 'approved'::public.approval_decision
    when 'B' then 'approved_as_noted'::public.approval_decision
    when 'C' then 'resubmit'::public.approval_decision
    when 'D' then 'rejected'::public.approval_decision
    else 'for_information'::public.approval_decision
  end;

  select * into v_step
  from public.approval_steps
  where id = p_step_id
  for update;

  if v_step.id is null then
    raise exception 'NOT_FOUND';
  end if;

  if v_decision in ('rejected') and not public.has_permission('approval.reject', v_step.organization_id) then
    raise exception 'FORBIDDEN';
  end if;

  if v_decision not in ('rejected') and not (
    public.has_permission('approval.approve', v_step.organization_id)
    or public.has_permission('approval.review', v_step.organization_id)
  ) then
    raise exception 'FORBIDDEN';
  end if;

  if v_step.status in ('completed', 'cancelled', 'skipped') then
    raise exception 'CONFLICT';
  end if;

  if exists (select 1 from public.approval_actions where step_id = v_step.id) then
    raise exception 'CONFLICT';
  end if;

  select * into v_request
  from public.approval_requests
  where id = v_step.request_id
  for update;

  if v_request.status in ('completed', 'cancelled') then
    raise exception 'CONFLICT';
  end if;

  if v_request.mode = 'sequential' then
    if exists (
      select 1
      from public.approval_steps s
      where s.request_id = v_request.id
        and s.sequence < v_step.sequence
        and s.status in ('pending', 'in_progress')
    ) then
      raise exception 'CONFLICT';
    end if;
  end if;

  insert into public.approval_actions (
    organization_id, request_id, step_id, actor_id, decision, official_code, comment
  ) values (
    v_step.organization_id, v_request.id, v_step.id, auth.uid(), v_decision, p_official_code, p_comment
  ) returning * into v_action;

  update public.approval_steps
  set status = 'completed'
  where id = v_step.id;

  if v_decision in ('rejected', 'resubmit') or not exists (
    select 1 from public.approval_steps
    where request_id = v_request.id
      and id <> v_step.id
      and status in ('pending', 'in_progress')
  ) then
    update public.approval_requests
    set status = 'completed',
        official_outcome = v_decision,
        official_code = p_official_code,
        completed_at = timezone('utc', now())
    where id = v_request.id;
  else
    select * into v_next
    from public.approval_steps
    where request_id = v_request.id
      and status = 'pending'
    order by sequence
    limit 1;

    if v_next.id is not null and v_request.mode = 'sequential' then
      update public.approval_steps set status = 'in_progress' where id = v_next.id;
    end if;

    update public.approval_requests
    set status = 'in_progress'
    where id = v_request.id;
  end if;

  perform public.log_audit(
    v_step.organization_id,
    case
      when v_decision = 'rejected' then 'approval.rejected'
      when v_decision = 'resubmit' then 'approval.resubmitted'
      else 'approval.approved'
    end,
    'approval_request',
    v_request.id,
    null,
    to_jsonb(v_action)
  );
  perform public.emit_domain_event(
    v_step.organization_id,
    case
      when v_decision = 'rejected' then 'approval.rejected'
      when v_decision = 'resubmit' then 'approval.resubmitted'
      else 'approval.approved'
    end,
    'approval_request',
    v_request.id,
    jsonb_build_object('official_code', p_official_code)
  );

  return v_action;
end;
$$;

create or replace function public.bootstrap_platform_admin(p_email text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_org_id uuid;
  v_role_id uuid;
begin
  if exists (select 1 from public.profiles where is_platform_admin = true) then
    raise exception 'CONFLICT';
  end if;

  select id into v_user_id from auth.users where email = lower(p_email) limit 1;
  if v_user_id is null then
    raise exception 'NOT_FOUND';
  end if;

  update public.profiles
  set is_platform_admin = true, is_active = true
  where id = v_user_id;

  select id into v_org_id from public.organizations order by created_at limit 1;
  if v_org_id is null then
    raise exception 'NOT_FOUND';
  end if;

  insert into public.organization_members (organization_id, profile_id, status)
  values (v_org_id, v_user_id, 'active')
  on conflict (organization_id, profile_id) do update set status = 'active';

  select id into v_role_id from public.roles where code = 'super_admin' and organization_id is null;

  if v_role_id is not null then
    insert into public.user_roles (organization_id, profile_id, role_id, scope_type)
    values (v_org_id, v_user_id, v_role_id, 'organization')
    on conflict do nothing;
  end if;
end;
$$;

grant execute on function public.generate_project_code(uuid) to authenticated;
grant execute on function public.create_project(uuid, text, text, text, uuid, uuid, public.project_priority, date, date, text, uuid) to authenticated;
grant execute on function public.start_workflow(uuid, uuid, text, uuid) to authenticated;
grant execute on function public.complete_workflow_step(uuid, text) to authenticated;
grant execute on function public.submit_approval_decision(uuid, text, text) to authenticated;
revoke all on function public.bootstrap_platform_admin(text) from public, anon, authenticated;
