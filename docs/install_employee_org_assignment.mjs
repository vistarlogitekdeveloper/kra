/**
 * Lets a SUPER_ADMIN choose which organisation a NEW employee belongs to.
 *
 * Run with node — not a shell command, not SQL:
 *
 *     node D:\Vistar\krafrontend\docs\install_employee_org_assignment.mjs --dry
 *     node D:\Vistar\krafrontend\docs\install_employee_org_assignment.mjs
 *
 * Idempotent; backs up each file as <name>.bak before writing.
 *
 * ── WHY THIS IS CREATE-ONLY ─────────────────────────────────────────────────
 *
 * `POST /employees` and `PATCH /employees/:id` currently accept no
 * organizationId at all (0 occurrences in either schema), and
 * employees.controller.js passes req.user.organizationId on every call — so a
 * new employee always lands in the CALLER's organisation.
 *
 * This patch changes that for create only. Moving an EXISTING employee is
 * deliberately left impossible, because employees.repository.js `update()` is
 * a strict field whitelist that does not include organizationId — and that is
 * a feature, not an oversight:
 *
 *   reviews, kra_assignments, kra_templates, project_locations and
 *   review_cycles each carry their OWN organization_id, independent of the
 *   employee. Changing only the employee's org strands all of it: their review
 *   history stays with the old tenant and becomes invisible to them, their
 *   manager_id points at someone in another organisation, and their
 *   project_location_id references a site their new tenant does not contain.
 *
 * That is not hypothetical — it happened to VLPL0591 during setup, at a scale
 * of one. Moving a populated employee is a data migration, not a form field,
 * and belongs in SQL where the related rows can be moved in the same
 * transaction (see docs/create_organization_and_assign.sql).
 *
 * ── WHAT CHANGES ────────────────────────────────────────────────────────────
 *
 *   1. employees.types.js       CreateEmployeeSchema gains an optional
 *                               organizationId (zod strips unknown keys, and
 *                               validate() replaces req.body with the parsed
 *                               result, so without this the field never
 *                               reaches the controller)
 *   2. employees.controller.js  resolves the target organisation: a
 *                               SUPER_ADMIN may name another tenant, everyone
 *                               else is pinned to their own
 *   3. employees.service.js     verifies the target organisation exists, so a
 *                               bogus id is a clean 400 rather than a
 *                               foreign-key 500
 *
 * Note the manager check in service.create already compares against the
 * organizationId PARAMETER, so it starts validating the manager against the
 * TARGET tenant for free — exactly the right behaviour.
 */
import fs from 'fs';

const B = 'D:/Vistar/vistar_CRM/src/modules/kra/dist/features/employees';
const DRY = process.argv.includes('--dry');

