import { Controller, Get } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { Roles } from '../../common/decorators/roles.decorator';
import { CashService } from './cash.service';

@Controller('cash')
@Roles(UserRole.ACCOUNTANT)
export class CashController {
  constructor(private readonly cash: CashService) {}

  @Get('accounts')
  findAllAccounts() {
    return this.cash.findAllAccounts();
  }
}
