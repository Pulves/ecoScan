import 'dart:math' as math;

import 'package:flutter/material.dart';

void main() {
  runApp(const EcoScanApp());
}

class EcoScanApp extends StatelessWidget {
  const EcoScanApp({super.key});

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
      home: const LoginScreen(),
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
  });

  final String name;
  final String date;
  final String subtitle;
  final List<Color> palette;
  final IconData icon;
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
  const LoginScreen({super.key});

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
                  const EcoTextField(
                    hint: 'Login',
                    icon: Icons.person_outline,
                  ),
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
                            builder: (_) => const EcoHomeShell(),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class EcoHomeShell extends StatefulWidget {
  const EcoHomeShell({super.key});

  @override
  State<EcoHomeShell> createState() => _EcoHomeShellState();
}

class _EcoHomeShellState extends State<EcoHomeShell> {
  int _selectedIndex = 1;
  final List<PlantEntry> _libraryPlants = [samplePlants[1]];
  final List<PlantEntry> _historyPlants = [samplePlants[0], samplePlants[0], samplePlants[1]];

  void _addScanResult() {
    setState(() {
      _selectedIndex = 1;
      _historyPlants.insert(0, samplePlants[2]);
      _libraryPlants.insert(0, samplePlants[2]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      LibraryScreen(plants: _libraryPlants),
      HistoryScreen(plants: _historyPlants),
      CaptureScreen(
        onBack: () => setState(() => _selectedIndex = 1),
        onPlantDetected: _addScanResult,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: screens,
        ),
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
          child: ListView(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
            children: [
              const DateLabel('28/04/2026'),
              PlantCard(plant: plants[0]),
              const SizedBox(height: 16),
              PlantCard(plant: plants.length > 1 ? plants[1] : samplePlants[0]),
              const SizedBox(height: 16),
              const DateLabel('12/04/2026'),
              PlantCard(plant: plants.length > 2 ? plants[2] : samplePlants[1]),
            ],
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
              return PlantCard(
                plant: plant,
                showDelete: true,
              );
            },
            separatorBuilder: (_, _) => const SizedBox(height: 14),
            itemCount: plants.length,
          ),
        ),
      ],
    );
  }
}

class CaptureScreen extends StatelessWidget {
  const CaptureScreen({
    super.key,
    required this.onBack,
    required this.onPlantDetected,
  });

  final VoidCallback onBack;
  final VoidCallback onPlantDetected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ScreenHeader(
          title: 'Captura',
          showBackButton: true,
          onBack: onBack,
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
                        const PlantPreview(),
                        Container(color: Colors.white.withAlpha(65)),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: FocusFramePainter(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, -34),
                  child: CaptureButton(onTap: () => _showDetection(context)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showDetection(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Jiboia identificada',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Resultado simulado para validar o fluxo de captura. '
                'Depois, este ponto pode receber o modelo de deteccao '
                'por camera.',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.library_add_outlined),
                  label: const Text('Adicionar a biblioteca'),
                  onPressed: () {
                    Navigator.pop(context);
                    onPlantDetected();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
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
  const PlantCard({
    super.key,
    required this.plant,
    this.showDelete = false,
  });

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
            child: Icon(Icons.center_focus_strong, size: size * 0.22, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class CaptureButton extends StatelessWidget {
  const CaptureButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 66,
          height: 66,
          child: Icon(Icons.camera, color: AppColors.forest, size: 34),
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
    return CustomPaint(
      painter: PlantThumbnailPainter(plant.palette),
      child: Icon(plant.icon, color: Colors.white.withAlpha(230), size: 42),
    );
  }
}

class PlantPreview extends StatelessWidget {
  const PlantPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: CameraPreviewPainter(),
      child: const SizedBox.expand(),
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

class CameraPreviewPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final sky = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF9BC7EB), Color(0xFFF3D7B0), Color(0xFFC69E72)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sky);

    final groundPaint = Paint()..color = const Color(0xFFB88458);
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.68, size.width, size.height * 0.32),
      groundPaint,
    );

    final trunkPaint = Paint()
      ..color = const Color(0xFF7C5638)
      ..strokeWidth = size.width * 0.04
      ..strokeCap = StrokeCap.round;
    final trunkTop = Offset(size.width * 0.48, size.height * 0.18);
    final trunkBottom = Offset(size.width * 0.58, size.height * 0.78);
    canvas.drawLine(trunkBottom, trunkTop, trunkPaint);

    final leafPaint = Paint()..color = const Color(0xFF577B42);
    for (var i = 0; i < 16; i++) {
      final angle = i * 0.39;
      final leafLength = size.width * (0.25 + (i % 3) * 0.03);
      final end = Offset(
        trunkTop.dx + leafLength * math.sin(angle),
        trunkTop.dy + leafLength * math.cos(angle) * 0.62,
      );
      canvas.drawLine(
        trunkTop,
        end,
        Paint()
          ..color = leafPaint.color.withAlpha(220)
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round,
      );
    }

    final fencePaint = Paint()
      ..color = const Color(0xFF7F654B).withAlpha(170)
      ..strokeWidth = 3;
    for (var x = size.width * 0.12; x < size.width; x += size.width * 0.19) {
      canvas.drawLine(
        Offset(x, size.height * 0.72),
        Offset(x - 8, size.height * 0.95),
        fencePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
