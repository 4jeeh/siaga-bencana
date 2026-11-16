class UserDto {
  const UserDto({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    required this.hasZone,
  });
  final String id;
  final String email;
  final String displayName;
  final String role;
  final bool hasZone;
  factory UserDto.fromJson(Map<String, dynamic> json) {
    final role = json['role'] as String;
    if (!['citizen', 'admin'].contains(role)) {
      throw const FormatException('Invalid user role');
    }
    return UserDto(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['display_name'] as String,
      role: role,
      hasZone: json['has_zone'] as bool,
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'display_name': displayName,
    'role': role,
    'has_zone': hasZone,
  };
}

class AuthData {
  const AuthData({
    required this.accessToken,
    required this.expiresAt,
    required this.expiresIn,
    required this.user,
  });
  final String accessToken;
  final DateTime expiresAt;
  final int expiresIn;
  final UserDto user;
  factory AuthData.fromJson(Map<String, dynamic> json) {
    if (json['token_type'] != 'bearer' || json['expires_in'] != 3600) {
      throw const FormatException('Invalid auth response');
    }
    return AuthData(
      accessToken: json['access_token'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
      expiresIn: json['expires_in'] as int,
      user: UserDto.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}

class LoginRequest {
  const LoginRequest(this.email, this.password);
  final String email;
  final String password;
  Map<String, dynamic> toJson() => {
    'email': email.trim().toLowerCase(),
    'password': password,
  };
}

class RegisterRequest extends LoginRequest {
  const RegisterRequest(super.email, super.password, this.displayName);
  final String displayName;
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'display_name': displayName.trim(),
  };
}
