import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { Roles } from '../../common/decorators/roles.decorator';
import { PaginationDto, paginationSchema } from '../../common/dto/pagination.dto';
import { ZodValidationPipe } from '../../common/pipes/zod-validation.pipe';
import {
  BulkApproveDto,
  CreateWorkLogDto,
  ListWorkLogsDto,
  RejectDto,
  bulkApproveSchema,
  createWorkLogSchema,
  listWorkLogsSchema,
  rejectSchema,
} from './dto/work-log.dto';
import { WorkLogsService } from './work-logs.service';

@Controller('work-logs')
export class WorkLogsController {
  constructor(private readonly workLogs: WorkLogsService) {}

  @Get()
  findAll(@Query(new ZodValidationPipe(listWorkLogsSchema)) query: ListWorkLogsDto) {
    return this.workLogs.findAll(query);
  }

  // До ':id', иначе "pending" будет разобрано как UUID.
  @Get('pending')
  @Roles(UserRole.ADMIN)
  findPending(@Query(new ZodValidationPipe(paginationSchema)) query: PaginationDto) {
    return this.workLogs.findPending(query);
  }

  @Get(':id')
  findOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.workLogs.findOne(id);
  }

  @Post()
  @Roles(UserRole.ADMIN)
  create(
    @Body(new ZodValidationPipe(createWorkLogSchema)) dto: CreateWorkLogDto,
    @CurrentUser() user: AuthUser,
  ) {
    return this.workLogs.createManual(dto, user.userId);
  }

  @Post('bulk-approve')
  @Roles(UserRole.ADMIN)
  @HttpCode(200)
  bulkApprove(
    @Body(new ZodValidationPipe(bulkApproveSchema)) dto: BulkApproveDto,
    @CurrentUser() user: AuthUser,
  ) {
    return this.workLogs.bulkApprove(dto.ids, user.userId);
  }

  @Post(':id/approve')
  @Roles(UserRole.ADMIN)
  @HttpCode(200)
  approve(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() user: AuthUser) {
    return this.workLogs.approve(id, user.userId);
  }

  @Post(':id/reject')
  @Roles(UserRole.ADMIN)
  @HttpCode(200)
  reject(
    @Param('id', ParseUUIDPipe) id: string,
    @Body(new ZodValidationPipe(rejectSchema)) dto: RejectDto,
    @CurrentUser() user: AuthUser,
  ) {
    return this.workLogs.reject(id, user.userId, dto.reason);
  }

  @Delete(':id')
  @Roles(UserRole.OWNER)
  remove(@Param('id', ParseUUIDPipe) id: string) {
    return this.workLogs.remove(id);
  }
}
