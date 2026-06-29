import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(EcoScanApp());
}

typedef CameraLoader = Future<List<CameraDescription>> Function();
typedef PlantIdentifier =
    Future<PlantIdentification> Function(Uint8List imageBytes);

const _configuredApiBaseUrl = String.fromEnvironment('ECOSCAN_API_BASE_URL');
const _defaultApiBaseUrls = ['http://127.0.0.1:8000', 'http://10.0.2.2:8000'];

List<String> resolveApiBaseUrlCandidates({
  String? customBaseUrl,
  String configuredBaseUrl = _configuredApiBaseUrl,
  bool releaseMode = kReleaseMode,
}) {
  final selectedBaseUrl = customBaseUrl?.trim().isNotEmpty == true
      ? customBaseUrl!.trim()
      : configuredBaseUrl.trim();

  if (selectedBaseUrl.isNotEmpty) {
    final uri = Uri.tryParse(selectedBaseUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('A URL da API e invalida: $selectedBaseUrl');
    }
    if (releaseMode && uri.scheme.toLowerCase() != 'https') {
      throw StateError('O release do EcoScan exige uma API HTTPS.');
    }
    return [selectedBaseUrl.replaceFirst(RegExp(r'/+$'), '')];
  }

  if (releaseMode) {
    throw StateError(
      'Defina ECOSCAN_API_BASE_URL com --dart-define para gerar o release.',
    );
  }
  return _defaultApiBaseUrls;
}

abstract interface class TokenStorage {
  Future<String?> readAccessToken();

  Future<String?> readRefreshToken();

  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
  });

  Future<void> clear();
}

class SecureTokenStorage implements TokenStorage {
  const SecureTokenStorage({this.storage = const FlutterSecureStorage()});

  static const _accessTokenKey = 'ecoscan_access_token';
  static const _refreshTokenKey = 'ecoscan_refresh_token';

  final FlutterSecureStorage storage;

  @override
  Future<String?> readAccessToken() => storage.read(key: _accessTokenKey);

  @override
  Future<String?> readRefreshToken() => storage.read(key: _refreshTokenKey);

  @override
  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      storage.write(key: _accessTokenKey, value: accessToken),
      storage.write(key: _refreshTokenKey, value: refreshToken),
    ]);
  }

  @override
  Future<void> clear() async {
    await Future.wait([
      storage.delete(key: _accessTokenKey),
      storage.delete(key: _refreshTokenKey),
    ]);
  }
}

class CapturedPlantResult {
  const CapturedPlantResult({
    required this.imageBytes,
    required this.identification,
  });

  final Uint8List imageBytes;
  final PlantIdentification identification;
}

class PlantIdentification {
  const PlantIdentification({
    required this.success,
    required this.recognized,
    required this.plant,
    required this.alternatives,
    required this.threshold,
  });

  factory PlantIdentification.fromJson(Map<String, dynamic> json) {
    final plantJson = json['plant'];
    final alternativesJson = json['alternatives'];
    return PlantIdentification(
      success: json['success'] == true,
      recognized: json['recognized'] == true,
      plant: plantJson is Map<String, dynamic>
          ? PlantPrediction.fromJson(plantJson)
          : null,
      alternatives: alternativesJson is List
          ? alternativesJson
                .whereType<Map<String, dynamic>>()
                .map(PlantPrediction.fromJson)
                .toList()
          : const [],
      threshold: (json['threshold'] as num?)?.toDouble() ?? 0,
    );
  }

  final bool success;
  final bool recognized;
  final PlantPrediction? plant;
  final List<PlantPrediction> alternatives;
  final double threshold;
}

class PlantPrediction {
  const PlantPrediction({
    required this.classId,
    required this.slug,
    required this.name,
    required this.confidence,
  });

  factory PlantPrediction.fromJson(Map<String, dynamic> json) {
    return PlantPrediction(
      classId: (json['class_id'] as num?)?.toInt() ?? -1,
      slug: json['slug']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Planta',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    );
  }

  final int classId;
  final String slug;
  final String name;
  final double confidence;

  String get confidenceLabel => '${(confidence * 100).toStringAsFixed(0)}%';
}

class PlantIdentificationException implements Exception {
  const PlantIdentificationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PersistedPlantRecord {
  const PersistedPlantRecord({
    required this.id,
    required this.plantName,
    required this.plantSlug,
    required this.confidence,
    required this.recognized,
    required this.createdAt,
    required this.inLibrary,
    required this.imageUrl,
    this.imageBytes,
  });

  factory PersistedPlantRecord.fromJson(Map<String, dynamic> json) {
    return PersistedPlantRecord(
      id: json['id']?.toString() ?? '',
      plantName: json['plant_name']?.toString() ?? 'Planta',
      plantSlug: json['plant_slug']?.toString(),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      recognized: json['recognized'] == true,
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      inLibrary: json['in_library'] == true,
      imageUrl: json['image_url']?.toString() ?? '',
    );
  }

  final String id;
  final String plantName;
  final String? plantSlug;
  final double confidence;
  final bool recognized;
  final DateTime createdAt;
  final bool inLibrary;
  final String imageUrl;
  final Uint8List? imageBytes;

  PersistedPlantRecord withImage(Uint8List bytes) {
    return PersistedPlantRecord(
      id: id,
      plantName: plantName,
      plantSlug: plantSlug,
      confidence: confidence,
      recognized: recognized,
      createdAt: createdAt,
      inLibrary: inLibrary,
      imageUrl: imageUrl,
      imageBytes: bytes,
    );
  }
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
    );
  }

  final String id;
  final String name;
  final String email;
}

class EcoScanApiClient {
  EcoScanApiClient({
    this.baseUrl,
    this.client,
    this.timeout = const Duration(seconds: 90),
    this.accessToken,
    this.refreshToken,
    TokenStorage? tokenStorage,
  }) : tokenStorage = tokenStorage ?? const SecureTokenStorage();

  final String? baseUrl;
  final http.Client? client;
  final Duration timeout;
  String? _resolvedBaseUrl;
  final TokenStorage tokenStorage;
  String? accessToken;
  String? refreshToken;

