import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_dto.freezed.dart';
part 'auth_dto.g.dart';

/// Ответ `/auth/login` и `/auth/register` — они совпадают по формату.
@freezed
class AuthResponse with _$AuthResponse {
  const factory AuthResponse({
    required String accessToken,
    required String refreshToken,
    required UserDto user,
    CompanyDto? company,
  }) = _AuthResponse;

  factory AuthResponse.fromJson(Map<String, dynamic> json) =>
      _$AuthResponseFromJson(json);
}

/// Ответ `/auth/me`: токенов здесь нет, они уже в хранилище.
@freezed
class MeResponse with _$MeResponse {
  const factory MeResponse({required UserDto user, CompanyDto? company}) =
      _MeResponse;

  factory MeResponse.fromJson(Map<String, dynamic> json) =>
      _$MeResponseFromJson(json);
}

@freezed
class UserDto with _$UserDto {
  const factory UserDto({
    required String id,
    required String fullName,
    required String phone,
    required String role,
    String? companyId,
  }) = _UserDto;

  factory UserDto.fromJson(Map<String, dynamic> json) =>
      _$UserDtoFromJson(json);
}

@freezed
class CompanyDto with _$CompanyDto {
  const factory CompanyDto({
    required String id,
    required String name,
    String? plan,
    DateTime? subscriptionEndsAt,
  }) = _CompanyDto;

  factory CompanyDto.fromJson(Map<String, dynamic> json) =>
      _$CompanyDtoFromJson(json);
}
