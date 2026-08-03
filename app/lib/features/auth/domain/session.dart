import '../data/auth_dto.dart';
import 'user_role.dart';

/// Текущая сессия — то, к чему обращается UI.
///
/// Отдельно от DTO: приложению нужна роль как перечисление, а не строка,
/// и завязывать роутер на сырой JSON значит ловить опечатки в рантайме.
class Session {
  const Session({
    required this.userId,
    required this.fullName,
    required this.phone,
    required this.role,
    this.companyName,
  });

  final String userId;
  final String fullName;
  final String phone;
  final UserRole role;
  final String? companyName;

  factory Session.fromDto(UserDto user, [CompanyDto? company]) => Session(
    userId: user.id,
    fullName: user.fullName,
    phone: user.phone,
    role: UserRole.parse(user.role),
    companyName: company?.name,
  );
}