  Future<EcoScanApiClient> login(String email, String password) async {
    final response = await _sendWithFallback((baseUrl) {
      return http.Request('POST', Uri.parse('$baseUrl/auth/token'))
        ..headers['content-type'] = 'application/x-www-form-urlencoded'
        ..bodyFields = {'username': email, 'password': password};
    });
    _ensureSuccess(response, expectedStatus: 200);
    final decoded = _decodeObject(response);
    final accessToken = decoded['access_token']?.toString();
    final refreshToken = decoded['refresh_token']?.toString();
    if (accessToken == null ||
        accessToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty) {
      throw const PlantIdentificationException(
        'A API nao retornou os tokens da sessao.',
      );
    }
    await _storeTokens(accessToken, refreshToken);
    return this;
  }

  Future<bool> restoreSession() async {
    final accessToken = await tokenStorage.readAccessToken();
    final refreshToken = await tokenStorage.readRefreshToken();
    if (accessToken == null ||
        accessToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty) {
      return false;
    }

    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
    try {
      final response = await _sendAuthenticatedWithFallback((baseUrl) {
        return http.Request('GET', Uri.parse('$baseUrl/users/'));
      });
      _ensureSuccess(response, expectedStatus: 200);
      return true;
    } on PlantIdentificationException {
      await logout();
      return false;
    }
  }

  Future<void> logout() async {
    accessToken = null;
    refreshToken = null;
    await tokenStorage.clear();
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await _sendWithFallback((baseUrl) {
      return http.Request('POST', Uri.parse('$baseUrl/users/'))
        ..headers['content-type'] = 'application/json'
        ..body = jsonEncode({
          'name': name,
          'email': email,
          'password': password,
        });
    });
    _ensureSuccess(response, expectedStatus: 201);
  }

  Future<UserProfile> fetchCurrentUser() async {
    final response = await _sendAuthenticatedWithFallback((baseUrl) {
      return http.Request('GET', Uri.parse('$baseUrl/users/'));
    });
    _ensureSuccess(response, expectedStatus: 200);
    return UserProfile.fromJson(_decodeObject(response));
  }

  Future<UserProfile> updateProfile({
    required String name,
    required String email,
  }) async {
    final response = await _sendAuthenticatedWithFallback((baseUrl) {
      return http.Request('PUT', Uri.parse('$baseUrl/users/'))
        ..headers['content-type'] = 'application/json'
        ..body = jsonEncode({'name': name, 'email': email});
    });
    _ensureSuccess(response, expectedStatus: 200);
    final decoded = _decodeObject(response);
    final userJson = decoded['user'];
    final nextAccessToken = decoded['access_token']?.toString();
    final nextRefreshToken = decoded['refresh_token']?.toString();
    if (userJson is! Map<String, dynamic> ||
        nextAccessToken == null ||
        nextRefreshToken == null) {
      throw const PlantIdentificationException(
        'Resposta invalida ao atualizar o perfil.',
      );
    }
    await _storeTokens(nextAccessToken, nextRefreshToken);
    return UserProfile.fromJson(userJson);
  }

  Future<void> deleteAccount() async {
    final response = await _sendAuthenticatedWithFallback((baseUrl) {
      return http.Request('DELETE', Uri.parse('$baseUrl/users/'));
    });
    _ensureSuccess(response, expectedStatus: 204);
    await logout();
  }

  Future<String?> requestPasswordReset(String email) async {
    final response = await _sendWithFallback((baseUrl) {
      return http.Request(
          'POST',
          Uri.parse('$baseUrl/auth/password-reset/request'),
        )
        ..headers['content-type'] = 'application/json'
        ..body = jsonEncode({'email': email});
    });
    _ensureSuccess(response, expectedStatus: 200);
    return _decodeObject(response)['reset_token']?.toString();
  }

  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async {
    final response = await _sendWithFallback((baseUrl) {
      return http.Request(
          'POST',
          Uri.parse('$baseUrl/auth/password-reset/confirm'),
        )
        ..headers['content-type'] = 'application/json'
        ..body = jsonEncode({'token': token, 'new_password': newPassword});
    });
    _ensureSuccess(response, expectedStatus: 200);
  }

  Future<PlantIdentification> identifyPlant(Uint8List imageBytes) async {
    try {
      final response = await _sendWithFallback((baseUrl) {
        return http.MultipartRequest(
            'POST',
            Uri.parse('$baseUrl/plants/identify').replace(
              queryParameters: {'confidence_threshold': '0.60', 'top_k': '3'},
            ),
          )
          ..files.add(
            http.MultipartFile.fromBytes(
              'image',
              imageBytes,
              filename: 'plant.jpg',
            ),
          );
      });
      _ensureSuccess(response, expectedStatus: 200);
      return PlantIdentification.fromJson(_decodeObject(response));
    } on FormatException {
      throw const PlantIdentificationException(
        'A API retornou uma resposta invalida.',
      );
    }
  }

  Future<PersistedPlantRecord> saveIdentification(
    CapturedPlantResult result,
  ) async {
    _requireAuthentication();
    final prediction = result.identification.plant;
    final bestPrediction =
        prediction ??
        (result.identification.alternatives.isNotEmpty
            ? result.identification.alternatives.first
            : null);
    final response = await _sendAuthenticatedWithFallback((baseUrl) {
      return http.MultipartRequest('POST', Uri.parse('$baseUrl/history'))
        ..fields.addAll({
          'plant_name': result.identification.recognized && prediction != null
              ? prediction.name
              : 'Planta nao reconhecida',
          'plant_slug': bestPrediction?.slug ?? '',
          'confidence': (bestPrediction?.confidence ?? 0).toString(),
          'recognized': result.identification.recognized.toString(),
          'add_to_library': 'true',
        })
        ..files.add(
          http.MultipartFile.fromBytes(
            'image',
            result.imageBytes,
            filename: 'plant.jpg',
          ),
        );
    });
    _ensureSuccess(response, expectedStatus: 201);
    return PersistedPlantRecord.fromJson(
      _decodeObject(response),
    ).withImage(result.imageBytes);
  }

  Future<List<PersistedPlantRecord>> fetchHistory() {
    return _fetchRecords('/history');
  }

  Future<List<PersistedPlantRecord>> fetchLibrary() {
    return _fetchRecords('/library');
  }

  Future<void> deleteHistory(String identificationId) async {
    _requireAuthentication();
    final response = await _sendAuthenticatedWithFallback((baseUrl) {
      return http.Request(
        'DELETE',
        Uri.parse('$baseUrl/history/$identificationId'),
      );
    });
    _ensureSuccess(response, expectedStatus: 204);
  }

