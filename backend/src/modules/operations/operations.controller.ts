import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Patch, Post, Query, UsePipes } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { Roles } from '../../common/decorators/roles.decorator';
import { ZodValidationPipe } from '../../common/pipes/zod-validation.pipe';
import {
  CreateOperationDto,
  UpdateOperationDto,
  createOperationSchema,
  updateOperationSchema,
} from './dto/operation.dto';
import { OperationsService } from './operations.service';

@Controller('operations')
export class OperationsController {
  constructor(private readonly operations: OperationsService) {}

  @Get()
  findAll(@Query('includeInactive') includeInactive?: string) {
    return this.operations.findAll(includeInactive === 'true');
  }

  @Get(':id')
  findOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.operations.findOne(id);
  }

  @Post()
  @Roles(UserRole.ADMIN)
  @UsePipes(new ZodValidationPipe(createOperationSchema))
  create(@Body() dto: CreateOperationDto) {
    return this.operations.create(dto);
  }

  @Patch(':id')
  @Roles(UserRole.ADMIN)
  update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body(new ZodValidationPipe(updateOperationSchema)) dto: UpdateOperationDto,
  ) {
    return this.operations.update(id, dto);
  }

  // @Roles(OWNER) = только владелец: RolesGuard пропускает OWNER всегда,
  // а ADMIN и ACCOUNTANT не найдут себя в списке и получат 403.
  @Delete(':id')
  @Roles(UserRole.OWNER)
  remove(@Param('id', ParseUUIDPipe) id: string) {
    return this.operations.remove(id);
  }
}
