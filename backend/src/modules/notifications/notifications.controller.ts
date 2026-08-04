import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { ZodValidationPipe } from '../../common/pipes/zod-validation.pipe';
import {
  ListNotificationsDto,
  PushTokenDto,
  listNotificationsSchema,
  pushTokenSchema,
} from './dto/notification.dto';
import { NotificationsService } from './notifications.service';

/** Лента доступна всем ролям: уведомления адресные, чужого в ней нет. */
@Controller('notifications')
export class NotificationsController {
  constructor(private readonly notifications: NotificationsService) {}

  @Get()
  findAll(
    @Query(new ZodValidationPipe(listNotificationsSchema)) query: ListNotificationsDto,
    @CurrentUser() user: AuthUser,
  ) {
    return this.notifications.findAll(user.userId, query);
  }

  @Post('read-all')
  @HttpCode(200)
  markAllRead(@CurrentUser() user: AuthUser) {
    return this.notifications.markAllRead(user.userId);
  }

  // Объявлен ПОСЛЕ 'read-all', иначе Nest примет его за :id и вернёт 400.
  @Post(':id/read')
  @HttpCode(200)
  markRead(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() user: AuthUser) {
    return this.notifications.markRead(id, user.userId);
  }
}

@Controller('devices')
export class DevicesController {
  constructor(private readonly notifications: NotificationsService) {}

  @Post('push-token')
  @HttpCode(200)
  savePushToken(
    @Body(new ZodValidationPipe(pushTokenSchema)) dto: PushTokenDto,
    @CurrentUser() user: AuthUser,
  ) {
    return this.notifications.savePushToken(user.userId, dto);
  }
}
