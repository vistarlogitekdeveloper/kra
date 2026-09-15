/**
 * Adds POST /employees/:id/transfer — move an existing employee to another
 * organization. SUPER_ADMIN only.
 *
 * Run with node:
 *
 *     node D:\Vistar\krafrontend\docs\install_employee_transfer.mjs --dry
 *     node D:\Vistar\krafrontend\docs\install_employee_transfer.mjs
 *
 * Idempotent; backs each file up as <name>.bak before writing.
 *
 * ── WHY A NAMED ENDPOINT AND NOT A PATCH FIELD ──────────────────────────────
 *
 * employees.repository.js `update()` is a strict field whitelist that omits
 * organizationId, so adding the field to UpdateEmployeeSchema would change
 * nothing while LOOKING like it worked — the worst possible outcome. Moving an
 * employee is also not one write: it has to relocate their KRA assignments and
 * drop references that only make sense in the old tenant. That is a migration,
 * so it gets its own verb.
 *
 * ── WHAT IT REFUSES, AND WHY THAT IS NOT NEGOTIABLE ─────────────────────────
 *
 * kra.reviews has NO organization_id. A review hangs off a review_cycle, and
 * the CYCLE carries the organization. So a review's tenancy is decided by the
 * cycle that produced it, and there is no column to update to bring history
 * along — moving the employee leaves it behind permanently.
 *
 * The endpoint therefore REFUSES (409) when the employee has any reviews,
 * rather than silently detaching their history. Everyone else moves cleanly.
 *
 * ── WHAT IT DOES, IN ONE TRANSACTION ────────────────────────────────────────
 *
 *   1. employees.organization_id  -> the destination
 *   2. manager_id = NULL          -> their manager is in the old tenant
 *   3. project_location_id = NULL -> that site belongs to the old tenant and
 *                                    is not even offered in the new one's form
 *   4. kra_assignments.organization_id -> follows the employee, so it does not
 *                                    orphan (this is what stranded VLPL0591)
 *   5. an EMPLOYEE.UPDATED audit entry recording both organization ids
 */
import fs from 'fs';

const B = 'D:/Vistar/vistar_CRM/src/modules/kra/dist/features/employees';
const DRY = process.argv.includes('--dry');

const SERVICE_FN = `    /**
     * Move an employee to another organization.
     *
     * Refuses when they have reviews. kra.reviews has no organization_id — a
     * review's tenant is whichever organization owns its review_cycle — so
     * there is no way to bring history along, and a "successful" transfer
     * would quietly make it invisible to the employee and their new manager.
     * Better to refuse and let the caller decide.
     *
     * manager_id and project_location_id are cleared because both reference
     * rows in the OLD organization; leaving them gives the employee a manager
     * their tenant does not contain and a location its forms cannot offer.
     * Reassign from inside the destination organization afterwards.
     */
    async transfer(actorId, id, targetOrganizationId) {
        const employee = await employees_repository_1.employeesRepository.findById(id);
        if (!employee) {
            throw new http_errors_1.NotFoundError('Employee');
        }
        const target = await database_1.prisma.organization.findUnique({
            where: { id: targetOrganizationId },
        });
        if (!target) {
            throw new http_errors_1.BadRequestError('Organization not found');
        }
        const fromOrganizationId = employee.organizationId;
        if (fromOrganizationId === targetOrganizationId) {
            throw new http_errors_1.BadRequestError('Employee is already in that organization');
        }
        const reviewCount = await database_1.prisma.review.count({
            where: { employeeId: id },
        });
        if (reviewCount > 0) {
            throw new http_errors_1.ConflictError(\`This employee has \${reviewCount} review(s). Review history belongs to the organization that ran the review cycle and cannot move with them, so the transfer was not made. Create a new account in the destination organization instead.\`);
        }
        await database_1.prisma.$transaction([
            database_1.prisma.employee.update({
                where: { id },
                data: {
                    organizationId: targetOrganizationId,
                    managerId: null,
                    projectLocationId: null,
                },
            }),
            // Assignments carry their own organizationId, so they must follow or
            // they orphan in the old tenant.
            database_1.prisma.kraAssignment.updateMany({
                where: { employeeId: id },
                data: { organizationId: targetOrganizationId },
            }),
        ]);
        await (0, audit_1.writeAudit)(database_1.prisma, {
            actorId,
            action: audit_1.AuditAction.EMPLOYEE_UPDATED,
            entityType: 'Employee',
            entityId: id,
            oldValues: { organizationId: fromOrganizationId },
            newValues: { organizationId: targetOrganizationId },
        });
        return employees_repository_1.employeesRepository.findById(id);
    },
`;

