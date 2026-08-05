import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { Roles } from '../../common/decorators/roles.decorator';
import { ZodValidationPipe } from '../../common/pipes/zod-validation.pipe';
import {
  CreateMaterialDto,
  ListMaterialsDto,
  UpdateMaterialDto,
  createMaterialSchema,
  listMaterialsSchema,
  updateMaterialSchema,
} from './dto/material.dto';
import { MaterialsService } from './materials.service';

/** Справочник ведут владелец и мастер — те же, кто ведёт расценки. */
@Controller('materials')
@Roles(UserRole.ADMIN)
export class MaterialsController {
  constructor(private readonly materials: MaterialsService) {}

  @Get()
  findAll(@Query(new ZodValidationPipe(listMaterialsSchema)) query: ListMaterialsDto) {
    return this.materials.findAll(query);
  }

  @Get(':id')
  findOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.materials.findOne(id);
  }

  @Post()
  create(@Body(new ZodValidationPipe(createMaterialSchema)) dto: CreateMaterialDto) {
    return this.materials.create(dto);
  }

  @Patch(':id')
  update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body(new ZodValidationPipe(updateMaterialSchema)) dto: UpdateMaterialDto,
  ) {
    return this.materials.update(id, dto);
  }

  @Delete(':id')
  remove(@Param('id', ParseUUIDPipe) id: string) {
    return this.materials.remove(id);
  }
}
