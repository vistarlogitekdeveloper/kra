/**
 * READY TO APPLY — save this file as:
 *   D:\Vistar\vistar_CRM\src\modules\kra\dist\features\organizations\organizations.routes.js
 *
 * Then mount it in  dist/app.js  next to the other routers (see MOUNT below).
 *
 * I could not write it into the backend myself — creating new files under
 * D:\Vistar\vistar_CRM is denied in this session. Everything here was written
 * against your actual conventions, read from the module:
 *   - router shape / guard style      features/locations/locations.routes.js
 *   - envelope helpers                shared/utils/response.js  (sendSuccess, sendCreated)
 *   - paging                          shared/utils/pagination.js (buildPaginatedResult)
 *   - typed errors                    shared/errors/http-errors.js (NotFoundError, ConflictError)
 *   - prisma client                   config/database.js (exports.prisma)
 *   - validation                      middleware/validate.middleware.js (validate(schema, 'query'?))
 *
 * ─── MOUNT (one line, in dist/app.js, beside the existing app.use calls) ─────
 *
 *   const organizations_routes_1 = require("./features/organizations/organizations.routes");
 *   app.use(`${env_1.env.API_PREFIX}/organizations`, organizations_routes_1.organizationsRouter);
 *
 * Put the require with the other requires at the top of app.js, and the app.use
 * next to `app.use(`${env_1.env.API_PREFIX}/locations`, ...)`.
 *
 * ─── ENDPOINTS THIS ADDS ─────────────────────────────────────────────────────
 *
 *   GET   /organizations           list + search + employeeCount   SUPER_ADMIN
 *   GET   /organizations/:id       read one                        SUPER_ADMIN
 *   POST  /organizations           create                          SUPER_ADMIN
 *   PATCH /organizations/:id       rename / re-slug / logo         SUPER_ADMIN
 *   POST  /organizations/switch    re-issue JWT for another tenant SUPER_ADMIN
 *
 * There is deliberately NO DELETE. Organization is the parent of employees,
 * locations, review cycles, templates and assignments, and the relation is
 * onDelete: Cascade — a delete would erase review history. Add a deletedAt /
 * isActive column first if you need retirement.
 *
 * WHY /switch EXISTS: organizationId is signed into the JWT at login
 * (auth.service.js issueTokenPair) and every repository scopes by that claim,
 * never by a request parameter. So listing organisations is not enough — a
 * super admin needs a token for the tenant it wants to act on. This is the only
 * mechanism that does not require rewriting every query in the module.
 */
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.organizationsRouter = void 0;
const express_1 = require("express");
const zod_1 = require("zod");
const async_handler_1 = require("../../middleware/async-handler");
const auth_middleware_1 = require("../../middleware/auth.middleware");
const rbac_middleware_1 = require("../../middleware/rbac.middleware");
const validate_middleware_1 = require("../../middleware/validate.middleware");
const database_1 = require("../../config/database");
const response_1 = require("../../shared/utils/response");
const pagination_1 = require("../../shared/utils/pagination");
const http_errors_1 = require("../../shared/errors/http-errors");
// ── Validation ───────────────────────────────────────────────────────────────
// `slug` is @unique and is what a human types / a URL carries, so constrain it
// to a URL-safe shape here rather than letting Postgres reject it later.
const slug = zod_1.z
    .string()
    .min(2)
    .max(64)
    .regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/, 'Lowercase letters, digits and single hyphens, e.g. "vistar-logitek"');
