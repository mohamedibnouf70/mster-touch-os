-- Master Touch OS — 013
-- Production-safe system seed: organization, departments, RBAC, templates.
-- Does NOT create employees, users, or financial figures.

insert into public.organizations (
  id, name_ar, name_en, legal_name, country, timezone, default_currency, status
) values (
  '11111111-1111-1111-1111-111111111111',
  'ماستر تاتش',
  'Master Touch',
  'Master Touch',
  'SA',
  'Asia/Riyadh',
  'SAR',
  'active'
) on conflict (id) do nothing;

insert into public.departments (organization_id, code, name_ar, name_en, description)
values
  ('11111111-1111-1111-1111-111111111111', 'GM', 'الإدارة العامة', 'General Management', 'الإدارة العليا للشركة'),
  ('11111111-1111-1111-1111-111111111111', 'PM', 'إدارة المشاريع', 'Project Management', 'إدارة تنفيذ المشاريع'),
  ('11111111-1111-1111-1111-111111111111', 'ENG', 'الهندسة', 'Engineering', 'الهندسة والتصميم'),
  ('11111111-1111-1111-1111-111111111111', 'MEP', 'المكتب الفني / MEP', 'Technical Office / MEP', 'المكتب الفني والكهرباء والميكانيكا'),
  ('11111111-1111-1111-1111-111111111111', 'DC', 'ضبط الوثائق', 'Document Control', 'ضبط وإصدار الوثائق'),
  ('11111111-1111-1111-1111-111111111111', 'FIN', 'المالية', 'Finance', 'الشؤون المالية'),
  ('11111111-1111-1111-1111-111111111111', 'HR', 'الموارد البشرية', 'Human Resources', 'شؤون الموظفين'),
  ('11111111-1111-1111-1111-111111111111', 'PRC', 'المشتريات', 'Procurement', 'المشتريات والتوريد'),
  ('11111111-1111-1111-1111-111111111111', 'LOG', 'الخدمات والمرافق', 'Logistics / Facilities', 'الخدمات اللوجستية والمرافق'),
  ('11111111-1111-1111-1111-111111111111', 'HSE', 'الصحة والسلامة', 'HSE', 'الصحة والسلامة والبيئة'),
  ('11111111-1111-1111-1111-111111111111', 'QA', 'الجودة', 'Quality', 'ضمان الجودة'),
  ('11111111-1111-1111-1111-111111111111', 'ADM', 'الإدارة الإدارية', 'Administration', 'الشؤون الإدارية')
on conflict (organization_id, code) do nothing;