  Future<void> removeFromLibrary(String identificationId) async {
    _requireAuthentication();
    final response = await _sendAuthenticatedWithFallback((baseUrl) {
      return http.Request(
        'DELETE',
        Uri.parse('$baseUrl/library/$identificationId'),
      );
    });
    _ensureSuccess(response, expectedStatus: 204);
  }

  List<String> get _baseUrlCandidates {
    final candidates = resolveApiBaseUrlCandidates(customBaseUrl: baseUrl);
    final resolvedBaseUrl = _resolvedBaseUrl;
    if (resolvedBaseUrl == null || candidates.contains(resolvedBaseUrl)) {
      return candidates;
    }
    return [resolvedBaseUrl, ...candidates];
  }

  bool get _canDiscoverLanApi {
    return !kReleaseMode &&
        (baseUrl == null || baseUrl!.trim().isEmpty) &&
        _configuredApiBaseUrl.trim().isEmpty;
  }

  Future<String?> _discoverLanApi() async {
    List<NetworkInterface> interfaces;
    try {
      interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
    } on SocketException {
      return null;
    }

    final ownAddresses = interfaces
        .expand((interface) => interface.addresses)
        .map((address) => address.address)
        .where(_isPrivateIpv4)
        .toSet();
    final prefixes = ownAddresses
        .map((address) => address.substring(0, address.lastIndexOf('.')))
        .toSet();
    if (prefixes.isEmpty) {
      return null;
    }

    final discoveryClient = http.Client();
    try {
      for (final prefix in prefixes) {
        final hosts = [
          for (var host = 1; host <= 254; host++)
            if (!ownAddresses.contains('$prefix.$host')) '$prefix.$host',
        ];
        const batchSize = 32;
        for (var start = 0; start < hosts.length; start += batchSize) {
          final nextEnd = start + batchSize;
          final end = nextEnd < hosts.length ? nextEnd : hosts.length;
          final results = await Future.wait(
            hosts
                .sublist(start, end)
                .map((host) => _probeEcoScanApi(discoveryClient, host)),
          );
          for (final result in results) {
            if (result != null) {
              _resolvedBaseUrl = result;
              return result;
            }
          }
        }
      }
    } finally {
      discoveryClient.close();
    }
    return null;
  }

  Future<String?> _probeEcoScanApi(http.Client client, String host) async {
    final candidate = 'http://$host:8000';
    try {
      final response = await client
          .get(Uri.parse('$candidate/plants/health'))
          .timeout(const Duration(milliseconds: 600));
      if (response.statusCode != 200) {
        return null;
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map<String, dynamic> &&
          body.containsKey('model_loaded') &&
          body.containsKey('status')) {
        return candidate;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  bool _isPrivateIpv4(String address) {
    final parts = address.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null)) {
      return false;
    }
    final first = parts[0]!;
    final second = parts[1]!;
    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }

  Map<String, String> get _authorizationHeaders {
    return {'authorization': 'Bearer $accessToken'};
  }

  Future<List<PersistedPlantRecord>> _fetchRecords(String path) async {
    _requireAuthentication();
    final response = await _sendAuthenticatedWithFallback((baseUrl) {
      return http.Request('GET', Uri.parse('$baseUrl$path'));
    });
    _ensureSuccess(response, expectedStatus: 200);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) {
      throw const PlantIdentificationException(
        'A API retornou uma lista invalida.',
      );
    }

    final records = decoded
        .whereType<Map<String, dynamic>>()
        .map(PersistedPlantRecord.fromJson)
        .toList();
    return Future.wait(records.map(_loadRecordImage));
  }

  Future<PersistedPlantRecord> _loadRecordImage(
    PersistedPlantRecord record,
  ) async {
    if (record.imageUrl.isEmpty) {
      return record;
    }
    final response = await _sendAuthenticatedWithFallback((baseUrl) {
      final imageUri = Uri.parse(record.imageUrl);
      final uri = imageUri.hasScheme
          ? imageUri
          : Uri.parse('$baseUrl${record.imageUrl}');
      return http.Request('GET', uri);
    });
    _ensureSuccess(response, expectedStatus: 200);
    return record.withImage(response.bodyBytes);
  }

  Future<http.Response> _sendWithFallback(
    http.BaseRequest Function(String baseUrl) requestBuilder,
  ) async {
    final activeClient = client ?? http.Client();
    Object? lastNetworkError;
    try {
      final candidateBaseUrls = [..._baseUrlCandidates];
      if (_canDiscoverLanApi && _resolvedBaseUrl == null) {
        final discoveredBaseUrl = await _discoverLanApi();
        if (discoveredBaseUrl != null) {
          candidateBaseUrls
            ..remove(discoveredBaseUrl)
            ..insert(0, discoveredBaseUrl);
        }
      }

      for (final candidateBaseUrl in candidateBaseUrls) {
        final normalizedBaseUrl = candidateBaseUrl.endsWith('/')
            ? candidateBaseUrl.substring(0, candidateBaseUrl.length - 1)
            : candidateBaseUrl;
        try {
          final request = requestBuilder(normalizedBaseUrl);
          final streamedResponse = await activeClient
              .send(request)
              .timeout(timeout);
          if (_canDiscoverLanApi) {
            _resolvedBaseUrl = normalizedBaseUrl;
          }
          return await http.Response.fromStream(streamedResponse);
        } on TimeoutException catch (error) {
          lastNetworkError = error;
        } on http.ClientException catch (error) {
          lastNetworkError = error;
        }
      }
    } finally {
      if (client == null) {
        activeClient.close();
      }
    }

    if (lastNetworkError is TimeoutException) {
      throw const PlantIdentificationException(
        'Tempo esgotado ao chamar a API. '
        'Verifique se o celular e o computador estao na mesma rede Wi-Fi.',
      );
    }
    throw const PlantIdentificationException(
      'Nao foi possivel localizar a API EcoScan na rede local. '
      'Verifique a porta 8000 e o firewall do computador.',
    );
  }

  Future<http.Response> _sendAuthenticatedWithFallback(
    http.BaseRequest Function(String baseUrl) requestBuilder,
  ) async {
    _requireAuthentication();

    Future<http.Response> send() {
      return _sendWithFallback((baseUrl) {
        final request = requestBuilder(baseUrl);
        request.headers.addAll(_authorizationHeaders);
        return request;
      });
    }

    var response = await send();
    if (response.statusCode != 401) {
      return response;
    }

    await _refreshSession();
    response = await send();
    return response;
  }

