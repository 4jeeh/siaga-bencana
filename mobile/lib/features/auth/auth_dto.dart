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
    if (json case {'id': String id, 'email': String email, 'display_name': String name,
        'role': String role, 'has_zone': bool hasZone}
        when role == 'citizen' || role == 'admin') {
      return UserDto(id: id, email: email, displayName: name, role: role, hasZone: hasZone);
    }
    throw const FormatException('Invalid user response');
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
    final expiresIn = json['expires_in'];
    if (json['token_type'] != 'bearer' || expiresIn is! int || expiresIn < 3600 || expiresIn > 604800) {
      throw const FormatException('Invalid auth response');
    }
    if (json case {'access_token': String token, 'expires_at': String expiry,
        'user': Map<String, dynamic> user} when token.trim().isNotEmpty) {
      return AuthData(accessToken: token, expiresAt: DateTime.parse(expiry).toUtc(),
        expiresIn: expiresIn, user: UserDto.fromJson(user));
    }
    throw const FormatException('Invalid auth response');
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
