import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
} from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { Roles } from '../../common/decorators/roles.decorator';
import { ZodValidationPipe } from '../../common/pipes/zod-validation.pipe';
import { CostingService } from './costing.service';
import {
  CalculateDto,
  CreateCalculationDto,
  ListCalculationsDto,
  calculateSchema,
  createCalculationSchema,
  listCalculationsSchema,
} from './dto/costing.dto';

@Controller('costing')
@Roles(UserRole.ADMIN)
export class CostingController {
  constructor(private readonly costing: CostingService) {}

  /**
   * Расчёт без сохранения.
   *
   * Отдельно от `POST /costing` намеренно: владелец крутит маржу туда-сюда,
   * глядя на цену, и каждое движение ползунка не должно оставлять запись
   * в базе. Поэтому 200, а не 201 — ничего не создано.
   */
  @Post('calculate')
  @HttpCode(200)
  calculate(@Body(new ZodValidationPipe(calculateSchema)) dto: CalculateDto) {
    return this.costing.calculate(dto);
  }

  @Get()
  findAll(@Query(new ZodValidationPipe(listCalculationsSchema)) query: ListCalculationsDto) {
    return this.costing.findAll(query);
  }

  @Get(':id')
  findOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.costing.findOne(id);
  }

  @Post()
  create(@Body(new ZodValidationPipe(createCalculationSchema)) dto: CreateCalculationDto) {
    return this.costing.create(dto);
  }

  @Post(':id/apply')
  @HttpCode(200)
  apply(@Param('id', ParseUUIDPipe) id: string) {
    return this.costing.apply(id);
  }

  @Delete(':id')
  remove(@Param('id', ParseUUIDPipe) id: string) {
    return this.costing.remove(id);
  }
}
