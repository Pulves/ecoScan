import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:ecoscan_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<List<CameraDescription>> _noCameras() async => [];

void main() {
  testWidgets('EcoScan login opens the main plant screens', (tester) async {
    await tester.pumpWidget(const EcoScanApp(cameraLoader: _noCameras));

    expect(find.text('EcoScan'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);

    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('Historico'), findsOneWidget);

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
            onPlantIdentified: (_) {},
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
}