insert into public.permissions (key, resource, action, description_ar, description_en) values
  ('organization.read', 'organization', 'read', 'عرض بيانات المنشأة', 'Read organization'),
  ('organization.update', 'organization', 'update', 'تحديث بيانات المنشأة', 'Update organization'),
  ('department.create', 'department', 'create', 'إنشاء إدارة', 'Create department'),
  ('department.read', 'department', 'read', 'عرض الإدارات', 'Read departments'),
  ('department.update', 'department', 'update', 'تحديث الإدارات', 'Update departments'),
  ('project.create', 'project', 'create', 'إنشاء مشروع', 'Create project'),
  ('project.read', 'project', 'read', 'عرض المشاريع', 'Read projects'),
  ('project.update', 'project', 'update', 'تحديث المشاريع', 'Update projects'),
  ('project.archive', 'project', 'archive', 'أرشفة المشاريع', 'Archive projects'),
  ('project.manage_team', 'project', 'manage_team', 'إدارة فريق المشروع', 'Manage project team'),
  ('user.create', 'user', 'create', 'إنشاء مستخدم', 'Create user'),
  ('user.read', 'user', 'read', 'عرض المستخدمين', 'Read users'),
  ('user.update', 'user', 'update', 'تحديث المستخدمين', 'Update users'),
  ('user.disable', 'user', 'disable', 'إيقاف المستخدمين', 'Disable users'),
  ('role.read', 'role', 'read', 'عرض الأدوار', 'Read roles'),
  ('role.assign', 'role', 'assign', 'تعيين الأدوار', 'Assign roles'),
  ('document.upload', 'document', 'upload', 'رفع مستند', 'Upload document'),
  ('document.read', 'document', 'read', 'عرض المستندات', 'Read documents'),
  ('document.update', 'document', 'update', 'تحديث المستندات', 'Update documents'),
  ('document.approve', 'document', 'approve', 'اعتماد المستندات', 'Approve documents'),
  ('approval.create', 'approval', 'create', 'إنشاء طلب موافقة', 'Create approval'),
  ('approval.review', 'approval', 'review', 'مراجعة الموافقات', 'Review approvals'),
  ('approval.approve', 'approval', 'approve', 'اعتماد الموافقات', 'Approve requests'),
  ('approval.reject', 'approval', 'reject', 'رفض الموافقات', 'Reject approvals'),
  ('finance.read', 'finance', 'read', 'عرض البيانات المالية', 'Read finance'),
  ('finance.manage', 'finance', 'manage', 'إدارة المالية', 'Manage finance'),
  ('employee.read', 'employee', 'read', 'عرض الموظفين', 'Read employees'),
  ('employee.manage', 'employee', 'manage', 'إدارة الموظفين', 'Manage employees'),
  ('reports.management.read', 'reports', 'read', 'عرض تقارير الإدارة', 'Read management reports'),
  ('audit.read', 'audit', 'read', 'عرض سجل التدقيق', 'Read audit trail'),
  ('notification.read', 'notification', 'read', 'عرض التنبيهات', 'Read notifications'),
  ('workflow.start', 'workflow', 'start', 'بدء مسار عمل', 'Start workflow'),
  ('workflow.advance', 'workflow', 'advance', 'تقدم مسار العمل', 'Advance workflow'),
  ('workflow.manage', 'workflow', 'manage', 'إدارة مسارات العمل', 'Manage workflows'),
  ('settings.manage', 'settings', 'manage', 'إدارة الإعدادات', 'Manage settings')
on conflict (key) do nothing;

insert into public.roles (id, organization_id, code, name_ar, name_en, is_system, is_external) values
  ('20000000-0000-0000-0000-000000000001', null, 'super_admin', 'مدير النظام', 'Super Admin', true, false),
  ('20000000-0000-0000-0000-000000000002', null, 'general_manager', 'المدير العام', 'General Manager', true, false),
  ('20000000-0000-0000-0000-000000000003', null, 'operations_manager', 'مدير العمليات', 'Operations Manager', true, false),
  ('20000000-0000-0000-0000-000000000004', null, 'department_manager', 'مدير إدارة', 'Department Manager', true, false),
  ('20000000-0000-0000-0000-000000000005', null, 'project_manager', 'مدير مشروع', 'Project Manager', true, false),
  ('20000000-0000-0000-0000-000000000006', null, 'project_engineer', 'مهندس مشروع', 'Project Engineer', true, false),
  ('20000000-0000-0000-0000-000000000007', null, 'engineer', 'مهندس', 'Engineer', true, false),
  ('20000000-0000-0000-0000-000000000008', null, 'document_controller', 'ضابط وثائق', 'Document Controller', true, false),
  ('20000000-0000-0000-0000-000000000009', null, 'finance_manager', 'مدير مالية', 'Finance Manager', true, false),
  ('20000000-0000-0000-0000-00000000000a', null, 'finance_officer', 'موظف مالية', 'Finance Officer', true, false),
  ('20000000-0000-0000-0000-00000000000b', null, 'hr_manager', 'مدير موارد بشرية', 'HR Manager', true, false),
  ('20000000-0000-0000-0000-00000000000c', null, 'hr_officer', 'موظف موارد بشرية', 'HR Officer', true, false),
  ('20000000-0000-0000-0000-00000000000d', null, 'procurement_manager', 'مدير مشتريات', 'Procurement Manager', true, false),
  ('20000000-0000-0000-0000-00000000000e', null, 'procurement_officer', 'موظف مشتريات', 'Procurement Officer', true, false),
  ('20000000-0000-0000-0000-00000000000f', null, 'hse_manager', 'مدير سلامة', 'HSE Manager', true, false),
  ('20000000-0000-0000-0000-000000000010', null, 'hse_officer', 'موظف سلامة', 'HSE Officer', true, false),
  ('20000000-0000-0000-0000-000000000011', null, 'quality_manager', 'مدير جودة', 'Quality Manager', true, false),
  ('20000000-0000-0000-0000-000000000012', null, 'quality_officer', 'موظف جودة', 'Quality Officer', true, false),
  ('20000000-0000-0000-0000-000000000013', null, 'viewer', 'مستعرض', 'Viewer', true, false),
  ('20000000-0000-0000-0000-000000000014', null, 'client', 'عميل', 'Client', true, true),
  ('20000000-0000-0000-0000-000000000015', null, 'consultant', 'استشاري', 'Consultant', true, true),
  ('20000000-0000-0000-0000-000000000016', null, 'supplier', 'مورد', 'Supplier', true, true),
  ('20000000-0000-0000-0000-000000000017', null, 'subcontractor', 'مقاول باطن', 'Subcontractor', true, true)
