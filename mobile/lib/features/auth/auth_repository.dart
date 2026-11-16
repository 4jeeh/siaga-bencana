import '../../core/network/api_client.dart';
import '../../core/network/api_envelope.dart';
import 'auth_dto.dart';

class AuthRepository {
  AuthRepository(this.api);
  final ApiClient api;
  Future<AuthData> login(LoginRequest body) async =>
      AuthData.fromJson((await api.post('/auth/login', body.toJson())).data);
  Future<AuthData> register(RegisterRequest body) async =>
      AuthData.fromJson((await api.post('/auth/register', body.toJson())).data);
  Future<UserDto> me() async =>
      UserDto.fromJson((await api.get('/me', authenticated: true)).data);
  Future<ApiMeta> health() async {
    final response = await api.get('/health');
    if (response.data['status'] != 'ok') {
      throw const ApiErrorEnvelope(
        code: 'INVALID_RESPONSE',
        message: 'Status API tidak valid.',
      );
    }
    return response.meta;
  }
}
