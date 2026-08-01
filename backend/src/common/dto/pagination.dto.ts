import { z } from 'zod';

export const paginationSchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  search: z.string().trim().min(1).max(120).optional(),
  sort: z.string().regex(/^-?[a-zA-Z]+$/).optional(),
});

export type PaginationDto = z.infer<typeof paginationSchema>;

export const dateRangeSchema = z.object({
  dateFrom: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  dateTo: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
});

export interface PageMeta {
  page: number;
  limit: number;
  total: number;
  totalPages: number;
}

export interface Paginated<T> {
  items: T[];
  meta: PageMeta;
}

export function paginate<T>(items: T[], total: number, dto: PaginationDto): Paginated<T> {
  return {
    items,
    meta: {
      page: dto.page,
      limit: dto.limit,
      total,
      totalPages: Math.max(1, Math.ceil(total / dto.limit)),
    },
  };
}

/** Преобразует `-createdAt` в `{ createdAt: 'desc' }` для Prisma orderBy. */
export function parseSort(
  sort: string | undefined,
  fallback: Record<string, 'asc' | 'desc'>,
): Record<string, 'asc' | 'desc'> {
  if (!sort) return fallback;
  const desc = sort.startsWith('-');
  return { [desc ? sort.slice(1) : sort]: desc ? 'desc' : 'asc' };
}