  Future<void> _refreshSession() async {
    final currentRefreshToken = refreshToken;
    if (currentRefreshToken == null || currentRefreshToken.isEmpty) {
      await logout();
      throw const PlantIdentificationException('Sessao expirada.');
    }

    final response = await _sendWithFallback((baseUrl) {
      return http.Request('POST', Uri.parse('$baseUrl/auth/refresh'))
        ..headers['authorization'] = 'Bearer $currentRefreshToken';
    });
    if (response.statusCode != 200) {
      await logout();
      throw const PlantIdentificationException(
        'Sessao expirada. Entre novamente.',
      );
    }

    final decoded = _decodeObject(response);
    final accessToken = decoded['access_token']?.toString();
    final nextRefreshToken = decoded['refresh_token']?.toString();
    if (accessToken == null ||
        accessToken.isEmpty ||
        nextRefreshToken == null ||
        nextRefreshToken.isEmpty) {
      await logout();
      throw const PlantIdentificationException(
        'Nao foi possivel renovar a sessao.',
      );
    }
    await _storeTokens(accessToken, nextRefreshToken);
  }

  Future<void> _storeTokens(String accessToken, String refreshToken) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
    await tokenStorage.writeTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException();
    }
    return decoded;
  }

  void _ensureSuccess(http.Response response, {required int expectedStatus}) {
    if (response.statusCode != expectedStatus) {
      throw PlantIdentificationException(_errorMessageFrom(response));
    }
  }

  void _requireAuthentication() {
    if (accessToken == null || accessToken!.isEmpty) {
      throw const PlantIdentificationException('Usuario nao autenticado.');
    }
  }

  String _errorMessageFrom(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail != null) {
          return detail.toString();
        }
      }
    } on FormatException {
      // Fall through to the generic status message below.
    }
    return 'Falha na identificacao (HTTP ${response.statusCode}).';
  }
}

class EcoScanApp extends StatelessWidget {
  EcoScanApp({
    super.key,
    this.cameraLoader,
    this.plantIdentifier,
    EcoScanApiClient? apiClient,
  }) : apiClient = apiClient ?? EcoScanApiClient();

  final CameraLoader? cameraLoader;
  final PlantIdentifier? plantIdentifier;
  final EcoScanApiClient apiClient;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EcoScan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.forest,
          primary: AppColors.forest,
          surface: AppColors.page,
        ),
        scaffoldBackgroundColor: AppColors.page,
        fontFamily: 'Serif',
        useMaterial3: true,
      ),
      home: SessionBootstrap(
        cameraLoader: cameraLoader,
        plantIdentifier: plantIdentifier,
        apiClient: apiClient,
      ),
    );
  }
}

class SessionBootstrap extends StatefulWidget {
  const SessionBootstrap({
    super.key,
    required this.apiClient,
    this.cameraLoader,
    this.plantIdentifier,
  });

  final EcoScanApiClient apiClient;
  final CameraLoader? cameraLoader;
  final PlantIdentifier? plantIdentifier;

  @override
  State<SessionBootstrap> createState() => _SessionBootstrapState();
}

