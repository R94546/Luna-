import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'notification_dto.freezed.dart';
part 'notification_dto.g.dart';

@freezed
class NotificationDto with _$NotificationDto {
  const factory NotificationDto({
    required String id,
    required String type,
    required String title,
    required String body,
    required bool isRead,
    required DateTime createdAt,
  }) = _NotificationDto;

  const NotificationDto._();

  factory NotificationDto.fromJson(Map<String, dynamic> json) =>
      _$NotificationDtoFromJson(json);

  /// Иконка по типу: в ленте вперемешку остатки, сроки и зарплата,
  /// и глазом их проще различать по значку, чем по заголовку.
  IconData get icon => switch (type) {
    'LOW_STOCK' => Icons.inventory_2_outlined,
    'ORDER_OVERDUE' => Icons.schedule_outlined,
    'WORK_LOG_PENDING' => Icons.assignment_outlined,
    'WORK_LOG_ANOMALY' => Icons.warning_amber_outlined,
    'PAYROLL_READY' => Icons.payments_outlined,
    _ => Icons.notifications_outlined,
  };
}

@freezed
class NotificationsPageDto with _$NotificationsPageDto {
  const factory NotificationsPageDto({
    required List<NotificationDto> items,
    required int unread,
  }) = _NotificationsPageDto;

  factory NotificationsPageDto.fromJson(Map<String, dynamic> json) =>
      _$NotificationsPageDtoFromJson(json);
}
