import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/constants.dart';
import '../api/api_client.dart';

class AuthProvider with ChangeNotifier {
  AuthProvider() : _storage = const FlutterSecureStorage() {
    _loadStored();
  }

  final FlutterSecureStorage _storage;
  ApiClient? _apiClient;
  ApiClient get api => _apiClient ??= ApiClient(getToken: getToken);

  String? _accessToken;
  String? _userId;
  String? _email;
  String? _name;

  String? get accessToken => _accessToken;
  String? get userId => _userId;
  String? get email => _email;
  String? get name => _name;
  bool get isLoggedIn => _accessToken != null && _accessToken!.isNotEmpty;

  Future<String?> getToken() async {
    return _accessToken ?? await _storage.read(key: kStorageKeyAccessToken);
  }

  Future<void> _loadStored() async {
    _accessToken = await _storage.read(key: kStorageKeyAccessToken);
    _userId = await _storage.read(key: kStorageKeyUserId);
    _email = await _storage.read(key: kStorageKeyEmail);
    _name = await _storage.read(key: kStorageKeyName);
    notifyListeners();
  }

  Future<void> saveFromCallback(Map<String, String> params) async {
    final token = params['access_token'];
    if (token == null || token.isEmpty) return;
    _accessToken = token;
    _userId = params['user_id'];
    _email = params['email'];
    _name = params['name'];
    await _storage.write(key: kStorageKeyAccessToken, value: token);
    if (_userId != null) await _storage.write(key: kStorageKeyUserId, value: _userId);
    if (_email != null) await _storage.write(key: kStorageKeyEmail, value: _email);
    if (_name != null) await _storage.write(key: kStorageKeyName, value: _name);
    notifyListeners();
  }

  /// Native Google Sign-In (uses id_token and backend /auth/google/token). Returns error message or null on success.
  Future<String?> signInWithGoogle() async {
    if (kGoogleWebClientId.isEmpty) {
      return 'Не задан Google Web Client ID (lib/core/constants.dart)';
    }
    try {
      final googleSignIn = GoogleSignIn(
        serverClientId: kGoogleWebClientId,
        scopes: ['email', 'profile', 'openid'],
      );
      final account = await googleSignIn.signIn();
      if (account == null) return null; // пользователь отменил
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        return 'Google не вернул токен';
      }
      final result = await api.loginWithGoogleIdToken(idToken);
      if (result == null) return 'Ошибка входа на сервере';
      await saveFromCallback(result);
      await googleSignIn.signOut(); // we only needed the token
      return null;
    } catch (e, st) {
      debugPrint('signInWithGoogle: $e $st');
      return e.toString();
    }
  }

  Future<void> logout() async {
    _accessToken = _userId = _email = _name = null;
    await _storage.delete(key: kStorageKeyAccessToken);
    await _storage.delete(key: kStorageKeyUserId);
    await _storage.delete(key: kStorageKeyEmail);
    await _storage.delete(key: kStorageKeyName);
    notifyListeners();
  }

  String get googleLoginUrl => api.googleLoginUrl;
}