const EDITS = [
  // 1. Validation schema for the body.
  {
    file: `${B}/employees.types.js`,
    marker: 'TransferEmployeeSchema',
    find: 'exports.CreateEmployeeSchema = zod_1.z.object({',
    replace:
      '// Body of POST /employees/:id/transfer.\n' +
      'exports.TransferEmployeeSchema = zod_1.z.object({\n' +
      '    organizationId: zod_1.z.string().min(1).max(64),\n' +
      '});\n' +
      'exports.CreateEmployeeSchema = zod_1.z.object({',
  },
  // 2. Export it alongside the others so `require` picks it up.
  {
    file: `${B}/employees.types.js`,
    marker: 'exports.TransferEmployeeSchema = void 0',
    find: 'exports.ListEmployeesQuerySchema = exports.UpdateEmployeeSchema = exports.CreateEmployeeSchema = void 0;',
    replace:
      'exports.TransferEmployeeSchema = exports.ListEmployeesQuerySchema = exports.UpdateEmployeeSchema = exports.CreateEmployeeSchema = void 0;',
  },
  // 3. The service method.
  {
    file: `${B}/employees.service.js`,
    marker: 'async transfer(actorId, id, targetOrganizationId)',
    find: '    async update(actorId, organizationId, id, input) {',
    replace: SERVICE_FN + '    async update(actorId, organizationId, id, input) {',
  },
  // 4. Controller action.
  {
    file: `${B}/employees.controller.js`,
    marker: 'async transfer(req, res)',
    find: '    async deactivate(req, res) {',
    replace:
      '    async transfer(req, res) {\n' +
      '        const employee = await employees_service_1.employeesService.transfer(req.user.id, req.params[\'id\'], req.body.organizationId);\n' +
      '        (0, response_1.sendSuccess)(res, employee);\n' +
      '    },\n' +
      '    async deactivate(req, res) {',
  },
  // 5. Route. SUPER_ADMIN only — moving people between tenants is above HR
  //    administration, which is scoped to one organization by definition.
  {
    file: `${B}/employees.routes.js`,
    marker: "employeesController.transfer",
    find: '// Admin-only explicit set/reset of an employee\'s login password.',
    replace:
      "// Move an employee to another organization. SUPER_ADMIN only: HR\n" +
      "// administration is scoped to a single tenant by definition.\n" +
      "exports.employeesRouter.post('/:id/transfer', (0, rbac_middleware_1.requireRoles)('SUPER_ADMIN'), (0, validate_middleware_1.validate)(employees_types_1.TransferEmployeeSchema), (0, async_handler_1.asyncHandler)(employees_controller_1.employeesController.transfer));\n" +
      "// Admin-only explicit set/reset of an employee's login password.",
  },
];

let applied = 0;
let skipped = 0;
let failed = 0;
const backedUp = new Set();

for (const e of EDITS) {
  const name = e.file.split('/').pop();
  if (!fs.existsSync(e.file)) {
    console.error(`  FAIL   ${name} — not found`);
    failed++;
    continue;
  }

  const src = fs.readFileSync(e.file, 'utf8');
  const eol = src.includes('\r\n') ? '\r\n' : '\n';
  const N = (t) => t.split('\n').join(eol);

  if (src.includes(N(e.marker))) {
    console.log(`  SKIP   ${name} — "${e.marker}" already present`);
    skipped++;
    continue;
  }

  const find = N(e.find);
  const hits = src.split(find).length - 1;
  if (hits !== 1) {
    console.error(`  FAIL   ${name} — anchor matched ${hits} times, expected 1`);
    failed++;
    continue;
  }

  if (DRY) {
    console.log(`  WOULD  ${name} — ${e.marker}`);
    applied++;
    continue;
  }

  if (!backedUp.has(e.file)) {
    fs.copyFileSync(e.file, `${e.file}.bak`);
    backedUp.add(e.file);
  }
  fs.writeFileSync(e.file, src.replace(find, N(e.replace)), 'utf8');
  console.log(`  OK     ${name} — ${e.marker}`);
  applied++;
}

console.log('');
if (DRY) {
  console.log(`dry run: ${applied} would apply, ${skipped} already done, ${failed} failed`);
} else {
  const checks = [
    [`${B}/employees.types.js`, 'TransferEmployeeSchema'],
    [`${B}/employees.service.js`, 'async transfer(actorId, id, targetOrganizationId)'],
    [`${B}/employees.controller.js`, 'async transfer(req, res)'],
    [`${B}/employees.routes.js`, 'employeesController.transfer'],
  ];
  let ok = 0;
  for (const [f, needle] of checks) {
    if (fs.existsSync(f) && fs.readFileSync(f, 'utf8').includes(needle)) ok++;
  }
  console.log(`verify: ${ok}/4 files carry the change`);
  console.log(`applied=${applied} skipped=${skipped} failed=${failed}`);
  if (ok === 4 && failed === 0) {
    console.log('');
    console.log('Next: restart / redeploy the API, then in the app open any');
    console.log('employee with NO reviews and use "Move to another organization".');
    console.log('An employee WITH reviews is refused with a 409 explaining why.');
    console.log('');
    console.log('Restore:');
    for (const f of backedUp) {
      const n = f.split('/').pop();
      console.log(`  copy ${n}.bak ${n}`);
    }
  }
}

process.exit(failed > 0 ? 1 : 0);