class _SessionBootstrapState extends State<SessionBootstrap> {
  bool? _hasSession;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreSession());
  }

  Future<void> _restoreSession() async {
    var hasSession = false;
    try {
      hasSession = await widget.apiClient.restoreSession();
    } catch (_) {
      hasSession = false;
    }
    if (mounted) {
      setState(() => _hasSession = hasSession);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSession = _hasSession;
    if (hasSession == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (hasSession) {
      return EcoHomeShell(
        apiClient: widget.apiClient,
        cameraLoader: widget.cameraLoader,
        plantIdentifier: widget.plantIdentifier,
      );
    }
    return LoginScreen(
      apiClient: widget.apiClient,
      cameraLoader: widget.cameraLoader,
      plantIdentifier: widget.plantIdentifier,
    );
  }
}

class AppColors {
  static const forest = Color(0xFF0D6041);
  static const moss = Color(0xFF5C9147);
  static const page = Color(0xFFF3F3F1);
  static const card = Color(0xFFFFFFFF);
  static const text = Color(0xFF111111);
  static const muted = Color(0xFF607066);
}

class PlantEntry {
  const PlantEntry({
    required this.id,
    required this.name,
    required this.date,
    required this.subtitle,
    required this.palette,
    required this.icon,
    this.imageBytes,
  });

  final String id;
  final String name;
  final String date;
  final String subtitle;
  final List<Color> palette;
  final IconData icon;
  final Uint8List? imageBytes;
}

class LoginScreen extends StatefulWidget {
  LoginScreen({
    super.key,
    this.cameraLoader,
    this.plantIdentifier,
    EcoScanApiClient? apiClient,
  }) : apiClient = apiClient ?? EcoScanApiClient();

  final CameraLoader? cameraLoader;
  final PlantIdentifier? plantIdentifier;
  final EcoScanApiClient apiClient;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Informe email e senha.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final authenticatedClient = await widget.apiClient.login(email, password);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => EcoHomeShell(
            cameraLoader: widget.cameraLoader,
            plantIdentifier: widget.plantIdentifier,
            apiClient: authenticatedClient,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error is PlantIdentificationException
              ? error.message
              : 'Nao foi possivel entrar.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showRegistration() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController(text: _emailController.text);
    final passwordController = TextEditingController();
    final shouldRegister = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Criar conta'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nome'),
                ),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Senha (minimo 8 caracteres)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Criar'),
            ),
          ],
        );
      },
    );

    if (shouldRegister != true || !mounted) {
      nameController.dispose();
      emailController.dispose();
      passwordController.dispose();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await widget.apiClient.register(
        name: nameController.text.trim(),
        email: emailController.text.trim(),
        password: passwordController.text,
      );
      _emailController.text = emailController.text.trim();
      _passwordController.text = passwordController.text;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conta criada. Entrando...')),
        );
      }
      await _login();
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error is PlantIdentificationException
              ? error.message
              : 'Nao foi possivel criar a conta.';
        });
      }
    } finally {
      nameController.dispose();
      emailController.dispose();
      passwordController.dispose();
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showPasswordRecovery() async {
    var recoveryEmail = _emailController.text;
    final email = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Recuperar senha'),
          content: TextFormField(
            initialValue: recoveryEmail,
            onChanged: (value) => recoveryEmail = value,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, recoveryEmail.trim()),
              child: const Text('Continuar'),
            ),
          ],
        );
      },
    );
    if (email == null || email.isEmpty || !mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final resetToken = await widget.apiClient.requestPasswordReset(email);
      if (!mounted) {
        return;
      }

      var recoveryToken = resetToken ?? '';
      var recoveryPassword = '';
      final recoveryData = await showDialog<({String token, String password})>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Definir nova senha'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Informe o codigo enviado por email e a nova senha.',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: recoveryToken,
                  onChanged: (value) => recoveryToken = value,
                  decoration: const InputDecoration(
                    labelText: 'Codigo de recuperacao',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  onChanged: (value) => recoveryPassword = value,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Nova senha (minimo 8 caracteres)',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, (
                  token: recoveryToken.trim(),
                  password: recoveryPassword,
                )),
                child: const Text('Alterar senha'),
              ),
            ],
          );
        },
      );
      if (recoveryData == null || !mounted) {
        return;
      }
      if (recoveryData.token.isEmpty || recoveryData.password.length < 8) {
        if (mounted) {
          setState(
            () => _errorMessage =
                'Informe o codigo e uma senha com ao menos 8 caracteres.',
          );
        }
        return;
      }

      await widget.apiClient.confirmPasswordReset(
        token: recoveryData.token,
        newPassword: recoveryData.password,
      );
      _emailController.text = email;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Senha alterada com sucesso.')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error is PlantIdentificationException
              ? error.message
              : 'Nao foi possivel recuperar a senha.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const EcoScanLogo(size: 112),
                  const SizedBox(height: 34),
                  const Text(
                    'EcoScan',
                    style: TextStyle(
                      fontSize: 44,
                      color: AppColors.text,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 36),
                  EcoTextField(
                    hint: 'Email',
                    icon: Icons.person_outline,
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 14),
                  EcoTextField(
                    hint: 'Senha',
                    icon: Icons.lock_outline,
                    obscureText: true,
                    controller: _passwordController,
                    onSubmitted: (_) => _login(),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    width: 118,
                    height: 42,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.forest,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      onPressed: _isLoading ? null : _login,
                      child: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Entrar'),
                    ),
                  ),
                  TextButton(
                    onPressed: _isLoading ? null : _showRegistration,
                    child: const Text(
                      'Criar conta',
                      style: TextStyle(color: AppColors.forest, fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: _isLoading ? null : _showPasswordRecovery,
                    child: const Text(
                      'Esqueci minha senha',
                      style: TextStyle(color: AppColors.forest, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

class EcoTextField extends StatelessWidget {
  const EcoTextField({
    super.key,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.controller,
    this.keyboardType,
    this.onSubmitted,
  });

  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.moss),
        prefixIcon: Icon(icon, color: AppColors.moss, size: 20),
        filled: true,
        fillColor: AppColors.card,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class EcoHomeShell extends StatefulWidget {
  const EcoHomeShell({
    super.key,
    required this.apiClient,
    this.cameraLoader,
    this.plantIdentifier,
  });

  final EcoScanApiClient apiClient;
  final CameraLoader? cameraLoader;
  final PlantIdentifier? plantIdentifier;

  @override
  State<EcoHomeShell> createState() => _EcoHomeShellState();
}

class _EcoHomeShellState extends State<EcoHomeShell> {
  int _selectedIndex = 1;
  final List<PlantEntry> _libraryPlants = [];
  final List<PlantEntry> _historyPlants = [];
  bool _isLoading = true;
  String? _loadError;
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPersistedPlants());
  }

  Future<void> _loadPersistedPlants() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final profile = await widget.apiClient.fetchCurrentUser();
      final results = await Future.wait([
        widget.apiClient.fetchHistory(),
        widget.apiClient.fetchLibrary(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = profile;
        _historyPlants
          ..clear()
          ..addAll(results[0].map(_entryFromRecord));
        _libraryPlants
          ..clear()
          ..addAll(results[1].map(_entryFromRecord));
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = error is PlantIdentificationException
              ? error.message
              : 'Nao foi possivel carregar os dados.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _addIdentifiedPlant(CapturedPlantResult result) async {
    final record = await widget.apiClient.saveIdentification(result);
    final capturedPlant = _entryFromRecord(record);

    if (!mounted) {
      return;
    }
    setState(() {
      _selectedIndex = 1;
      _historyPlants.insert(0, capturedPlant);
      _libraryPlants.insert(0, capturedPlant);
    });
  }

  PlantEntry _entryFromRecord(PersistedPlantRecord record) {
    return PlantEntry(
      id: record.id,
      name: record.plantName,
      date: _formatDate(record.createdAt.toLocal()),
      subtitle: record.recognized
          ? 'Confianca ${(record.confidence * 100).toStringAsFixed(0)}%'
          : 'Maior confianca ${(record.confidence * 100).toStringAsFixed(0)}%',
      palette: const [Color(0xFF315B48), Color(0xFF8DBB75), Color(0xFFE1E8D8)],
      icon: Icons.local_florist,
      imageBytes: record.imageBytes,
    );
  }

  Future<void> _deleteHistory(PlantEntry plant) async {
    try {
      await widget.apiClient.deleteHistory(plant.id);
      if (mounted) {
        setState(() {
          _historyPlants.removeWhere((item) => item.id == plant.id);
          _libraryPlants.removeWhere((item) => item.id == plant.id);
        });
      }
    } catch (error) {
      _showDataError(error);
    }
  }

  Future<void> _removeFromLibrary(PlantEntry plant) async {
    try {
      await widget.apiClient.removeFromLibrary(plant.id);
      if (mounted) {
        setState(() {
          _libraryPlants.removeWhere((item) => item.id == plant.id);
        });
      }
    } catch (error) {
      _showDataError(error);
    }
  }

  void _showDataError(Object error) {
    if (!mounted) {
      return;
    }
    final message = error is PlantIdentificationException
        ? error.message
        : 'Nao foi possivel atualizar os dados.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _logout() async {
    try {
      await widget.apiClient.logout();
    } catch (_) {
      // The in-memory tokens are cleared before secure storage is accessed.
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          apiClient: widget.apiClient,
          cameraLoader: widget.cameraLoader,
          plantIdentifier: widget.plantIdentifier,
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    final profile = _profile;
    if (profile == null) {
      _showDataError(
        const PlantIdentificationException(
          'Nao foi possivel carregar o perfil.',
        ),
      );
      return;
    }

    final outcome = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          profile: profile,
          onSave: ({required String name, required String email}) {
            return widget.apiClient.updateProfile(name: name, email: email);
          },
          onDeleteAccount: widget.apiClient.deleteAccount,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    if (outcome is UserProfile) {
      setState(() => _profile = outcome);
    } else if (outcome == true) {
      await _logout();
    }
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      LibraryScreen(
        plants: _libraryPlants,
        onDelete: _removeFromLibrary,
        onRefresh: _loadPersistedPlants,
        onLogout: _logout,
        onSettings: _openSettings,
      ),
      HistoryScreen(
        plants: _historyPlants,
        onDelete: _deleteHistory,
        onRefresh: _loadPersistedPlants,
        onLogout: _logout,
        onSettings: _openSettings,
      ),
      CaptureScreen(
        onBack: () => setState(() => _selectedIndex = 1),
        onPlantIdentified: _addIdentifiedPlant,
        cameraLoader: widget.cameraLoader,
        plantIdentifier:
            widget.plantIdentifier ?? widget.apiClient.identifyPlant,
        isActive: _selectedIndex == 2,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null &&
                  _historyPlants.isEmpty &&
                  _libraryPlants.isEmpty
            ? DataLoadError(message: _loadError!, onRetry: _loadPersistedPlants)
            : IndexedStack(index: _selectedIndex, children: screens),
      ),
      bottomNavigationBar: EcoBottomNav(
        selectedIndex: _selectedIndex,
        onChanged: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }
}

class EcoBottomNav extends StatelessWidget {
  const EcoBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(18),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          EcoNavButton(
            icon: Icons.menu_book_outlined,
            selected: selectedIndex == 0,
            semanticLabel: 'Biblioteca',
            onTap: () => onChanged(0),
          ),
          EcoNavButton(
            icon: Icons.home_outlined,
            selected: selectedIndex == 1,
            semanticLabel: 'Historico',
            onTap: () => onChanged(1),
          ),
          EcoNavButton(
            icon: Icons.center_focus_strong,
            selected: selectedIndex == 2,
            semanticLabel: 'Captura',
            onTap: () => onChanged(2),
          ),
        ],
      ),
    );
  }
}

class EcoNavButton extends StatelessWidget {
  const EcoNavButton({
    super.key,
    required this.icon,
    required this.selected,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: selected ? AppColors.forest : AppColors.moss,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}

class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.showBackButton = false,
    this.onBack,
    this.onLogout,
    this.onSettings,
  });

  final String title;
  final bool showBackButton;
  final VoidCallback? onBack;
  final Future<void> Function()? onLogout;
  final Future<void> Function()? onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (showBackButton)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, size: 22),
                      onPressed: onBack,
                    ),
                    const Text(
                      'EcoScan',
                      style: TextStyle(fontSize: 14, color: AppColors.text),
                    ),
                  ],
                )
              else
                const Text(
                  'EcoScan',
                  style: TextStyle(fontSize: 14, color: AppColors.text),
                ),
              const Spacer(),
              if (!showBackButton) ...[
                IconButton(
                  tooltip: 'Configuracoes',
                  onPressed: onSettings,
                  icon: const Icon(Icons.settings_outlined),
                ),
                IconButton(
                  tooltip: 'Sair',
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout_outlined),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w500,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.profile,
    required this.onSave,
    required this.onDeleteAccount,
  });

  final UserProfile profile;
  final Future<UserProfile> Function({
    required String name,
    required String email,
  })
  onSave;
  final Future<void> Function() onDeleteAccount;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _emailController = TextEditingController(text: widget.profile.email);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    if (name.isEmpty || email.isEmpty) {
      setState(() => _errorMessage = 'Informe nome e email.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final profile = await widget.onSave(name: name, email: email);
      if (mounted) {
        Navigator.pop(context, profile);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error is PlantIdentificationException
              ? error.message
              : 'Nao foi possivel atualizar o perfil.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir conta?'),
          content: const Text(
            'Esta acao remove permanentemente a conta, o historico, '
            'a biblioteca e as imagens salvas. Ela nao pode ser desfeita.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Excluir definitivamente'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await widget.onDeleteAccount();
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error is PlantIdentificationException
              ? error.message
              : 'Nao foi possivel excluir a conta.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuracoes')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Perfil',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nome',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Salvar alteracoes'),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _isSaving
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PrivacyPolicyScreen(),
                        ),
                      );
                    },
              icon: const Icon(Icons.privacy_tip_outlined),
              label: const Text('Politica de privacidade'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isSaving ? null : _deleteAccount,
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('Excluir minha conta'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Politica de privacidade')),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: SelectableText(
            'Vigencia: 25 de junho de 2026\n\n'
            'O EcoScan trata nome, email, senha em formato de hash, fotos de '
            'plantas, resultados de identificacao, confianca, datas e dados '
            'do historico e da biblioteca para autenticar o usuario e '
            'oferecer as funcoes do aplicativo.\n\n'
            'A camera e acessada somente quando o usuario abre a captura. '
            'As fotos enviadas sao processadas pelo modelo e, quando salvas, '
            'ficam vinculadas a conta no banco de dados.\n\n'
            'A comunicacao de producao usa HTTPS, e os tokens de sessao ficam '
            'no armazenamento seguro do Android. Os dados nao sao vendidos. '
            'Fornecedores de hospedagem e email podem processar dados apenas '
            'para operar o servico.\n\n'
            'Identificacoes podem ser excluidas pelo aplicativo. Registros '
            'fora da biblioteca podem ser limpos apos 90 dias. A conta e '
            'todos os dados associados podem ser excluidos em Configuracoes '
            '> Excluir minha conta.\n\n'
            'Politica completa e contato:\n'
            'https://github.com/Pulves/ecoScan/blob/front_app/'
            'PRIVACY_POLICY.md',
            style: TextStyle(fontSize: 16, height: 1.45),
          ),
        ),
      ),
    );
  }
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({
    super.key,
    required this.plants,
    required this.onDelete,
    required this.onRefresh,
    required this.onLogout,
    required this.onSettings,
  });

  final List<PlantEntry> plants;
  final Future<void> Function(PlantEntry plant) onDelete;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLogout;
  final Future<void> Function() onSettings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ScreenHeader(
          title: 'Historico',
          onLogout: onLogout,
          onSettings: onSettings,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: plants.isEmpty
                ? const EmptyDataState(
                    icon: Icons.history,
                    message: 'Nenhuma identificacao no historico.',
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                    itemCount: plants.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final plant = plants[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DateLabel(plant.date),
                          PlantCard(
                            plant: plant,
                            showDelete: true,
                            onDelete: () => onDelete(plant),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({
    super.key,
    required this.plants,
    required this.onDelete,
    required this.onRefresh,
    required this.onLogout,
    required this.onSettings,
  });

  final List<PlantEntry> plants;
  final Future<void> Function(PlantEntry plant) onDelete;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLogout;
  final Future<void> Function() onSettings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ScreenHeader(
          title: 'Minha Biblioteca',
          onLogout: onLogout,
          onSettings: onSettings,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: plants.isEmpty
                ? const EmptyDataState(
                    icon: Icons.menu_book_outlined,
                    message: 'Sua biblioteca ainda esta vazia.',
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(28, 14, 28, 24),
                    itemBuilder: (context, index) {
                      final plant = plants[index];
                      return PlantCard(
                        plant: plant,
                        showDelete: true,
                        onDelete: () => onDelete(plant),
                      );
                    },
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemCount: plants.length,
                  ),
          ),
        ),
      ],
    );
  }
}

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    super.key,
    required this.onBack,
    required this.onPlantIdentified,
    required this.isActive,
    this.cameraLoader,
    this.plantIdentifier,
  });

  final VoidCallback onBack;
  final Future<void> Function(CapturedPlantResult result) onPlantIdentified;
  final bool isActive;
  final CameraLoader? cameraLoader;
  final PlantIdentifier? plantIdentifier;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isInitializing = false;
  bool _isTakingPicture = false;
  bool _isIdentifying = false;
  String? _cameraError;
  int _initializationToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.isActive) {
      unawaited(_initializeCamera());
    }
  }

  @override
  void didUpdateWidget(covariant CaptureScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      unawaited(_initializeCamera());
    } else if (oldWidget.isActive && !widget.isActive) {
      unawaited(_stopCamera());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.isActive) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      unawaited(_stopCamera());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_initializeCamera());
    }
  }

  Future<void> _initializeCamera() async {
    final token = ++_initializationToken;
    final oldController = _controller;
    _controller = null;
    await oldController?.dispose();

    if (!mounted || token != _initializationToken || !widget.isActive) {
      return;
    }

    setState(() {
      _isInitializing = true;
      _cameraError = null;
    });

    CameraController? nextController;
    try {
      final cameras = await (widget.cameraLoader ?? availableCameras)();
      if (cameras.isEmpty) {
        throw CameraException(
          'NoCameraAvailable',
          'Nenhuma camera foi encontrada neste dispositivo.',
        );
      }

      final selectedCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      nextController = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await nextController.initialize();

      if (!mounted || token != _initializationToken || !widget.isActive) {
        await nextController.dispose();
        return;
      }

      setState(() {
        _controller = nextController;
        _isInitializing = false;
      });
    } on CameraException catch (error) {
      await nextController?.dispose();
      _setCameraError(token, _messageForCameraError(error));
    } catch (_) {
      await nextController?.dispose();
      _setCameraError(
        token,
        'Nao foi possivel iniciar a camera. Tente novamente.',
      );
    }
  }

  void _setCameraError(int token, String message) {
    if (!mounted || token != _initializationToken) {
      return;
    }
    setState(() {
      _isInitializing = false;
      _cameraError = message;
    });
  }

  String _messageForCameraError(CameraException error) {
    switch (error.code) {
      case 'CameraAccessDenied':
        return 'A permissao da camera foi negada. Autorize o acesso e tente novamente.';
      case 'CameraAccessDeniedWithoutPrompt':
        return 'A camera esta bloqueada para o EcoScan. Libere o acesso nos ajustes do dispositivo.';
      case 'CameraAccessRestricted':
        return 'O acesso a camera esta restrito neste dispositivo.';
      case 'NoCameraAvailable':
        return error.description ?? 'Nenhuma camera foi encontrada.';
      default:
        return 'Nao foi possivel acessar a camera (${error.code}).';
    }
  }

  Future<void> _stopCamera() async {
    ++_initializationToken;
    final controller = _controller;
    _controller = null;
    await controller?.dispose();

    if (mounted) {
      setState(() {
        _isInitializing = false;
        _isTakingPicture = false;
        _isIdentifying = false;
      });
    }
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture ||
        _isTakingPicture ||
        _isIdentifying) {
      return;
    }

    setState(() => _isTakingPicture = true);
    try {
      final image = await controller.takePicture();
      final imageBytes = await image.readAsBytes();
      if (!mounted) {
        return;
      }

      final shouldIdentify = await _showCapturedPhoto(imageBytes);
      if (shouldIdentify && mounted) {
        await _identifyCapturedPhoto(imageBytes);
      }
    } on CameraException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao capturar a foto (${error.code}).')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTakingPicture = false);
      }
    }
  }

  Future<void> _identifyCapturedPhoto(Uint8List imageBytes) async {
    setState(() => _isIdentifying = true);
    try {
      final identifier =
          widget.plantIdentifier ?? EcoScanApiClient().identifyPlant;
      final identification = await identifier(imageBytes);
      if (!mounted) {
        return;
      }

      final shouldAddToHistory = await _showIdentificationResult(
        imageBytes,
        identification,
      );
      if (shouldAddToHistory && mounted) {
        await widget.onPlantIdentified(
          CapturedPlantResult(
            imageBytes: imageBytes,
            identification: identification,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        await _showIdentificationError(error);
      }
    } finally {
      if (mounted) {
        setState(() => _isIdentifying = false);
      }
    }
  }

  Future<bool> _showCapturedPhoto(Uint8List imageBytes) async {
    return await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Foto capturada',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AspectRatio(
                        aspectRatio: 4 / 3,
                        child: Image.memory(imageBytes, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Revise a imagem antes de envia-la ao modelo.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Tirar outra'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.check),
                            label: const Text('Identificar'),
                            onPressed: () => Navigator.pop(context, true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ) ??
        false;
  }

  Future<bool> _showIdentificationResult(
    Uint8List imageBytes,
    PlantIdentification identification,
  ) async {
    final prediction = identification.plant;
    final recognized = identification.recognized && prediction != null;
    return await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recognized ? prediction.name : 'Planta nao reconhecida',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AspectRatio(
                        aspectRatio: 4 / 3,
                        child: Image.memory(imageBytes, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      recognized
                          ? 'Confianca do modelo: ${prediction.confidenceLabel}'
                          : 'Nenhuma classe atingiu o limiar de '
                                '${(identification.threshold * 100).toStringAsFixed(0)}%.',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    if (identification.alternatives.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Text(
                        'Alternativas',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      ...identification.alternatives.take(3).map((plant) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '${plant.name} - ${plant.confidenceLabel}',
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        );
                      }),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Descartar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.library_add_outlined),
                            label: const Text('Salvar'),
                            onPressed: () => Navigator.pop(context, true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ) ??
        false;
  }

  Future<void> _showIdentificationError(Object error) async {
    final message = error is PlantIdentificationException
        ? error.message
        : 'Nao foi possivel identificar a planta.';

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Falha na identificacao',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(message, style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Entendi'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ScreenHeader(
          title: 'Captura',
          showBackButton: true,
          onBack: widget.onBack,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
            child: Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildCameraContent(),
                        if (_controller?.value.isInitialized ?? false) ...[
                          Container(color: Colors.white.withAlpha(28)),
                          Positioned.fill(
                            child: CustomPaint(painter: FocusFramePainter()),
                          ),
                        ],
                        if (_isIdentifying) const IdentificationOverlay(),
                      ],
                    ),
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, -34),
                  child: CaptureButton(
                    isBusy: _isTakingPicture || _isIdentifying,
                    onTap:
                        _controller?.value.isInitialized == true &&
                            !_isTakingPicture &&
                            !_isIdentifying
                        ? _takePicture
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCameraContent() {
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      final previewSize = controller.value.previewSize;
      if (previewSize == null) {
        return CameraPreview(controller);
      }

      return LayoutBuilder(
        builder: (context, constraints) {
          final isPortrait = constraints.maxHeight >= constraints.maxWidth;
          return ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: isPortrait ? previewSize.height : previewSize.width,
                height: isPortrait ? previewSize.width : previewSize.height,
                child: CameraPreview(controller),
              ),
            ),
          );
        },
      );
    }

    return ColoredBox(
      color: const Color(0xFF15271F),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: _isInitializing
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Iniciando camera...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.no_photography_outlined,
                      color: Colors.white,
                      size: 42,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _cameraError ?? 'Camera indisponivel.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                      ),
                      onPressed: _initializeCamera,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ++_initializationToken;
    unawaited(_controller?.dispose());
    super.dispose();
  }
}

