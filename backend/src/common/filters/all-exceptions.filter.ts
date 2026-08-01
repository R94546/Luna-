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
import { Lang, parseLang, t } from '../i18n/messages';

interface ErrorBody {
  statusCode: number;
  code: string;
  message: string;
  details?: unknown;
  timestamp: string;
  path: string;
}

/** Ключи словаря выглядят как `error.foo` / `validation.bar`. */
const I18N_KEY = /^(error|validation)\.[a-z_]+$/;

/**
 * Единый формат ошибок для всего API.
 *
 * Здесь же происходит перевод: сервисы бросают ключи, а язык известен
 * только на границе HTTP — из заголовка Accept-Language.
 */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger(AllExceptionsFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();

    const lang = parseLang(request.headers['accept-language']);
    const body = this.toErrorBody(exception, request.url, lang);

    if (body.statusCode >= 500) {
      this.logger.error(
        `${request.method} ${request.url} → ${body.statusCode}`,
        exception instanceof Error ? exception.stack : String(exception),
      );
    }

    response.status(body.statusCode).json(body);
  }

  private toErrorBody(exception: unknown, path: string, lang: Lang): ErrorBody {
    const timestamp = new Date().toISOString();

    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const payload = exception.getResponse();

      if (typeof payload === 'object' && payload !== null) {
        const p = payload as Record<string, unknown>;

        return {
          statusCode: status,
          code: (p.code as string) ?? this.defaultCode(status),
          message: this.resolveMessage(p, exception.message, status, lang),
          details: this.translateDetails(p.details, lang),
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
      return { ...this.fromPrisma(exception, lang), timestamp, path };
    }

    // Всё неопознанное — 500 без подробностей наружу: текст ошибки может
    // содержать фрагменты SQL и данные других компаний.
    return {
      statusCode: HttpStatus.INTERNAL_SERVER_ERROR,
      code: 'INTERNAL_ERROR',
      message: t(lang, 'error.internal'),
      timestamp,
      path,
    };
  }

  private resolveMessage(
    payload: Record<string, unknown>,
    fallback: string,
    status: number,
    lang: Lang,
  ): string {
    if (typeof payload.messageKey === 'string') {
      return t(lang, payload.messageKey, payload.params as Record<string, unknown> | undefined);
    }

    // Исключения самого Nest (ThrottlerException, UnauthorizedException и т.п.)
    // ключей не знают — подставляем перевод по HTTP-статусу.
    const byStatus: Record<number, string> = {
      401: 'error.unauthorized',
      403: 'error.forbidden_role',
      404: 'error.not_found',
      429: 'error.too_many_requests',
    };

    if (byStatus[status]) return t(lang, byStatus[status], { entity: '' }).trim();

    const message = payload.message;
    if (Array.isArray(message)) return message.join('; ');

    return (message as string) ?? fallback;
  }

  /** Переводит значения в details.fields — туда ZodValidationPipe кладёт ключи. */
  private translateDetails(details: unknown, lang: Lang): unknown {
    if (!details || typeof details !== 'object') return details;

    const d = details as Record<string, unknown>;
    if (!d.fields || typeof d.fields !== 'object') return details;

    const fields = Object.fromEntries(
      Object.entries(d.fields as Record<string, string>).map(([field, value]) => [
        field,
        I18N_KEY.test(value) ? t(lang, value) : value,
      ]),
    );

    return { ...d, fields };
  }

  private fromPrisma(
    e: Prisma.PrismaClientKnownRequestError,
    lang: Lang,
  ): Pick<ErrorBody, 'statusCode' | 'code' | 'message' | 'details'> {
    const target = (e.meta?.target as string[] | undefined)?.join(', ');

    switch (e.code) {
      case 'P2002': // нарушение уникальности
        return {
          statusCode: 409,
          code: 'DUPLICATE_VALUE',
          message: target
            ? t(lang, 'error.duplicate', { field: target })
            : t(lang, 'error.duplicate_generic'),
          details: { fields: e.meta?.target },
        };

      case 'P2025': // запись не найдена
        return {
          statusCode: 404,
          code: 'NOT_FOUND',
          message: t(lang, 'error.not_found', { entity: '' }).trim(),
        };

      case 'P2003': // нарушение внешнего ключа
        return {
          statusCode: 422,
          code: 'RELATED_RECORD_MISSING',
          message: t(lang, 'error.related_missing'),
          details: { field: e.meta?.field_name },
        };

      default:
        return {
          statusCode: 500,
          code: 'DATABASE_ERROR',
          message: t(lang, 'error.database'),
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