const CreateOrganizationSchema = zod_1.z.object({
    name: zod_1.z.string().min(1).max(150),
    slug: slug,
    logoUrl: zod_1.z.string().url().max(500).nullable().optional(),
});
const UpdateOrganizationSchema = zod_1.z
    .object({
    name: zod_1.z.string().min(1).max(150).optional(),
    slug: slug.optional(),
    logoUrl: zod_1.z.string().url().max(500).nullable().optional(),
})
    // An empty PATCH is a client bug, not a 200 worth returning.
    .refine((v) => Object.keys(v).length > 0, {
    message: 'Provide at least one field to update',
});
const ListOrganizationsQuerySchema = zod_1.z.object({
    page: zod_1.z.coerce.number().int().min(1).optional(),
    limit: zod_1.z.coerce.number().int().min(1).max(200).optional(),
    search: zod_1.z.string().max(150).optional(),
});
const SwitchOrganizationSchema = zod_1.z.object({
    organizationId: zod_1.z.string().min(1).max(64),
});
// ── Shape sent to clients ────────────────────────────────────────────────────
// employeeCount is what makes the list useful ("which tenant has the people?")
// and is why the reads below use _count rather than a bare findMany.
function toDto(org) {
    return {
        id: org.id,
        name: org.name,
        slug: org.slug,
        logoUrl: org.logoUrl ?? null,
        employeeCount: org._count ? org._count.employees : undefined,
        createdAt: org.createdAt,
        updatedAt: org.updatedAt,
    };
}
// Prisma's unique-constraint failure. Surfaced as a typed 409 so the client can
// show "that slug is taken" against the field instead of a raw driver error.
function isUniqueViolation(err) {
    return err && err.code === 'P2002';
}
exports.organizationsRouter = (0, express_1.Router)();
exports.organizationsRouter.use(auth_middleware_1.authenticate);
// Every route here is SUPER_ADMIN. Managing tenants is strictly above HR
// administration: an HR_ADMIN administers people INSIDE one organisation.
//
// NOTE: this is the one router that must NOT scope by req.user.organizationId.
// An organisation-wide admin has to see organisations it is not currently
// "inside", so access is gated purely on the role.
const superAdminOnly = (0, rbac_middleware_1.requireRoles)('SUPER_ADMIN');
exports.organizationsRouter.get('/', superAdminOnly, (0, validate_middleware_1.validate)(ListOrganizationsQuerySchema, 'query'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const page = req.query.page ?? 1;
    const limit = req.query.limit ?? 50;
    const search = req.query.search;
    const where = search
        ? {
            OR: [
                { name: { contains: search, mode: 'insensitive' } },
                { slug: { contains: search, mode: 'insensitive' } },
            ],
        }
        : {};
    const [rows, total] = await Promise.all([
        database_1.prisma.organization.findMany({
            where,
            skip: (page - 1) * limit,
            take: limit,
            orderBy: { name: 'asc' },
            include: { _count: { select: { employees: true } } },
        }),
        database_1.prisma.organization.count({ where }),
    ]);
    const result = (0, pagination_1.buildPaginatedResult)(rows.map(toDto), total, page, limit);
    (0, response_1.sendSuccess)(res, result.data, 200, result.meta);
}));
// NOTE: '/switch' is declared BEFORE '/:id' would otherwise match it. Express
// matches in declaration order, so keep this above the ':id' route if you
// reorder anything.
exports.organizationsRouter.post('/switch', superAdminOnly, (0, validate_middleware_1.validate)(SwitchOrganizationSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const { organizationId } = req.body;
    const org = await database_1.prisma.organization.findUnique({
        where: { id: organizationId },
    });
    if (!org) {
        throw new http_errors_1.NotFoundError('Organization');
    }
    // Required lazily: auth.service pulls in this router's siblings, and a
    // top-level require here would close a cycle through app.js.
    const { authService } = require('../auth/auth.service');
    const tokenPair = await authService.issueTokenPair(req.user.id, req.user.email, req.user.role, organizationId, { ip: req.ip, userAgent: req.get('user-agent') });
    (0, response_1.sendSuccess)(res, { tokenPair, organization: toDto(org) });
}));
exports.organizationsRouter.get('/:id', superAdminOnly, (0, async_handler_1.asyncHandler)(async (req, res) => {
    const org = await database_1.prisma.organization.findUnique({
        where: { id: req.params['id'] },
        include: { _count: { select: { employees: true } } },
    });
    if (!org) {
        throw new http_errors_1.NotFoundError('Organization');
    }
    (0, response_1.sendSuccess)(res, toDto(org));
}));
exports.organizationsRouter.post('/', superAdminOnly, (0, validate_middleware_1.validate)(CreateOrganizationSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    try {
        const org = await database_1.prisma.organization.create({
            data: {
                name: req.body.name,
                slug: req.body.slug,
                logoUrl: req.body.logoUrl ?? null,
            },
        });
        (0, response_1.sendCreated)(res, toDto(org));
    }
    catch (err) {
        if (isUniqueViolation(err)) {
            throw new http_errors_1.ConflictError(`An organization with the slug "${req.body.slug}" already exists`);
        }
        throw err;
    }
}));
exports.organizationsRouter.patch('/:id', superAdminOnly, (0, validate_middleware_1.validate)(UpdateOrganizationSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const id = req.params['id'];
    const existing = await database_1.prisma.organization.findUnique({ where: { id } });
    if (!existing) {
        throw new http_errors_1.NotFoundError('Organization');
    }
    // Only the keys actually supplied — a PATCH that omits logoUrl must not
    // clear it, while an explicit null must.
    const data = {};
    if (req.body.name !== undefined)
        data.name = req.body.name;
    if (req.body.slug !== undefined)
        data.slug = req.body.slug;
    if (req.body.logoUrl !== undefined)
        data.logoUrl = req.body.logoUrl;
    try {
        const org = await database_1.prisma.organization.update({
            where: { id },
            data,
            include: { _count: { select: { employees: true } } },
        });
        (0, response_1.sendSuccess)(res, toDto(org));
    }
    catch (err) {
        if (isUniqueViolation(err)) {
            throw new http_errors_1.ConflictError(`An organization with the slug "${req.body.slug}" already exists`);
        }
        throw err;
    }
}));
//# sourceMappingURL=organizations.routes.js.map