class DateLabel extends StatelessWidget {
  const DateLabel(this.date, {super.key});

  final String date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        date,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class EmptyDataState extends StatelessWidget {
  const EmptyDataState({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Icon(icon, size: 54, color: AppColors.moss),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted),
        ),
      ],
    );
  }
}

class DataLoadError extends StatelessWidget {
  const DataLoadError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: AppColors.moss,
            ),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

class PlantCard extends StatelessWidget {
  const PlantCard({
    super.key,
    required this.plant,
    this.showDelete = false,
    this.onDelete,
  });

  final PlantEntry plant;
  final bool showDelete;
  final Future<void> Function()? onDelete;

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remover registro?'),
          content: Text('Deseja remover ${plant.name}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remover'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await onDelete?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 86,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(22),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          SizedBox(
            width: 110,
            height: double.infinity,
            child: PlantThumbnail(plant: plant),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    plant.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, color: AppColors.text),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Desde ${plant.date}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                  Text(
                    plant.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          if (showDelete)
            IconButton(
              tooltip: 'Remover',
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: onDelete == null
                  ? null
                  : () => _confirmDelete(context),
            ),
        ],
      ),
    );
  }
}

class EcoScanLogo extends StatelessWidget {
  const EcoScanLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.moss,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.local_florist, size: size * 0.45, color: Colors.white),
          Positioned(
            top: size * 0.2,
            child: Icon(
              Icons.center_focus_strong,
              size: size * 0.22,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class IdentificationOverlay extends StatelessWidget {
  const IdentificationOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withAlpha(120),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Identificando planta...',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CaptureButton extends StatelessWidget {
  const CaptureButton({super.key, required this.onTap, this.isBusy = false});

  final VoidCallback? onTap;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onTap == null ? const Color(0xFFD6DBD7) : AppColors.card,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 66,
          height: 66,
          child: isBusy
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppColors.forest,
                  ),
                )
              : const Icon(Icons.camera, color: AppColors.forest, size: 34),
        ),
      ),
    );
  }
}

