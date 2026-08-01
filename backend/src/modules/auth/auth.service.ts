import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { Prisma, UserRole } from '@prisma/client';
import * as argon2 from 'argon2';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { AppException, Errors } from '../../common/filters/app.exception';
import { PrismaService } from '../../prisma/prisma.service';
import { ChangePasswordDto, JwtPayload, LoginDto, RegisterDto, TokenPair } from './dto/auth.dto';

/**
 * Стартовые данные новой компании: без них первый экран приложения пустой.
 * На узбекском — этими справочниками пользуются в цехе, а не в офисе.
 */
const SEED_EXPENSE_CATEGORIES = [
  'Ijara',
  "Kommunal to'lovlar",
  'Materiallar',
  'Transport',
  'Boshqa xarajatlar',
];
const SEED_OPERATIONS = ['Bichish', 'Tikish', 'Qolipga tortish', 'Qadoqlash'];
const TRIAL_DAYS = 14;

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}

  /**
   * Регистрация компании + владельца + стартовых справочников — одной транзакцией.
   * Если что-то упадёт на середине, не должно остаться компании без владельца
   * или владельца без кассы.
   */
  async register(dto: RegisterDto, userAgent?: string) {
    const exists = await this.prisma.user.findUnique({ where: { phone: dto.phone } });
    if (exists) {
      throw new AppException(409, 'PHONE_TAKEN', 'error.phone_taken');
    }

    const passwordHash = await argon2.hash(dto.password, { type: argon2.argon2id });

    const { user, company } = await this.prisma.$transaction(async (tx) => {
      const company = await tx.company.create({
        data: {
          name: dto.companyName,
          slug: await this.uniqueSlug(tx, dto.companyName),
          phone: dto.phone,
          subscriptionEndsAt: new Date(Date.now() + TRIAL_DAYS * 86_400_000),
        },
      });

      const user = await tx.user.create({
        data: {
          companyId: company.id,
          phone: dto.phone,
          fullName: dto.fullName,
          passwordHash,
          role: UserRole.OWNER,
        },
      });

      // Транзакционный клиент не проходит через tenant-middleware
      // (контекст ещё не установлен), поэтому companyId проставляем явно.
      await tx.cashAccount.create({
        data: { companyId: company.id, name: 'Asosiy kassa', isDefault: true },
      });

      await tx.expenseCategory.createMany({
        data: SEED_EXPENSE_CATEGORIES.map((name) => ({
          companyId: company.id,
          name,
          isSystem: true,
        })),
      });

      await tx.operation.createMany({
        data: SEED_OPERATIONS.map((name, i) => ({
          companyId: company.id,
          name,
          sortOrder: i,
        })),
      });

      return { user, company };
    });

    const tokens = await this.issueTokens(user.id, company.id, user.role, userAgent);

    this.logger.log(`Зарегистрирована компания «${company.name}» (${company.id})`);

    return {
      ...tokens,
      user: this.publicUser(user),
      company: {
        id: company.id,
        name: company.name,
        plan: company.plan,
        subscriptionEndsAt: company.subscriptionEndsAt,
      },
    };
  }

  async login(dto: LoginDto, userAgent?: string) {
    const user = await this.prisma.user.findUnique({
      where: { phone: dto.phone },
      include: { company: true },
    });

    // Одинаковая ошибка для «нет пользователя» и «неверный пароль»:
    // иначе форма логина превращается в справочник зарегистрированных номеров.
    if (!user || !user.isActive || user.deletedAt) throw Errors.invalidCredentials();

    const valid = await argon2.verify(user.passwordHash, dto.password);
    if (!valid) throw Errors.invalidCredentials();

    if (!user.companyId || !user.company) {
      throw new AppException(403, 'NO_COMPANY', 'error.no_company');
    }

    await this.prisma.user.update({
      where: { id: user.id },
      data: { lastLoginAt: new Date() },
    });

    const tokens = await this.issueTokens(user.id, user.companyId, user.role, userAgent);

    return {
      ...tokens,
      user: this.publicUser(user),
      company: {
        id: user.company.id,
        name: user.company.name,
        plan: user.company.plan,
        subscriptionEndsAt: user.company.subscriptionEndsAt,
      },
    };
  }

  /**
   * Ротация refresh-токена.
   *
   * Старый токен отзывается сразу. Если кто-то попытается использовать его
   * повторно — значит токен украли и им уже воспользовались; отзываем всю
   * семью токенов, законный пользователь разлогинится и войдёт заново.
   */
  async refresh(refreshToken: string, userAgent?: string): Promise<TokenPair> {
    const tokenHash = this.hashToken(refreshToken);

    const stored = await this.prisma.refreshToken.findUnique({
      where: { tokenHash },
      include: { user: true },
    });

    if (!stored) {
      throw new AppException(401, 'INVALID_REFRESH_TOKEN', 'error.invalid_refresh_token');
    }

    if (stored.revokedAt) {
      await this.prisma.refreshToken.updateMany({
        where: { familyId: stored.familyId, revokedAt: null },
        data: { revokedAt: new Date() },
      });

      this.logger.warn(
        `Повторное использование отозванного токена, семья ${stored.familyId} отозвана целиком`,
      );

      throw new AppException(401, 'TOKEN_REUSED', 'error.token_reused');
    }

    if (stored.expiresAt < new Date()) {
      throw new AppException(401, 'REFRESH_TOKEN_EXPIRED', 'error.refresh_token_expired');
    }

    const { user } = stored;
    if (!user.isActive || user.deletedAt || !user.companyId) {
      throw new AppException(401, 'USER_INACTIVE', 'error.user_inactive');
    }

    await this.prisma.refreshToken.update({
      where: { id: stored.id },
      data: { revokedAt: new Date() },
    });

    return this.issueTokens(user.id, user.companyId, user.role, userAgent, stored.familyId);
  }

  async logout(refreshToken: string): Promise<void> {
    await this.prisma.refreshToken.updateMany({
      where: { tokenHash: this.hashToken(refreshToken), revokedAt: null },
      data: { revokedAt: new Date() },
    });
  }

  async me(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      include: { company: true },
    });

    if (!user) throw Errors.notFound('Пользователь');

    return {
      user: this.publicUser(user),
      company: user.company && {
        id: user.company.id,
        name: user.company.name,
        plan: user.company.plan,
        status: user.company.status,
        subscriptionEndsAt: user.company.subscriptionEndsAt,
        currency: user.company.currency,
        timezone: user.company.timezone,
        workLogAutoApprove: user.company.workLogAutoApprove,
      },
    };
  }

  async changePassword(userId: string, dto: ChangePasswordDto): Promise<void> {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw Errors.notFound('Пользователь');

    const valid = await argon2.verify(user.passwordHash, dto.currentPassword);
    if (!valid) {
      throw new AppException(400, 'WRONG_PASSWORD', 'error.wrong_password');
    }

    await this.prisma.$transaction([
      this.prisma.user.update({
        where: { id: userId },
        data: { passwordHash: await argon2.hash(dto.newPassword, { type: argon2.argon2id }) },
      }),
      // Смена пароля завершает все прочие сессии — иначе украденный токен
      // продолжит работать ещё 30 дней после того, как пароль сменили из-за кражи.
      this.prisma.refreshToken.updateMany({
        where: { userId, revokedAt: null },
        data: { revokedAt: new Date() },
      }),
    ]);
  }

  // ── Внутреннее ────────────────────────────────────────────────────────────

  private async issueTokens(
    userId: string,
    companyId: string,
    role: UserRole,
    userAgent?: string,
    familyId?: string,
  ): Promise<TokenPair> {
    const payload: JwtPayload = { sub: userId, companyId, role };
    const accessToken = await this.jwt.signAsync(payload);

    // Случайная строка, а не JWT: refresh должен отзываться, а подписанный
    // токен отозвать нельзя — только вести список отозванных, что то же самое,
    // но сложнее.
    const refreshToken = randomBytes(32).toString('hex');
    const days = this.config.get<number>('JWT_REFRESH_TTL_DAYS', 30);

    await this.prisma.refreshToken.create({
      data: {
        userId,
        tokenHash: this.hashToken(refreshToken),
        familyId: familyId ?? randomUUID(),
        expiresAt: new Date(Date.now() + days * 86_400_000),
        userAgent: userAgent?.slice(0, 255),
      },
    });

    return { accessToken, refreshToken };
  }

  /** В БД хранится только хеш: утечка таблицы не даёт войти ни в один аккаунт. */
  private hashToken(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }

  private async uniqueSlug(tx: Prisma.TransactionClient, name: string): Promise<string> {
    const base =
      name
        .toLowerCase()
        .replace(/[^a-z0-9Ѐ-ӿ]+/g, '-')
        .replace(/^-+|-+$/g, '')
        .slice(0, 48) || 'company';

    for (let attempt = 0; attempt < 10; attempt++) {
      const candidate = attempt === 0 ? base : `${base}-${attempt}`;
      const taken = await tx.company.findUnique({ where: { slug: candidate } });
      if (!taken) return candidate;
    }

    return `${base}-${randomBytes(3).toString('hex')}`;
  }

  private publicUser(user: {
    id: string;
    fullName: string;
    phone: string;
    role: UserRole;
    companyId: string | null;
  }) {
    return {
      id: user.id,
      fullName: user.fullName,
      phone: user.phone,
      role: user.role,
      companyId: user.companyId,
    };
  }
}
