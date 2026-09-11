import 'package:flutter/material.dart';

/// Géométrie des yeux dans les images 512×512 (calculée par
/// tools/make_icon.py, voir assets/images/dino_eyes.json).
class _Eyes {
  static const double left = 183.3;
  static const double right = 328.7;
  static const double y = 198.4;
  static const double whiteRx = 51.9;
  static const double whiteRy = 54.5;
  static const double pupilR = 33.2;
  static const double pupilDy = 6.2;
}

/// Les têtes qui ont des yeux "vivants" (pupilles dessinées par l'appli,
/// paupières pour cligner). Les autres têtes sont des images complètes.
const kLiveEyeFaces = {'head', 'listen'};

/// Toutes les têtes disponibles, pour le préchargement.
const kAllFaces = [
  'head',
  'head_noeyes',
  'listen',
  'listen_noeyes',
  'huh',
  'yell',
  'tongue',
  'yark',
  'squish1',
  'squish2',
  'squish3',
];

const _kSkin = Color(0xFFFF69B4);

/// La tête du dino. [pupil] : regard, de (-1,-1) à (1,1), (0,0) = droit
/// devant. [blink] : paupières fermées.
class DinoFace extends StatelessWidget {
  const DinoFace({
    super.key,
    required this.face,
    required this.size,
    this.pupil = Offset.zero,
    this.blink = false,
  });

  final String face;
  final double size;
  final Offset pupil;
  final bool blink;

  @override
  Widget build(BuildContext context) {
    final live = kLiveEyeFaces.contains(face);
    final asset = live
        ? 'assets/images/dino_${face}_noeyes.png'
        : 'assets/images/dino_$face.png';
    final k = size / 512;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            asset,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
          ),
          if (live) ...[
            for (final cx in [_Eyes.left, _Eyes.right]) ...[
              // Pupille, limitée à l'intérieur du blanc de l'œil.
              Positioned(
                left:
                    (cx +
                        pupil.dx * (_Eyes.whiteRx - _Eyes.pupilR) -
                        _Eyes.pupilR) *
                    k,
                top:
                    (_Eyes.y +
                        _Eyes.pupilDy +
                        pupil.dy * (_Eyes.whiteRy - _Eyes.pupilR) -
                        _Eyes.pupilR) *
                    k,
                width: _Eyes.pupilR * 2 * k,
                height: _Eyes.pupilR * 2 * k,
                child: const _Pupil(),
              ),
              // Paupière : un disque couleur peau qui recouvre l'œil.
              if (blink)
                Positioned(
                  left: (cx - _Eyes.whiteRx - 2) * k,
                  top: (_Eyes.y - _Eyes.whiteRy - 2) * k,
                  width: (_Eyes.whiteRx + 2) * 2 * k,
                  height: (_Eyes.whiteRy + 2) * 2 * k,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kSkin,
                    ),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Pupil extends StatelessWidget {
  const _Pupil();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final d = c.maxWidth;
        return Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF281228),
              ),
            ),
            // Reflet
            Positioned(
              left: d * 0.55,
              top: d * 0.12,
              width: d * 0.32,
              height: d * 0.32,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            ),
            Positioned(
              left: d * 0.2,
              top: d * 0.62,
              width: d * 0.14,
              height: d * 0.14,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
