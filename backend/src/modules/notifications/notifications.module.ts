import { Module } from '@nestjs/common';
import { DevicesController, NotificationsController } from './notifications.controller';
import { NotificationsCron } from './notifications.cron';
import { NotificationsService } from './notifications.service';

@Module({
  controllers: [NotificationsController, DevicesController],
  providers: [NotificationsService, NotificationsCron],
  exports: [NotificationsService],
})
export class NotificationsModule {}
