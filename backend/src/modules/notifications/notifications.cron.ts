import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from '../../prisma/prisma.service';
import { runWithTenant } from '../../prisma/tenant-context';
import { NotificationsService } from './notifications.service';

/**
 * Сторож: раз в час смотрит, не появилось ли того, о чём владельцу
 * стоит узнать без того, чтобы открывать приложение.
 *
 * Выборки покрыты partial-индексами (`idx_products_low_stock`,
 * `idx_orders_active`) — они читают несколько страниц независимо от того,
 * сколько лет истории накопилось.
 */
@Injectable()
export class NotificationsCron {
  private readonly logger = new Logger(NotificationsCron.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
  ) {}

  @Cron(CronExpression.EVERY_HOUR)
  async run(): Promise<void> {
    // Крон живёт вне HTTP-запроса, и tenant-контекста у него нет: обходим
    // компании явно и на каждую входим отдельно. Без этого middleware
    // изоляции упал бы на первом же запросе.
    const companies = await this.prisma.company.findMany({
      where: { status: 'ACTIVE' },
      select: { id: true },
    });

    for (const company of companies) {
      await runWithTenant({ companyId: company.id }, () => this.checkCompany()).catch(
        (error: Error) =>
          this.logger.error(`Проверка уведомлений для ${company.id}: ${error.message}`),
      );
    }
  }

  private async checkCompany(): Promise<void> {
    await this.lowStock();
    await this.overdueOrders();
  }

  private async lowStock(): Promise<void> {
    const products = await this.prisma.product.findMany({
      where: { isActive: true, deletedAt: null, minStockLevel: { gt: 0 } },
      select: { id: true, sku: true, name: true, stockQuantity: true, minStockLevel: true },
    });

    // Сравнение двух колонок Prisma не выражает в where — отбираем в коде.
    // Список активных моделей у цеха измеряется десятками, не тысячами.
    const low = products.filter((p) => p.stockQuantity <= p.minStockLevel);
    if (low.length === 0) return;

    const names = low
      .slice(0, 3)
      .map((p) => `${p.name} (${p.stockQuantity})`)
      .join(', ');

    await this.notifications.createOnce({
      type: 'LOW_STOCK',
      title: 'Товар заканчивается',
      body: low.length > 3 ? `${names} и ещё ${low.length - 3}` : names,
      payload: { productIds: low.map((p) => p.id) },
      // Ключ по составу списка: пополнили одну модель — уведомление о новом
      // составе придёт, а пока список тот же, повторов не будет.
      dedupeKey: `low-stock:${low.map((p) => p.id).sort().join(',')}`,
    });
  }

  private async overdueOrders(): Promise<void> {
    const today = new Date();
    today.setUTCHours(0, 0, 0, 0);

    const orders = await this.prisma.order.findMany({
      where: {
        status: { notIn: ['ISSUED', 'CANCELLED'] },
        dueDate: { lt: today },
      },
      select: { id: true, orderNumber: true, dueDate: true },
      orderBy: { dueDate: 'asc' },
    });

    if (orders.length === 0) return;

    const numbers = orders
      .slice(0, 3)
      .map((order) => `№${order.orderNumber}`)
      .join(', ');

    await this.notifications.createOnce({
      type: 'ORDER_OVERDUE',
      title: 'Заказы просрочены',
      body:
        orders.length > 3
          ? `${numbers} и ещё ${orders.length - 3}`
          : `${numbers} — срок вышел`,
      payload: { orderIds: orders.map((order) => order.id) },
      dedupeKey: `overdue:${orders.map((order) => order.id).sort().join(',')}`,
    });
  }
}
