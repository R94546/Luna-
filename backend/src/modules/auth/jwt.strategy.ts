import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PassportStrategy } from '@nestjs/passport';
import { UserRole } from '@prisma/client';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { JwtPayload } from './dto/auth.dto';

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy, 'jwt') {
  constructor(config: ConfigService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: config.getOrThrow<string>('JWT_SECRET'),
    });
  }

  /**
   * Возвращаемое значение попадает в request.user.
   *
   * В базу здесь не ходим: это +1 запрос на КАЖДЫЙ вызов API ради данных,
   * которые уже подписаны в токене. Цена — отключённый пользователь живёт
   * до истечения access-токена (15 минут). Приемлемо: refresh он не получит,
   * потому что там проверка isActive есть.
   */
  validate(payload: JwtPayload): AuthUser {
    if (!payload.sub || !payload.companyId) {
      throw new UnauthorizedException('Некорректный токен');
    }

    return {
      userId: payload.sub,
      companyId: payload.companyId,
      role: payload.role as UserRole,
    };
  }
}
