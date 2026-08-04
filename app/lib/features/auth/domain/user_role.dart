/// Роли из бэкенда.
///
/// Определяют не только доступ, но и стартовый экран: дашборд помечен
/// `@Roles(UserRole.OWNER)`, и отправить туда мастера значит показать
/// ему 403 сразу после входа.
enum UserRole {
  superadmin,
  owner,
  admin,
  accountant;

  static UserRole parse(String value) {
    return switch (value.toUpperCase()) {
      'SUPERADMIN' => UserRole.superadmin,
      'OWNER' => UserRole.owner,
      'ADMIN' => UserRole.admin,
      'ACCOUNTANT' => UserRole.accountant,
      // Неизвестная роль — самая ограниченная: новая роль на сервере
      // не должна открыть в приложении лишнего.
      _ => UserRole.admin,
    };
  }

  /// Деньги цеха целиком видит только владелец.
  bool get canSeeDashboard =>
      this == UserRole.owner || this == UserRole.superadmin;

  /// Зарплата и касса — владелец и бухгалтер. Мастеру эти эндпоинты
  /// закрыты на бэкенде, и показывать ему разделы значит обещать 403.
  bool get canSeeMoney => canSeeDashboard || this == UserRole.accountant;

  /// Подтверждать выработку могут владелец и мастер, но не бухгалтер:
  /// он ведёт деньги, а не производство.
  bool get canApproveWorkLogs => canSeeDashboard || this == UserRole.admin;

  String get label => switch (this) {
    UserRole.superadmin => 'Суперадмин',
    UserRole.owner => 'Владелец',
    UserRole.admin => 'Мастер',
    UserRole.accountant => 'Бухгалтер',
  };
}
