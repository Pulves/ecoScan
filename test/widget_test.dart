import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:ecoscan_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<List<CameraDescription>> _noCameras() async => [];

class MemoryTokenStorage implements TokenStorage {
  String? accessToken;
  String? refreshToken;

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
  }

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }
}

class FailingTokenStorage implements TokenStorage {
  @override
  Future<void> clear() async => throw StateError('storage unavailable');

  @override
  Future<String?> readAccessToken() async {
    throw StateError('storage unavailable');
  }

  @override
  Future<String?> readRefreshToken() async {
    throw StateError('storage unavailable');
  }

  @override
  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    throw StateError('storage unavailable');
  }
}

void main() {
  test('Release requires an explicit HTTPS API URL', () {
    expect(
      () =>
          resolveApiBaseUrlCandidates(configuredBaseUrl: '', releaseMode: true),
      throwsStateError,
    );
    expect(
      () => resolveApiBaseUrlCandidates(
        configuredBaseUrl: 'http://api.example.com',
        releaseMode: true,
      ),
      throwsStateError,
    );
    expect(
      resolveApiBaseUrlCandidates(
        configuredBaseUrl: 'https://api.example.com/',
        releaseMode: true,
      ),
      ['https://api.example.com'],
    );
  });

  testWidgets('EcoScan login opens the main plant screens', (tester) async {
    final tokenStorage = MemoryTokenStorage();
    final apiClient = EcoScanApiClient(
      baseUrl: 'http://api.test',
      tokenStorage: tokenStorage,
      client: MockClient((request) async {
        if (request.url.path == '/auth/token') {
          return http.Response(
            jsonEncode({
              'access_token': 'test-token',
              'refresh_token': 'test-refresh-token',
              'token_type': 'bearer',
            }),
            200,
          );
        }
        if (request.url.path == '/history' || request.url.path == '/library') {
          return http.Response('[]', 200);
        }
        if (request.url.path == '/users/') {
          return http.Response(
            jsonEncode({
              'id': 'user-id',
              'name': 'User',
              'email': 'user@example.com',
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      }),
    );
    await tester.pumpWidget(
      EcoScanApp(cameraLoader: _noCameras, apiClient: apiClient),
    );
    await tester.pumpAndSettle();

    expect(find.text('EcoScan'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'password123');

    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('Historico'), findsOneWidget);
    expect(tokenStorage.accessToken, 'test-token');
    expect(tokenStorage.refreshToken, 'test-refresh-token');

    await tester.tap(find.byIcon(Icons.menu_book_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Minha Biblioteca'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.center_focus_strong));
    await tester.pumpAndSettle();
    expect(find.text('Captura'), findsOneWidget);
    expect(
      find.text('Nenhuma camera foi encontrada neste dispositivo.'),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Historico'), findsOneWidget);
  });

  testWidgets('Camera initializes only while capture screen is active', (
    tester,
  ) async {
    var loaderCalls = 0;

    Future<List<CameraDescription>> cameraLoader() async {
      loaderCalls++;
      return [];
    }

    Widget buildCaptureScreen({required bool isActive}) {
      return MaterialApp(
        home: Scaffold(
          body: CaptureScreen(
            onBack: () {},
            onPlantIdentified: (_) async {},
            isActive: isActive,
            cameraLoader: cameraLoader,
          ),
        ),
      );
    }

    await tester.pumpWidget(buildCaptureScreen(isActive: false));
    expect(loaderCalls, 0);

    await tester.pumpWidget(buildCaptureScreen(isActive: true));
    await tester.pumpAndSettle();

    expect(loaderCalls, 1);
    expect(
      find.text('Nenhuma camera foi encontrada neste dispositivo.'),
      findsOneWidget,
    );
  });

  testWidgets('Stored session opens the app without a new login', (
    tester,
  ) async {
    final tokenStorage = MemoryTokenStorage()
      ..accessToken = 'stored-access'
      ..refreshToken = 'stored-refresh';
    final apiClient = EcoScanApiClient(
      baseUrl: 'http://api.test',
      tokenStorage: tokenStorage,
      client: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer stored-access');
        if (request.url.path == '/users/') {
          return http.Response(
            jsonEncode({
              'id': 'user-id',
              'name': 'User',
              'email': 'user@example.com',
            }),
            200,
          );
        }
        if (request.url.path == '/history' || request.url.path == '/library') {
          return http.Response('[]', 200);
        }
        return http.Response('Not found', 404);
      }),
    );

    await tester.pumpWidget(
      EcoScanApp(cameraLoader: _noCameras, apiClient: apiClient),
    );
    await tester.pumpAndSettle();

    expect(find.text('Historico'), findsOneWidget);
    expect(find.text('Entrar'), findsNothing);
  });

  testWidgets('Secure storage failure falls back to login', (tester) async {
    final apiClient = EcoScanApiClient(
      baseUrl: 'http://api.test',
      tokenStorage: FailingTokenStorage(),
      client: MockClient((_) async => http.Response('Not reached', 500)),
    );

    await tester.pumpWidget(EcoScanApp(apiClient: apiClient));
    await tester.pumpAndSettle();

    expect(find.text('Entrar'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
  });

  testWidgets('Password recovery accepts the code received by email', (
    tester,
  ) async {
    Map<String, dynamic>? confirmation;
    final apiClient = EcoScanApiClient(
      baseUrl: 'http://api.test',
      tokenStorage: MemoryTokenStorage(),
      client: MockClient((request) async {
        if (request.url.path == '/auth/password-reset/request') {
          expect(jsonDecode(request.body), {'email': 'user@example.com'});
          return http.Response(
            jsonEncode({
              'message': 'Instrucoes enviadas.',
              'reset_token': null,
            }),
            200,
          );
        }
        if (request.url.path == '/auth/password-reset/confirm') {
          confirmation = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'message': 'Senha alterada com sucesso.'}),
            200,
          );
        }
        return http.Response('Not found', 404);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(apiClient: apiClient)),
    );
    await tester.tap(find.text('Esqueci minha senha'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).last, 'user@example.com');
    await tester.tap(find.text('Continuar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Codigo de recuperacao'), findsOneWidget);
    final recoveryFields = find.byType(TextFormField);
    await tester.enterText(recoveryFields.first, 'email-code');
    await tester.enterText(recoveryFields.last, 'new-password');
    await tester.tap(find.text('Alterar senha'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(confirmation, {
      'token': 'email-code',
      'new_password': 'new-password',
    });
    expect(find.text('Senha alterada com sucesso.'), findsOneWidget);
  });

  testWidgets('Settings screen edits name and email', (tester) async {
    UserProfile? submittedProfile;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          profile: const UserProfile(
            id: 'user-id',
            name: 'Nome antigo',
            email: 'old@example.com',
          ),
          onSave: ({required name, required email}) async {
            submittedProfile = UserProfile(
              id: 'user-id',
              name: name,
              email: email,
            );
            return submittedProfile!;
          },
          onDeleteAccount: () async {},
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).at(0), 'Nome novo');
    await tester.enterText(find.byType(TextField).at(1), 'new@example.com');
    await tester.tap(find.text('Salvar alteracoes'));
    await tester.pumpAndSettle();

    expect(submittedProfile?.name, 'Nome novo');
    expect(submittedProfile?.email, 'new@example.com');
  });

  testWidgets('Settings exposes privacy and confirms account deletion', (
    tester,
  ) async {
    var deleteCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          profile: const UserProfile(
            id: 'user-id',
            name: 'User',
            email: 'user@example.com',
          ),
          onSave: ({required name, required email}) async {
            return UserProfile(id: 'user-id', name: name, email: email);
          },
          onDeleteAccount: () async => deleteCalls++,
        ),
      ),
    );

    await tester.tap(find.text('Politica de privacidade'));
    await tester.pumpAndSettle();
    expect(find.text('Politica de privacidade'), findsOneWidget);
    expect(find.textContaining('A camera e acessada'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Excluir minha conta'));
    await tester.pumpAndSettle();
    expect(find.text('Excluir conta?'), findsOneWidget);
    expect(deleteCalls, 0);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(deleteCalls, 0);

    await tester.tap(find.text('Excluir minha conta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir definitivamente'));
    await tester.pumpAndSettle();
    expect(deleteCalls, 1);
  });

  testWidgets('Deleting a record requires explicit confirmation', (
    tester,
  ) async {
    var deleteCalls = 0;
    const plant = PlantEntry(
      id: 'plant-id',
      name: 'Mangueira',
      date: '24/06/2026',
      subtitle: 'Confianca 93%',
      palette: [Colors.green, Colors.lightGreen],
      icon: Icons.local_florist,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlantCard(
            plant: plant,
            showDelete: true,
            onDelete: () async => deleteCalls++,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Remover'));
    await tester.pumpAndSettle();
    expect(find.text('Remover registro?'), findsOneWidget);
    expect(deleteCalls, 0);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(deleteCalls, 0);

    await tester.tap(find.byTooltip('Remover'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remover'));
    await tester.pumpAndSettle();
    expect(deleteCalls, 1);
  });

  test(
    'EcoScanApiClient posts the captured image to the identify endpoint',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/plants/identify');
        expect(request.url.queryParameters['confidence_threshold'], '0.60');
        expect(request.url.queryParameters['top_k'], '3');
        expect(
          request.headers['content-type'],
          contains('multipart/form-data'),
        );
        expect(utf8.decode(request.bodyBytes), contains('name="image"'));

        return http.Response(
          jsonEncode({
            'success': true,
            'recognized': true,
            'plant': {
              'class_id': 3,
              'slug': 'mango',
              'name': 'Mangueira',
              'confidence': 0.932,
            },
            'alternatives': [
              {
                'class_id': 4,
                'slug': 'banana',
                'name': 'Bananeira',
                'confidence': 0.12,
              },
            ],
            'threshold': 0.6,
            'model': {
              'task': 'classification',
              'architecture': 'yolo11s-cls.pt',
              'image_size': 224,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = EcoScanApiClient(baseUrl: 'http://api.test/', client: client);
      final result = await api.identifyPlant(Uint8List.fromList([1, 2, 3]));

      expect(result.recognized, isTrue);
      expect(result.plant?.name, 'Mangueira');
      expect(result.plant?.confidenceLabel, '93%');
      expect(result.alternatives.single.name, 'Bananeira');
    },
  );

  test('EcoScanApiClient surfaces API error details', () async {
    final client = MockClient((_) async {
      return http.Response(
        jsonEncode({
          'detail': 'O modelo best.pt ainda nao foi disponibilizado.',
        }),
        503,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = EcoScanApiClient(baseUrl: 'http://api.test', client: client);

    expect(
      () => api.identifyPlant(Uint8List.fromList([1, 2, 3])),
      throwsA(
        isA<PlantIdentificationException>().having(
          (error) => error.message,
          'message',
          'O modelo best.pt ainda nao foi disponibilizado.',
        ),
      ),
    );
  });

  test(
    'EcoScanApiClient falls back from adb reverse to emulator host',
    () async {
      final calledHosts = <String>[];
      final client = MockClient((request) async {
        calledHosts.add(request.url.host);
        if (request.url.host == '127.0.0.1') {
          throw http.ClientException('Connection refused', request.url);
        }

        return http.Response(
          jsonEncode({
            'success': true,
            'recognized': true,
            'plant': {
              'class_id': 0,
              'slug': 'banana',
              'name': 'Bananeira',
              'confidence': 0.81,
            },
            'alternatives': [],
            'threshold': 0.6,
            'model': {
              'task': 'classification',
              'architecture': 'yolo11s-cls.pt',
              'image_size': 224,
            },
          }),
          200,
        );
      });

      final api = EcoScanApiClient(client: client);
      final result = await api.identifyPlant(Uint8List.fromList([1, 2, 3]));

      expect(calledHosts, ['127.0.0.1', '10.0.2.2']);
      expect(result.plant?.name, 'Bananeira');
    },
  );

  test('EcoScanApiClient persists, reloads and removes user records', () async {
    const recordId = '9473157e-99eb-4633-91d8-38f72c164268';
    final requests = <String>[];
    final recordJson = {
      'id': recordId,
      'plant_name': 'Mangueira',
      'plant_slug': 'mango',
      'confidence': 0.93,
      'recognized': true,
      'created_at': '2026-06-24T12:00:00Z',
      'in_library': true,
      'image_url': '/history/$recordId/image',
    };
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      expect(request.headers['authorization'], 'Bearer test-token');

      if (request.method == 'POST' && request.url.path == '/history') {
        expect(utf8.decode(request.bodyBytes), contains('name="image"'));
        expect(utf8.decode(request.bodyBytes), contains('Mangueira'));
        return http.Response(jsonEncode(recordJson), 201);
      }
      if (request.method == 'GET' && request.url.path == '/history') {
        return http.Response(jsonEncode([recordJson]), 200);
      }
      if (request.method == 'GET' &&
          request.url.path == '/history/$recordId/image') {
        return http.Response.bytes([1, 2, 3, 4], 200);
      }
      if (request.method == 'DELETE' &&
          request.url.path == '/library/$recordId') {
        return http.Response('', 204);
      }
      return http.Response('Not found', 404);
    });
    final api = EcoScanApiClient(
      baseUrl: 'http://api.test',
      client: client,
      accessToken: 'test-token',
      refreshToken: 'test-refresh-token',
      tokenStorage: MemoryTokenStorage(),
    );
    final capture = CapturedPlantResult(
      imageBytes: Uint8List.fromList([9, 8, 7]),
      identification: const PlantIdentification(
        success: true,
        recognized: true,
        plant: PlantPrediction(
          classId: 3,
          slug: 'mango',
          name: 'Mangueira',
          confidence: 0.93,
        ),
        alternatives: [],
        threshold: 0.6,
      ),
    );

    final saved = await api.saveIdentification(capture);
    final history = await api.fetchHistory();
    await api.removeFromLibrary(recordId);

    expect(saved.id, recordId);
    expect(saved.imageBytes, [9, 8, 7]);
    expect(history.single.plantName, 'Mangueira');
    expect(history.single.imageBytes, [1, 2, 3, 4]);
    expect(requests, [
      'POST /history',
      'GET /history',
      'GET /history/$recordId/image',
      'DELETE /library/$recordId',
    ]);
  });

  test('EcoScanApiClient refreshes an expired stored session', () async {
    final tokenStorage = MemoryTokenStorage()
      ..accessToken = 'expired-access'
      ..refreshToken = 'valid-refresh';
    var userCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/users/') {
        userCalls++;
        if (request.headers['authorization'] == 'Bearer expired-access') {
          return http.Response(
            jsonEncode({'detail': 'Token has expired'}),
            401,
          );
        }
        expect(request.headers['authorization'], 'Bearer renewed-access');
        return http.Response(
          jsonEncode({
            'id': 'user-id',
            'name': 'User',
            'email': 'user@example.com',
          }),
          200,
        );
      }
      if (request.url.path == '/auth/refresh') {
        expect(request.headers['authorization'], 'Bearer valid-refresh');
        return http.Response(
          jsonEncode({
            'access_token': 'renewed-access',
            'refresh_token': 'renewed-refresh',
            'token_type': 'bearer',
          }),
          200,
        );
      }
      return http.Response('Not found', 404);
    });
    final api = EcoScanApiClient(
      baseUrl: 'http://api.test',
      client: client,
      tokenStorage: tokenStorage,
    );

    final restored = await api.restoreSession();

    expect(restored, isTrue);
    expect(userCalls, 2);
    expect(tokenStorage.accessToken, 'renewed-access');
    expect(tokenStorage.refreshToken, 'renewed-refresh');
  });

  test('EcoScanApiClient updates profile and rotates session tokens', () async {
    final tokenStorage = MemoryTokenStorage();
    final client = MockClient((request) async {
      expect(request.method, 'PUT');
      expect(request.url.path, '/users/');
      expect(request.headers['authorization'], 'Bearer old-access');
      expect(jsonDecode(request.body), {
        'name': 'Nome novo',
        'email': 'new@example.com',
      });
      return http.Response(
        jsonEncode({
          'user': {
            'id': 'user-id',
            'name': 'Nome novo',
            'email': 'new@example.com',
          },
          'access_token': 'new-access',
          'refresh_token': 'new-refresh',
          'token_type': 'bearer',
        }),
        200,
      );
    });
    final api = EcoScanApiClient(
      baseUrl: 'http://api.test',
      client: client,
      tokenStorage: tokenStorage,
      accessToken: 'old-access',
      refreshToken: 'old-refresh',
    );

    final profile = await api.updateProfile(
      name: 'Nome novo',
      email: 'new@example.com',
    );

    expect(profile.name, 'Nome novo');
    expect(tokenStorage.accessToken, 'new-access');
    expect(tokenStorage.refreshToken, 'new-refresh');
  });

  test('EcoScanApiClient deletes account and clears tokens', () async {
    final tokenStorage = MemoryTokenStorage()
      ..accessToken = 'stored-access'
      ..refreshToken = 'stored-refresh';
    final client = MockClient((request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/users/');
      expect(request.headers['authorization'], 'Bearer stored-access');
      return http.Response('', 204);
    });
    final api = EcoScanApiClient(
      baseUrl: 'http://api.test',
      client: client,
      tokenStorage: tokenStorage,
      accessToken: 'stored-access',
      refreshToken: 'stored-refresh',
    );

    await api.deleteAccount();

    expect(tokenStorage.accessToken, isNull);
    expect(tokenStorage.refreshToken, isNull);
  });

  test('EcoScanApiClient requests and confirms password reset', () async {
    final calls = <String>[];
    final client = MockClient((request) async {
      calls.add(request.url.path);
      if (request.url.path == '/auth/password-reset/request') {
        expect(jsonDecode(request.body), {'email': 'user@example.com'});
        return http.Response(
          jsonEncode({
            'message': 'Token criado.',
            'reset_token': 'reset-token',
          }),
          200,
        );
      }
      expect(request.url.path, '/auth/password-reset/confirm');
      expect(jsonDecode(request.body), {
        'token': 'reset-token',
        'new_password': 'new-password',
      });
      return http.Response(jsonEncode({'message': 'Senha alterada.'}), 200);
    });
    final api = EcoScanApiClient(
      baseUrl: 'http://api.test',
      client: client,
      tokenStorage: MemoryTokenStorage(),
    );

    final token = await api.requestPasswordReset('user@example.com');
    await api.confirmPasswordReset(token: token!, newPassword: 'new-password');

    expect(calls, [
      '/auth/password-reset/request',
      '/auth/password-reset/confirm',
    ]);
  });
}
