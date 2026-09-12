import 'package:flutter/material.dart';

/// Une page du tutoriel : personnage, titre, texte, fond, et le son joué
/// quand on arrive dessus.
class TutorialPage {
  const TutorialPage({
    required this.image,
    required this.title,
    required this.body,
    required this.background,
    this.sound,
    this.titleColors,
  });
  final String image;
  final String title;
  final String body;
  final List<Color> background;
  final String? sound;
  final List<Color>? titleColors;
}

/// Le tutoriel : 4 écrans qu'on fait glisser. [onSound] joue un asset (ou
/// rien si les sons sont coupés), [onDone] ferme.
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({
    super.key,
    required this.pages,
    required this.onSound,
    required this.rainbow,
  });
  final List<TutorialPage> pages;
  final void Function(String asset) onSound;
  final List<Color> rainbow;

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _controller = PageController();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    final s = widget.pages.first.sound;
    if (s != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onSound(s));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int i) {
    _controller.animateToPage(
      i,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.pages[_index];
    final last = _index == widget.pages.length - 1;
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: page.background,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Passer',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: widget.pages.length,
                  onPageChanged: (i) {
                    setState(() => _index = i);
                    final s = widget.pages[i].sound;
                    if (s != null) widget.onSound(s);
                  },
                  itemBuilder: (context, i) {
                    final p = widget.pages[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(p.image, height: 190),
                          const SizedBox(height: 28),
                          // Cartouche sombre : lisible sur les fonds clairs
                          // (le kawaii) comme sur les sombres.
                          Container(
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ShaderMask(
                                  blendMode: BlendMode.srcIn,
                                  shaderCallback: (rect) => LinearGradient(
                                    colors: p.titleColors ?? widget.rainbow,
                                  ).createShader(rect),
                                  child: Text(
                                    p.title,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontFamily: 'RubikSprayPaint',
                                      fontSize: 30,
                                      height: 1.1,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  p.body,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    height: 1.4,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < widget.pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: i == _index ? 22 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == _index ? Colors.white : Colors.white38,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 18, 28, 24),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: last
                        ? () => Navigator.of(context).pop()
                        : () => _go(_index + 1),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      last ? 'FAIS PÉTER' : 'Suivant',
                      style: const TextStyle(
                        fontFamily: 'RubikSprayPaint',
                        fontSize: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