on conflict do nothing;

insert into public.role_permissions (role_id, permission_key)
select r.id, p.key
from public.roles r
cross join public.permissions p
where r.code = 'super_admin'
on conflict do nothing;

insert into public.role_permissions (role_id, permission_key)
select r.id, p.key
from public.roles r
cross join public.permissions p
where r.code = 'general_manager' and p.key <> 'settings.manage'
on conflict do nothing;

insert into public.role_permissions (role_id, permission_key)
select r.id, x.permission_key
from public.roles r
join (values
  ('operations_manager', 'project.create'),
  ('operations_manager', 'project.read'),
  ('operations_manager', 'project.update'),
  ('operations_manager', 'project.archive'),
  ('operations_manager', 'project.manage_team'),
  ('operations_manager', 'document.upload'),
  ('operations_manager', 'document.read'),
  ('operations_manager', 'document.update'),
  ('operations_manager', 'document.approve'),
  ('operations_manager', 'approval.create'),
  ('operations_manager', 'approval.review'),
  ('operations_manager', 'approval.approve'),
  ('operations_manager', 'approval.reject'),
  ('operations_manager', 'workflow.start'),
  ('operations_manager', 'workflow.advance'),
  ('operations_manager', 'workflow.manage'),
  ('operations_manager', 'employee.read'),
  ('operations_manager', 'department.read'),
  ('operations_manager', 'notification.read'),
  ('operations_manager', 'reports.management.read'),
  ('department_manager', 'department.read'),
  ('department_manager', 'department.update'),
  ('department_manager', 'project.read'),
  ('department_manager', 'project.update'),
  ('department_manager', 'document.upload'),
  ('department_manager', 'document.read'),
  ('department_manager', 'document.update'),
  ('department_manager', 'document.approve'),
  ('department_manager', 'approval.create'),
  ('department_manager', 'approval.review'),
  ('department_manager', 'approval.approve'),
  ('department_manager', 'approval.reject'),
  ('department_manager', 'workflow.advance'),
  ('department_manager', 'employee.read'),
  ('department_manager', 'notification.read'),
  ('department_manager', 'audit.read'),
  ('project_manager', 'project.read'),
  ('project_manager', 'project.update'),
  ('project_manager', 'project.manage_team'),
  ('project_manager', 'document.upload'),
  ('project_manager', 'document.read'),
  ('project_manager', 'document.update'),
  ('project_manager', 'document.approve'),
  ('project_manager', 'approval.create'),
  ('project_manager', 'approval.review'),
  ('project_manager', 'approval.approve'),
  ('project_manager', 'approval.reject'),
  ('project_manager', 'workflow.start'),
  ('project_manager', 'workflow.advance'),
  ('project_manager', 'employee.read'),
  ('project_manager', 'department.read'),
  ('project_manager', 'notification.read'),
  ('project_engineer', 'project.read'),
  ('project_engineer', 'document.upload'),
  ('project_engineer', 'document.read'),
  ('project_engineer', 'document.update'),
  ('project_engineer', 'approval.create'),
  ('project_engineer', 'approval.review'),
  ('project_engineer', 'workflow.advance'),
  ('project_engineer', 'notification.read'),
  ('project_engineer', 'department.read'),
  ('engineer', 'project.read'),
  ('engineer', 'document.upload'),
  ('engineer', 'document.read'),
  ('engineer', 'approval.create'),
  ('engineer', 'notification.read'),
  ('document_controller', 'project.read'),
  ('document_controller', 'document.upload'),
  ('document_controller', 'document.read'),
  ('document_controller', 'document.update'),
  ('document_controller', 'document.approve'),
  ('document_controller', 'approval.create'),
  ('document_controller', 'approval.review'),
  ('document_controller', 'workflow.advance'),
  ('document_controller', 'notification.read'),
  ('finance_manager', 'finance.read'),
  ('finance_manager', 'finance.manage'),
  ('finance_manager', 'project.read'),
  ('finance_manager', 'document.read'),
  ('finance_manager', 'document.upload'),
  ('finance_manager', 'approval.create'),
  ('finance_manager', 'approval.review'),
  ('finance_manager', 'approval.approve'),
  ('finance_manager', 'approval.reject'),
  ('finance_manager', 'employee.read'),
  ('finance_manager', 'notification.read'),
  ('finance_manager', 'reports.management.read'),
  ('finance_manager', 'audit.read'),
  ('finance_officer', 'finance.read'),
  ('finance_officer', 'project.read'),
  ('finance_officer', 'document.read'),
  ('finance_officer', 'document.upload'),
  ('finance_officer', 'approval.create'),
  ('finance_officer', 'notification.read'),
  ('hr_manager', 'employee.read'),
  ('hr_manager', 'employee.manage'),
  ('hr_manager', 'user.read'),
  ('hr_manager', 'user.update'),
  ('hr_manager', 'department.read'),
  ('hr_manager', 'notification.read'),
  ('hr_manager', 'audit.read'),
  ('hr_officer', 'employee.read'),
  ('hr_officer', 'user.read'),
  ('hr_officer', 'department.read'),
  ('hr_officer', 'notification.read'),
  ('procurement_manager', 'project.read'),
  ('procurement_manager', 'document.upload'),
  ('procurement_manager', 'document.read'),
  ('procurement_manager', 'document.update'),
  ('procurement_manager', 'approval.create'),
  ('procurement_manager', 'approval.review'),
  ('procurement_manager', 'approval.approve'),
  ('procurement_manager', 'notification.read'),
  ('procurement_officer', 'project.read'),
  ('procurement_officer', 'document.upload'),
  ('procurement_officer', 'document.read'),
  ('procurement_officer', 'approval.create'),
  ('procurement_officer', 'notification.read'),
  ('hse_manager', 'project.read'),
  ('hse_manager', 'document.upload'),
  ('hse_manager', 'document.read'),
  ('hse_manager', 'document.update'),
  ('hse_manager', 'approval.create'),
  ('hse_manager', 'approval.review'),
  ('hse_manager', 'approval.approve'),
  ('hse_manager', 'notification.read'),
  ('hse_officer', 'project.read'),
  ('hse_officer', 'document.upload'),
  ('hse_officer', 'document.read'),
  ('hse_officer', 'approval.create'),
  ('hse_officer', 'notification.read'),
  ('quality_manager', 'project.read'),
  ('quality_manager', 'document.upload'),
  ('quality_manager', 'document.read'),
  ('quality_manager', 'document.update'),
  ('quality_manager', 'approval.create'),
  ('quality_manager', 'approval.review'),
  ('quality_manager', 'approval.approve'),
  ('quality_manager', 'notification.read'),
  ('quality_officer', 'project.read'),
  ('quality_officer', 'document.upload'),
  ('quality_officer', 'document.read'),
  ('quality_officer', 'approval.create'),
  ('quality_officer', 'notification.read')
) as x(code, permission_key) on x.code = r.code
on conflict do nothing;

