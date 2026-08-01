import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { Roles } from '../../common/decorators/roles.decorator';
import { ZodValidationPipe } from '../../common/pipes/zod-validation.pipe';
import {
  CreatePieceRateDto,
  ListPieceRatesDto,
  ResolveRateDto,
  createPieceRateSchema,
  listPieceRatesSchema,
  resolveRateSchema,
} from './dto/piece-rate.dto';
import { PieceRatesService } from './piece-rates.service';

@Controller('piece-rates')
@Roles(UserRole.ADMIN)
export class PieceRatesController {
  constructor(private readonly rates: PieceRatesService) {}

  @Get()
  findAll(@Query(new ZodValidationPipe(listPieceRatesSchema)) query: ListPieceRatesDto) {
    return this.rates.findAll(query);
  }

  /** Какая ставка сработает — нужен интерфейсу до записи выработки. */
  @Get('resolve')
  async resolve(@Query(new ZodValidationPipe(resolveRateSchema)) query: ResolveRateDto) {
    return { rate: (await this.rates.resolveRate(query)).toString() };
  }

  @Post()
  create(@Body(new ZodValidationPipe(createPieceRateSchema)) dto: CreatePieceRateDto) {
    return this.rates.create(dto);
  }

  @Delete(':id')
  @Roles(UserRole.OWNER)
  remove(@Param('id', ParseUUIDPipe) id: string) {
    return this.rates.remove(id);
  }
}
