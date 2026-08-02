import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

/**
 * Кассы — пока только чтение.
 *
 * Полный модуль кассы (журнал операций, ручные внесения, сводка, расходы)
 * идёт отдельно. Здесь ровно то, без чего не работает выплата зарплаты:
 * клиенту надо показать, из какой кассы платить, и её остаток.
 */
@Injectable()
export class CashService {
  constructor(private readonly prisma: PrismaService) {}

  async findAllAccounts() {
    const accounts = await this.prisma.cashAccount.findMany({
      where: { isActive: true },
      orderBy: [{ isDefault: 'desc' }, { name: 'asc' }],
    });

    return accounts.map((a) => ({
      id: a.id,
      name: a.name,
      type: a.type,
      balance: a.balance.toString(),
      isDefault: a.isDefault,
    }));
  }
}