insert into public.role_permissions (role_id, permission_key)
select r.id, p.key
from public.roles r
join public.permissions p on p.key like '%.read'
where r.code = 'viewer'
on conflict do nothing;

insert into public.project_stage_templates (id, organization_id, code, name_ar, name_en, is_default, is_active)
values (
  '30000000-0000-0000-0000-000000000001',
  null,
  'default_lifecycle',
  'دورة حياة المشروع الافتراضية',
  'Default project lifecycle',
  true,
  true
) on conflict do nothing;

insert into public.project_stage_template_items (template_id, name_ar, name_en, sequence, department_code, requires_approval, sla_hours)
values
  ('30000000-0000-0000-0000-000000000001', 'البداية', 'Initiation', 1, 'GM', true, 72),
  ('30000000-0000-0000-0000-000000000001', 'إعداد العقد والتجاري', 'Contract / Commercial Setup', 2, 'FIN', true, 120),
  ('30000000-0000-0000-0000-000000000001', 'التصميم والهندسة', 'Design & Engineering', 3, 'ENG', true, 240),
  ('30000000-0000-0000-0000-000000000001', 'اعتمادات ما قبل التنفيذ', 'Pre-Execution Approvals', 4, 'DC', true, 96),
  ('30000000-0000-0000-0000-000000000001', 'المشتريات', 'Procurement', 5, 'PRC', true, 168),
  ('30000000-0000-0000-0000-000000000001', 'التجهيز والMobilization', 'Mobilization', 6, 'PM', false, 72),
  ('30000000-0000-0000-0000-000000000001', 'التنفيذ', 'Execution', 7, 'PM', false, 720),
  ('30000000-0000-0000-0000-000000000001', 'الاختبار والتشغيل', 'Testing & Commissioning', 8, 'MEP', true, 168),
  ('30000000-0000-0000-0000-000000000001', 'التسليم', 'Handover', 9, 'PM', true, 120),
  ('30000000-0000-0000-0000-000000000001', 'الإغلاق', 'Closeout', 10, 'GM', true, 96)
