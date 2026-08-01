import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { Request, Response } from 'express';

interface ErrorBody {
  statusCode: number;
  code: string;
  message: string;
  details?: unknown;
  timestamp: string;
  path: string;
}

/**
 * Единый формат ошибок для всего API.
 * Flutter разбирает один контракт вместо трёх разных форм ответа
 * (Nest-исключения, ошибки Prisma, необработанные падения).
 */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger(AllExceptionsFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();

    const body = this.toErrorBody(exception, request.url);

    if (body.statusCode >= 500) {
      this.logger.error(
        `${request.method} ${request.url} → ${body.statusCode}`,
        exception instanceof Error ? exception.stack : String(exception),
      );
    }

    response.status(body.statusCode).json(body);
  }

  private toErrorBody(exception: unknown, path: string): ErrorBody {
    const timestamp = new Date().toISOString();

    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const payload = exception.getResponse();

      if (typeof payload === 'object' && payload !== null) {
        const p = payload as Record<string, unknown>;
        return {
          statusCode: status,
          code: (p.code as string) ?? this.defaultCode(status),
          message: Array.isArray(p.message)
            ? (p.message as string[]).join('; ')
            : ((p.message as string) ?? exception.message),
          details: p.details,
          timestamp,
          path,
        };
      }

      return {
        statusCode: status,
        code: this.defaultCode(status),
        message: String(payload),
        timestamp,
        path,
      };
    }

    if (exception instanceof Prisma.PrismaClientKnownRequestError) {
      return { ...this.fromPrisma(exception), timestamp, path };
    }

    // Всё неопознанное — 500 без подробностей наружу: текст ошибки может
    // содержать фрагменты SQL и данные других компаний.
    return {
      statusCode: HttpStatus.INTERNAL_SERVER_ERROR,
      code: 'INTERNAL_ERROR',
      message: 'Внутренняя ошибка сервера',
      timestamp,
      path,
    };
  }

  private fromPrisma(
    e: Prisma.PrismaClientKnownRequestError,
  ): Pick<ErrorBody, 'statusCode' | 'code' | 'message' | 'details'> {
    const target = (e.meta?.target as string[] | undefined)?.join(', ');

    switch (e.code) {
      case 'P2002': // нарушение уникальности
        return {
          statusCode: 409,
          code: 'DUPLICATE_VALUE',
          message: target
            ? `Запись с таким значением поля «${target}» уже существует`
            : 'Такая запись уже существует',
          details: { fields: e.meta?.target },
        };

      case 'P2025': // запись не найдена
        return {
          statusCode: 404,
          code: 'NOT_FOUND',
          message: 'Запись не найдена',
        };

      case 'P2003': // нарушение внешнего ключа
        return {
          statusCode: 422,
          code: 'RELATED_RECORD_MISSING',
          message: 'Связанная запись не существует',
          details: { field: e.meta?.field_name },
        };

      default:
        return {
          statusCode: 500,
          code: 'DATABASE_ERROR',
          message: 'Ошибка базы данных',
        };
    }
  }

  private defaultCode(status: number): string {
    const map: Record<number, string> = {
      400: 'BAD_REQUEST',
      401: 'UNAUTHORIZED',
      403: 'FORBIDDEN',
      404: 'NOT_FOUND',
      409: 'CONFLICT',
      422: 'UNPROCESSABLE_ENTITY',
      429: 'TOO_MANY_REQUESTS',
    };
    return map[status] ?? 'INTERNAL_ERROR';
  }
}
