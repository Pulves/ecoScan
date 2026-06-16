import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const EcoScanApp());
}

typedef CameraLoader = Future<List<CameraDescription>> Function();
typedef PlantIdentifier =
    Future<PlantIdentification> Function(Uint8List imageBytes);

const _apiBaseUrl = String.fromEnvironment(
  'ECOSCAN_API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

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

class EcoScanApiClient {
  const EcoScanApiClient({
    this.baseUrl = _apiBaseUrl,
    this.client,
    this.timeout = const Duration(seconds: 30),
  });

  final String baseUrl;
  final http.Client? client;
  final Duration timeout;

  Future<PlantIdentification> identifyPlant(Uint8List imageBytes) async {
    final normalizedBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final uri = Uri.parse(
      '$normalizedBaseUrl/plants/identify',
    ).replace(queryParameters: {'confidence_threshold': '0.60', 'top_k': '3'});
    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: 'plant.jpg',
        ),
      );
    final activeClient = client ?? http.Client();

    try {
      final streamedResponse = await activeClient
          .send(request)
          .timeout(timeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        throw PlantIdentificationException(_errorMessageFrom(response));
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const PlantIdentificationException(
          'Resposta inesperada da API de identificacao.',
        );
      }
      return PlantIdentification.fromJson(decoded);
    } on TimeoutException {
      throw const PlantIdentificationException(
        'Tempo esgotado ao chamar a API de identificacao.',
      );
    } on http.ClientException catch (error) {
      throw PlantIdentificationException(
        'Nao foi possivel conectar a API: ${error.message}',
      );
    } on FormatException {
      throw const PlantIdentificationException(
        'A API retornou uma resposta invalida.',
      );
    } finally {
      if (client == null) {
        activeClient.close();
      }
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
  const EcoScanApp({super.key, this.cameraLoader, this.plantIdentifier});

  final CameraLoader? cameraLoader;
  final PlantIdentifier? plantIdentifier;

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
      home: LoginScreen(
        cameraLoader: cameraLoader,
        plantIdentifier: plantIdentifier,
      ),
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
    required this.name,
    required this.date,
    required this.subtitle,
    required this.palette,
    required this.icon,
    this.imageBytes,
  });

  final String name;
  final String date;
  final String subtitle;
  final List<Color> palette;
  final IconData icon;
  final Uint8List? imageBytes;
}

const List<PlantEntry> samplePlants = [
  PlantEntry(
    name: 'Carnauba',
    date: '28/04/2026',
    subtitle: 'Palmeira nativa',
    palette: [Color(0xFF9FC4E4), Color(0xFFD2B27A), Color(0xFF5B7F45)],
    icon: Icons.park,
  ),
  PlantEntry(
    name: 'Planta',
    date: '12/04/2026',
    subtitle: 'Silvestre',
    palette: [Color(0xFF2F5132), Color(0xFFF1D342), Color(0xFFBA9A65)],
    icon: Icons.local_florist,
  ),
  PlantEntry(
    name: 'Jiboia',
    date: '07/04/2026',
    subtitle: 'Folhagem',
    palette: [Color(0xFF213C2A), Color(0xFFA6CA63), Color(0xFFE4E7D6)],
    icon: Icons.spa,
  ),
];

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, this.cameraLoader, this.plantIdentifier});

  final CameraLoader? cameraLoader;
  final PlantIdentifier? plantIdentifier;

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
                  const EcoTextField(hint: 'Login', icon: Icons.person_outline),
                  const SizedBox(height: 14),
                  const EcoTextField(
                    hint: 'Senha',
                    icon: Icons.lock_outline,
                    obscureText: true,
                  ),
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
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => EcoHomeShell(
                              cameraLoader: cameraLoader,
                              plantIdentifier: plantIdentifier,
                            ),
                          ),
                        );
                      },
                      child: const Text('Entrar'),
                    ),
                  ),
                  TextButton(
                    onPressed: () {},
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
}

