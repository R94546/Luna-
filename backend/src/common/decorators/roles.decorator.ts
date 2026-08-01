import { SetMetadata } from '@nestjs/common';
import { UserRole } from '@prisma/client';

export const ROLES_KEY = 'roles';

/**
 * Ограничивает доступ ролями. OWNER имеет доступ всегда — проверка в RolesGuard,
 * чтобы не перечислять его в каждом декораторе.
 *
 * @example @Roles(UserRole.ACCOUNTANT)
 */
export const Roles = (...roles: UserRole[]) => SetMetadata(ROLES_KEY, roles);
