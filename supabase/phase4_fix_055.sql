-- =============================================================================
-- Migration 055: Disambiguate column reference "id" in get_employee_banking RPC
-- =============================================================================

create or replace function public.get_employee_banking(
  p_employee_id uuid
)
returns table (
  id uuid,
  organization_id uuid,
  employee_id uuid,
  bank_name text,
  iban text,
  masked_iban text,
  account_name text,
  swift_code text,
  is_primary boolean,
  is_active boolean,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_emp public.employees;
  v_is_self boolean;
  v_can_manage boolean;
  v_can_read boolean;
begin
  select * into v_emp from public.employees e where e.id = p_employee_id;
  if v_emp.id is null then
    return;
  end if;

  if not public.is_organization_member(v_emp.organization_id) then
    raise exception 'FORBIDDEN' using errcode = 'P0001';
  end if;

  v_is_self := (v_emp.profile_id = auth.uid());
  v_can_manage := public.has_permission('employee_bank.manage', v_emp.organization_id, 'organization', null)
               or public.has_permission('finance.manage', v_emp.organization_id, 'organization', null)
               or public.has_permission('employee.manage', v_emp.organization_id, 'organization', null);
  v_can_read := public.has_permission('employee_bank.read', v_emp.organization_id, 'organization', null)
             or public.has_permission('finance.read', v_emp.organization_id, 'organization', null);

  if not (public.is_platform_admin() or v_can_manage or v_can_read or v_is_self) then
    raise exception 'FORBIDDEN' using errcode = 'P0001';
  end if;

  return query
  select
    b.id,
    b.organization_id,
    b.employee_id,
    b.bank_name,
    case
      when public.is_platform_admin() or v_can_manage or v_can_read then b.iban
      else null::text
    end as iban,
    case
      when length(b.iban) >= 8 then
        substr(b.iban, 1, 4) || ' **** **** **** ' || substr(b.iban, length(b.iban) - 3, 4)
      else '****'
    end as masked_iban,
    b.account_name,
    b.swift_code,
    b.is_primary,
    b.is_active,
    b.created_at,
    b.updated_at
  from public.employee_bank_accounts b
  where b.employee_id = p_employee_id
    and b.organization_id = v_emp.organization_id
  order by b.is_primary desc, b.created_at desc;
end;
$$;

grant execute on function public.get_employee_banking(uuid) to authenticated;