class EcoTextField extends StatelessWidget {
  const EcoTextField({
    super.key,
    required this.hint,
    required this.icon,
    this.obscureText = false,
  });

  final String hint;
  final IconData icon;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      obscureText: obscureText,
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
  const EcoHomeShell({super.key, this.cameraLoader, this.plantIdentifier});

  final CameraLoader? cameraLoader;
  final PlantIdentifier? plantIdentifier;

  @override
  State<EcoHomeShell> createState() => _EcoHomeShellState();
}

class _EcoHomeShellState extends State<EcoHomeShell> {
  int _selectedIndex = 1;
  final List<PlantEntry> _libraryPlants = [samplePlants[1]];
  final List<PlantEntry> _historyPlants = [
    samplePlants[0],
    samplePlants[0],
    samplePlants[1],
  ];

  void _addIdentifiedPlant(CapturedPlantResult result) {
    final identification = result.identification;
    final prediction = identification.plant;
    final capturedPlant = PlantEntry(
      name: identification.recognized && prediction != null
          ? prediction.name
          : 'Planta nao reconhecida',
      date: _formatDate(DateTime.now()),
      subtitle: _subtitleFor(identification),
      palette: const [Color(0xFF315B48), Color(0xFF8DBB75), Color(0xFFE1E8D8)],
      icon: Icons.local_florist,
      imageBytes: result.imageBytes,
    );

    setState(() {
      _selectedIndex = 1;
      _historyPlants.insert(0, capturedPlant);
      _libraryPlants.insert(0, capturedPlant);
    });
  }

  String _subtitleFor(PlantIdentification identification) {
    final prediction = identification.plant;
    if (identification.recognized && prediction != null) {
      return 'Confianca ${prediction.confidenceLabel}';
    }

    final threshold = (identification.threshold * 100).toStringAsFixed(0);
    return 'Abaixo do limiar de $threshold%';
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      LibraryScreen(plants: _libraryPlants),
      HistoryScreen(plants: _historyPlants),
      CaptureScreen(
        onBack: () => setState(() => _selectedIndex = 1),
        onPlantIdentified: _addIdentifiedPlant,
        cameraLoader: widget.cameraLoader,
        plantIdentifier: widget.plantIdentifier,
        isActive: _selectedIndex == 2,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _selectedIndex, children: screens),
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
  });

  final String title;
  final bool showBackButton;
  final VoidCallback? onBack;

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
                  onPressed: () {},
                  icon: const Icon(Icons.settings_outlined),
                ),
                IconButton(
                  tooltip: 'Sair',
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
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

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.plants});

  final List<PlantEntry> plants;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ScreenHeader(title: 'Historico'),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
            itemCount: plants.length,
            separatorBuilder: (_, _) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final plant = plants[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DateLabel(plant.date),
                  PlantCard(plant: plant),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, required this.plants});

  final List<PlantEntry> plants;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ScreenHeader(title: 'Minha Biblioteca'),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(28, 14, 28, 24),
            itemBuilder: (context, index) {
              final plant = plants[index];
              return PlantCard(plant: plant, showDelete: true);
            },
            separatorBuilder: (_, _) => const SizedBox(height: 14),
            itemCount: plants.length,
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
  final ValueChanged<CapturedPlantResult> onPlantIdentified;
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
          widget.plantIdentifier ?? const EcoScanApiClient().identifyPlant;
      final identification = await identifier(imageBytes);
      if (!mounted) {
        return;
      }

      final shouldAddToHistory = await _showIdentificationResult(
        imageBytes,
        identification,
      );
      if (shouldAddToHistory && mounted) {
        widget.onPlantIdentified(
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

class PlantCard extends StatelessWidget {
  const PlantCard({super.key, required this.plant, this.showDelete = false});

  final PlantEntry plant;
  final bool showDelete;

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
              onPressed: () {},
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
