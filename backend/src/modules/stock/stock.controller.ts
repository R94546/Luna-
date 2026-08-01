import { Body, Controller, Get, Post, Query } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { Roles } from '../../common/decorators/roles.decorator';
import { ZodValidationPipe } from '../../common/pipes/zod-validation.pipe';
import {
  CreateMovementDto,
  ListMovementsDto,
  createMovementSchema,
  listMovementsSchema,
} from './dto/stock.dto';
import { StockService } from './stock.service';

@Controller('stock')
@Roles(UserRole.ADMIN)
export class StockController {
  constructor(private readonly stock: StockService) {}

  @Get('movements')
  findMovements(@Query(new ZodValidationPipe(listMovementsSchema)) query: ListMovementsDto) {
    return this.stock.findMovements(query);
  }

  @Post('movements')
  createMovement(
    @Body(new ZodValidationPipe(createMovementSchema)) dto: CreateMovementDto,
    @CurrentUser() user: AuthUser,
  ) {
    return this.stock.createMovement(dto, user.userId);
  }
}
