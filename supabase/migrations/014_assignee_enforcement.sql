-- Master Touch OS — 014
-- Enforce assignee checks on approval and workflow step actions.
-- Users with broad permissions cannot act on steps assigned to others unless platform admin / workflow.manage.

create or replace function public.can_act_on_approval_step(p_step_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_platform_admin()
    or public.has_permission('workflow.manage', s.organization_id)
    or (
      s.approver_type = 'user'
      and coalesce(s.delegated_to, s.user_id) = auth.uid()
    )
    or (
      s.approver_type = 'role'
      and s.role_id is not null
      and exists (
        select 1
        from public.user_roles ur
        where ur.profile_id = auth.uid()
          and ur.organization_id = s.organization_id
          and ur.role_id = s.role_id
      )
    )
    or (
      s.approver_type = 'department'
      and s.department_id is not null
      and exists (
        select 1
        from public.employees e
        join public.employee_departments ed on ed.employee_id = e.id
        where e.profile_id = auth.uid()
          and e.organization_id = s.organization_id
          and e.is_active = true
          and ed.department_id = s.department_id
      )
    )
  from public.approval_steps s
  where s.id = p_step_id;
$$;

create or replace function public.can_act_on_workflow_step(p_step_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_platform_admin()
    or public.has_permission('workflow.manage', s.organization_id)
    or s.assigned_user_id = auth.uid()
    or (
      s.assigned_role_id is not null
      and exists (
        select 1
        from public.user_roles ur
        where ur.profile_id = auth.uid()
          and ur.organization_id = s.organization_id
          and ur.role_id = s.assigned_role_id
      )
    )
    or (
      s.assigned_department_id is not null
      and exists (
        select 1
        from public.employees e
        join public.employee_departments ed on ed.employee_id = e.id
        where e.profile_id = auth.uid()
          and e.organization_id = s.organization_id
          and e.is_active = true
          and ed.department_id = s.assigned_department_id
      )
    )
  from public.workflow_instance_steps s
  where s.id = p_step_id;
$$;

grant execute on function public.can_act_on_approval_step(uuid) to authenticated;
grant execute on function public.can_act_on_workflow_step(uuid) to authenticated;

-- Patch submit_approval_decision: require assignee match (or manage override).
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

  if not public.can_act_on_approval_step(p_step_id) then
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

-- Patch complete_workflow_step: workflow.advance requires assignee unless workflow.manage.
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

  if not (
    public.has_permission('workflow.manage', v_step.organization_id)
    or public.can_act_on_workflow_step(p_instance_step_id)
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

grant execute on function public.submit_approval_decision(uuid, text, text) to authenticated;
grant execute on function public.complete_workflow_step(uuid, text) to authenticated;
