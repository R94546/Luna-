import { Controller, Get, Query } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { Roles } from '../../common/decorators/roles.decorator';
import { ZodValidationPipe } from '../../common/pipes/zod-validation.pipe';
import { AnalyticsService } from './analytics.service';
import {
  DashboardDto,
  ProductionDto,
  ProfitDto,
  TopProductsDto,
  dashboardSchema,
  productionSchema,
  profitSchema,
  topProductsSchema,
} from './dto/analytics.dto';

/**
 * Деньги цеха целиком видит только владелец. Мастеру доступны выпуск
 * и топ моделей — это его работа, а выручка и прибыль не его дело.
 */
@Controller('analytics')
@Roles(UserRole.OWNER)
export class AnalyticsController {
  constructor(private readonly analytics: AnalyticsService) {}

  @Get('dashboard')
  dashboard(@Query(new ZodValidationPipe(dashboardSchema)) query: DashboardDto) {
    return this.analytics.dashboard(query);
  }

  @Get('profit')
  profit(@Query(new ZodValidationPipe(profitSchema)) query: ProfitDto) {
    return this.analytics.profit(query);
  }

  @Get('top-products')
  @Roles(UserRole.ADMIN)
  topProducts(@Query(new ZodValidationPipe(topProductsSchema)) query: TopProductsDto) {
    return this.analytics.topProducts(query);
  }

  @Get('production')
  @Roles(UserRole.ADMIN)
  production(@Query(new ZodValidationPipe(productionSchema)) query: ProductionDto) {
    return this.analytics.production(query);
  }
}
