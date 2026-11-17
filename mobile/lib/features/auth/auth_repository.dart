import '../../core/network/api_client.dart';
import '../../core/network/api_envelope.dart';
import 'auth_dto.dart';

class AuthRepository {
  AuthRepository(this.api);
  final ApiClient api;
  Future<AuthData> login(LoginRequest body) async =>
      AuthData.fromJson((await api.post('/auth/login', body.toJson())).requiredData);
  Future<AuthData> register(RegisterRequest body) async =>
      AuthData.fromJson((await api.post('/auth/register', body.toJson())).requiredData);
  Future<UserDto> me() async =>
      UserDto.fromJson((await api.get('/me', authenticated: true)).requiredData);
  Future<ApiMeta> health() async {
    final response = await api.get('/health');
    if (response.requiredData['status'] != 'ok') {
      throw const ApiErrorEnvelope(
        code: 'INVALID_RESPONSE',
        message: 'Status API tidak valid.',
      );
    }
    return response.meta;
  }
}