const EDITS = [
  {
    file: `${B}/employees.types.js`,
    marker: 'organizationId',
    // Anchor on the role line inside CreateEmployeeSchema.
    find: '    role: RoleEnum,\n',
    replace:
      '    role: RoleEnum,\n' +
      '    // Target organisation for a SUPER_ADMIN create. Optional: omitted\n' +
      "    // means \"the caller's own organisation\", which is what every other\n" +
      '    // role gets regardless of what they send. Must be declared here or\n' +
      '    // zod strips it before the controller ever sees it.\n' +
      '    organizationId: zod_1.z.string().min(1).max(64).optional(),\n',
  },
  {
    file: `${B}/employees.controller.js`,
    marker: 'resolveTargetOrganization',
    find:
      'const employees_service_1 = require("./employees.service");\n' +
      'exports.employeesController = {',
    replace:
      'const employees_service_1 = require("./employees.service");\n' +
      'const http_errors_1 = require("../../shared/errors/http-errors");\n' +
      '/**\n' +
      ' * Which organisation a NEW employee belongs to.\n' +
      ' *\n' +
      " * Defaults to the caller's own, which is what every request did before and\n" +
      ' * what every non-super-admin still gets. A SUPER_ADMIN may name a different\n' +
      ' * tenant, which is the only way to create an employee outside the\n' +
      ' * organisation the caller is currently scoped to.\n' +
      ' *\n' +
      ' * Anyone else naming another organisation is REFUSED rather than silently\n' +
      " * pinned: they asked for something they cannot have, and quietly writing the\n" +
      ' * row somewhere else would look like success.\n' +
      ' */\n' +
      'function resolveTargetOrganization(req) {\n' +
      '    const requested = req.body && req.body.organizationId;\n' +
      '    if (!requested || requested === req.user.organizationId) {\n' +
      '        return req.user.organizationId;\n' +
      '    }\n' +
      "    if (req.user.role !== 'SUPER_ADMIN') {\n" +
      '        throw new http_errors_1.ForbiddenError('
      + "'Only a super admin can create an employee in another organization');\n" +
      '    }\n' +
      '    return requested;\n' +
      '}\n' +
      'exports.employeesController = {',
  },
  {
    file: `${B}/employees.controller.js`,
    marker: 'resolveTargetOrganization(req)',
    find:
      'await employees_service_1.employeesService.create(req.user.id, req.user.organizationId, req.body)',
    replace:
      'await employees_service_1.employeesService.create(req.user.id, resolveTargetOrganization(req), req.body)',
  },
  {
    file: `${B}/employees.service.js`,
    marker: 'Organization not found',
    find:
      "        if (input.managerId) {\n" +
      '            const manager = await employees_repository_1.employeesRepository.findById(input.managerId);\n' +
      '            if (!manager || manager.organizationId !== organizationId) {\n' +
      "                throw new http_errors_1.BadRequestError('Manager not found in this organization');\n" +
      '            }\n' +
      '        }\n',
    replace:
      '        // The target organisation is caller-chosen for a SUPER_ADMIN create, so\n' +
      '        // it has to be validated. An unknown id would otherwise surface as a\n' +
      '        // foreign-key violation (500) instead of a clean 400.\n' +
      '        const targetOrg = await database_1.prisma.organization.findUnique({\n' +
      '            where: { id: organizationId },\n' +
      '        });\n' +
      '        if (!targetOrg) {\n' +
      "            throw new http_errors_1.BadRequestError('Organization not found');\n" +
      '        }\n' +
      "        if (input.managerId) {\n" +
      '            const manager = await employees_repository_1.employeesRepository.findById(input.managerId);\n' +
      '            if (!manager || manager.organizationId !== organizationId) {\n' +
      "                throw new http_errors_1.BadRequestError('Manager not found in this organization');\n" +
      '            }\n' +
      '        }\n',
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

  let src = fs.readFileSync(e.file, 'utf8');
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
    console.error(
      `  FAIL   ${name} — anchor matched ${hits} times, expected 1. ` +
        `Patch by hand rather than guessing.`,
    );
    failed++;
    continue;
  }

  if (DRY) {
    console.log(`  WOULD  ${name} — 1 replacement (${e.marker})`);
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

// ── Verify ──────────────────────────────────────────────────────────────────
console.log('');
if (DRY) {
  console.log(`dry run: ${applied} would apply, ${skipped} already done, ${failed} failed`);
} else {
  const checks = [
    [`${B}/employees.types.js`, 'organizationId'],
    [`${B}/employees.controller.js`, 'resolveTargetOrganization(req)'],
    [`${B}/employees.service.js`, 'Organization not found'],
  ];
  let ok = 0;
  for (const [f, needle] of checks) {
    if (fs.existsSync(f) && fs.readFileSync(f, 'utf8').includes(needle)) ok++;
  }
  console.log(`verify: ${ok}/3 files carry the change`);
  console.log(`applied=${applied} skipped=${skipped} failed=${failed}`);

  if (ok === 3 && failed === 0) {
    console.log('');
    console.log('Next: restart / redeploy the API, then as superadmin@vistar.test:');
    console.log('  POST /api/v1/kra/employees  { ..., "organizationId": "<another tenant>" }');
    console.log('  -> 201, and the employee belongs to that tenant.');
    console.log('');
    console.log('Restore if anything misbehaves:');
    for (const f of backedUp) console.log(`  copy ${f.split('/').pop()}.bak ${f.split('/').pop()}`);
  }
}

process.exit(failed > 0 ? 1 : 0);