class PlantThumbnail extends StatelessWidget {
  const PlantThumbnail({super.key, required this.plant});

  final PlantEntry plant;

  @override
  Widget build(BuildContext context) {
    final imageBytes = plant.imageBytes;
    if (imageBytes != null) {
      return Image.memory(
        imageBytes,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    }

    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return CustomPaint(
      painter: PlantThumbnailPainter(plant.palette),
      child: Icon(plant.icon, color: Colors.white.withAlpha(230), size: 42),
    );
  }
}

class PlantThumbnailPainter extends CustomPainter {
  PlantThumbnailPainter(this.palette);

  final List<Color> palette;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: palette,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint);

    final leafPaint = Paint()
      ..color = Colors.white.withAlpha(70)
      ..style = PaintingStyle.fill;
    for (var i = 0; i < 8; i++) {
      final dx = size.width * (0.12 + i * 0.11);
      final dy = size.height * (0.25 + (i.isEven ? 0.12 : -0.03));
      canvas.drawOval(
        Rect.fromCenter(center: Offset(dx, dy), width: 28, height: 14),
        leafPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PlantThumbnailPainter oldDelegate) {
    return oldDelegate.palette != palette;
  }
}

class FocusFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(210)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final rect = Rect.fromCenter(
      center: Offset(size.width * 0.5, size.height * 0.43),
      width: size.width * 0.68,
      height: size.width * 0.68,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(16)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
