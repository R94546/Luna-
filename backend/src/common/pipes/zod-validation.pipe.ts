import { ArgumentMetadata, Injectable, PipeTransform } from '@nestjs/common';
import { ZodSchema } from 'zod';
import { AppException } from '../filters/app.exception';

/**
 * Валидация входных данных через zod.
 *
 * Выбран вместо class-validator: схема — это одновременно и рантайм-проверка,
 * и TypeScript-тип (z.infer), поэтому DTO и валидация не могут разъехаться.
 */
@Injectable()
export class ZodValidationPipe implements PipeTransform {
  constructor(private readonly schema: ZodSchema) {}

  transform(value: unknown, _metadata: ArgumentMetadata): unknown {
    const result = this.schema.safeParse(value);

    if (!result.success) {
      const fields: Record<string, string> = {};
      for (const issue of result.error.issues) {
        fields[issue.path.join('.') || '_'] = issue.message;
      }

      // В fields лежат КЛЮЧИ словаря — переводит их AllExceptionsFilter,
      // который единственный знает язык из Accept-Language.
      throw new AppException(400, 'VALIDATION_ERROR', 'error.validation', undefined, { fields });
    }

    return result.data;
  }
}
