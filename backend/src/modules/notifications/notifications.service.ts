import { Injectable, Logger } from '@nestjs/common';
import { NotificationType, Prisma } from '@prisma/client';
import { Errors } from '../../common/filters/app.exception';
import { PrismaService } from '../../prisma/prisma.service';
import { requireTenant } from '../../prisma/tenant-context';
import { ListNotificationsDto, PushTokenDto } from './dto/notification.dto';

@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Лента пользователя: адресованные лично плюс общие для компании
   * (`userId = null` — «низкий остаток» касается всех, кто ведёт склад).
   */
  async findAll(userId: string, dto: ListNotificationsDto) {
    const where: Prisma.NotificationWhereInput = {
      OR: [{ userId }, { userId: null }],
      ...(dto.unreadOnly ? { isRead: false } : {}),
    };

    const [items, unread] = await Promise.all([
      this.prisma.notification.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        take: dto.limit,
      }),
      this.prisma.notification.count({
        where: { OR: [{ userId }, { userId: null }], isRead: false },
      }),
    ]);

    return { items, unread };
  }

  async markRead(id: string, userId: string) {
    const notification = await this.prisma.notification.findFirst({
      where: { id, OR: [{ userId }, { userId: null }] },
    });

    if (!notification) throw Errors.notFound('Bildirishnoma');

    return this.prisma.notification.update({ where: { id }, data: { isRead: true } });
  }

  async markAllRead(userId: string) {
    const result = await this.prisma.notification.updateMany({
      where: { OR: [{ userId }, { userId: null }], isRead: false },
      data: { isRead: true },
    });

    return { updated: result.count };
  }

  /**
   * Создаёт уведомление, если такого же непрочитанного ещё нет.
   *
   * Крон ходит раз в час, а остаток остаётся низким неделями — без этой
   * проверки к пятнице в ленте будет сорок одинаковых строк, и настоящее
   * уведомление в них потеряется.
   */
  async createOnce(input: {
    type: NotificationType;
    title: string;
    body: string;
    payload?: Record<string, Prisma.InputJsonValue>;
    dedupeKey: string;
  }): Promise<boolean> {
    const { companyId } = requireTenant();

    const existing = await this.prisma.notification.findFirst({
      where: {
        type: input.type,
        isRead: false,
        payload: { path: ['key'], equals: input.dedupeKey },
      },
    });

    if (existing) return false;

    await this.prisma.notification.create({
      data: {
        companyId,
        type: input.type,
        title: input.title,
        body: input.body,
        payload: { ...(input.payload ?? {}), key: input.dedupeKey },
      },
    });

    return true;
  }

  /**
   * Регистрация устройства для push.
   *
   * Токен привязывается к последнему вошедшему: телефон переходит от мастера
   * к мастеру, и оставить старую привязку значит слать уведомления цеха
   * человеку, который уже уволился.
   *
   * Отправка push пока не подключена — для неё нужны ключи FCM. Токены
   * копятся, чтобы включение не требовало обновлять приложение.
   */
  async savePushToken(userId: string, dto: PushTokenDto) {
    await this.prisma.pushToken.upsert({
      where: { token: dto.token },
      create: { userId, token: dto.token, platform: dto.platform },
      update: { userId, platform: dto.platform },
    });

    return { ok: true };
  }
}