on conflict do nothing;

insert into public.workflow_definitions (id, organization_id, code, name_ar, name_en, entity_type, status)
values (
  '40000000-0000-0000-0000-000000000001',
  null,
  'document_approval',
  'اعتماد مستند',
  'Document approval',
  'document',
  'published'
) on conflict do nothing;

insert into public.workflow_versions (id, definition_id, version_number, status, published_at)
values (
  '40000000-0000-0000-0000-000000000101',
  '40000000-0000-0000-0000-000000000001',
  1,
  'published',
  timezone('utc', now())
) on conflict do nothing;

insert into public.workflow_steps (version_id, key, name_ar, name_en, sequence, assignee_type, requires_approval, sla_hours, warning_hours, on_reject_step_key, on_resubmit_step_key)
values
  ('40000000-0000-0000-0000-000000000101', 'submit', 'تقديم', 'Submit', 1, 'unassigned', false, 24, 12, null, null),
  ('40000000-0000-0000-0000-000000000101', 'review', 'مراجعة ضبط الوثائق', 'Document control review', 2, 'role', true, 48, 24, null, 'submit'),
  ('40000000-0000-0000-0000-000000000101', 'approve', 'اعتماد', 'Approve', 3, 'role', true, 48, 24, null, 'review')
on conflict do nothing;

update public.workflow_steps s
set assigned_role_id = r.id
from public.roles r
where s.version_id = '40000000-0000-0000-0000-000000000101'
  and s.key = 'review'
  and r.code = 'document_controller';

update public.workflow_steps s
set assigned_role_id = r.id
from public.roles r
where s.version_id = '40000000-0000-0000-0000-000000000101'
  and s.key = 'approve'
  and r.code = 'project_manager';
