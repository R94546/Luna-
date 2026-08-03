import { Body, Controller, Get, Post, Query } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { Roles } from '../../common/decorators/roles.decorator';
import { PaginationDto, paginationSchema } from '../../common/dto/pagination.dto';
import { ZodValidationPipe } from '../../common/pipes/zod-validation.pipe';
import {
  CreateAccountDto,
  CreateTransactionDto,
  ListTransactionsDto,
  SummaryDto,
  createAccountSchema,
  createTransactionSchema,
  listTransactionsSchema,
  summarySchema,
} from './dto/cash.dto';
import { CashService } from './cash.service';

@Controller('cash')
@Roles(UserRole.ACCOUNTANT)
export class CashController {
  constructor(private readonly cash: CashService) {}

  @Get('accounts')
  findAllAccounts() {
    return this.cash.findAllAccounts();
  }

  /** Заводить кассы может только владелец: это про его деньги. */
  @Post('accounts')
  @Roles(UserRole.OWNER)
  createAccount(
    @Body(new ZodValidationPipe(createAccountSchema)) dto: CreateAccountDto,
    @CurrentUser() user: AuthUser,
  ) {
    return this.cash.createAccount(dto, user.userId);
  }

  @Get('transactions')
  findAllTransactions(
    @Query(new ZodValidationPipe(listTransactionsSchema.merge(paginationSchema)))
    query: ListTransactionsDto & PaginationDto,
  ) {
    return this.cash.findAllTransactions(query);
  }

  @Post('transactions')
  createTransaction(
    @Body(new ZodValidationPipe(createTransactionSchema)) dto: CreateTransactionDto,
    @CurrentUser() user: AuthUser,
  ) {
    return this.cash.createTransaction(dto, user.userId);
  }

  @Get('summary')
  summary(@Query(new ZodValidationPipe(summarySchema)) query: SummaryDto) {
    return this.cash.summary(query);
  }
}
