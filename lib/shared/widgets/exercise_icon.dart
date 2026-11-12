import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../domain/training.dart';

/// A decorative cue for the exercise name that appears beside it.
class ExerciseIcon extends StatelessWidget {
  const ExerciseIcon(this.name, {this.size = 34, super.key});

  final String name;
  final double size;

  static final _separators = RegExp(r'[\s_‐‑‒–—-]+');

  @override
  Widget build(BuildContext context) {
    final pose = switch (normalizeName(name).replaceAll(_separators, '')) {
      'pushup' || 'pushups' || 'pressup' || 'pressups' => _Pose.pushUp,
      'pullup' || 'pullups' || 'chinup' || 'chinups' => _Pose.pullUp,
      'plank' || 'planks' || 'forearmplank' => _Pose.plank,
      'dip' || 'dips' || 'parallelbardip' || 'parallelbardips' => _Pose.dip,
      'squat' ||
      'squats' ||
      'bodyweightsquat' ||
      'bodyweightsquats' ||
      'airsquat' ||
      'airsquats' => _Pose.squat,
      'wallsit' || 'wallsits' => _Pose.wallSit,
      'hollowhold' || 'hollowbodyhold' => _Pose.hollowHold,
      'lunge' || 'lunges' || 'forwardlunge' || 'forwardlunges' => _Pose.lunge,
      'situp' || 'situps' => _Pose.sitUp,
      'deadlift' || 'deadlifts' || 'barbelldeadlift' => _Pose.deadlift,
      'benchpress' || 'barbellbenchpress' => _Pose.benchPress,
      _ => null,
    };
    final colors = context.colors;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.input,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: pose == null
                ? Icon(
                    LucideIcons.dumbbell,
                    color: colors.green,
                    size: size * .58,
                  )
                : CustomPaint(
                    painter: _PosePainter(pose, colors.green, colors.muted),
                  ),
          ),
        ),
      ),
    );
  }
}

typedef _Point = (double, double);

// Every pose uses a 32-unit canvas. Equipment and floor lines sit behind the
// figure, giving each movement a recognizable silhouette at list size.
enum _Pose {
  pushUp(
    (26, 9),
    [
      [(23, 12), (15, 17), (6, 23), (4, 25)],
      [(23, 12), (24, 25), (28, 25)],
    ],
    [
      [(3, 27), (29, 27)],
    ],
  ),
  pullUp(
    (16, 9),
    [
      [(8, 5), (7, 12), (13, 14), (19, 14), (25, 12), (24, 5)],
      [(16, 13), (16, 21), (12, 26), (12, 29)],
      [(16, 21), (20, 26), (19, 29)],
    ],
    [
      [(4, 4), (28, 4)],
    ],
  ),
  plank(
    (26, 15),
    [
      [(23, 18), (14, 20), (6, 23), (4, 25)],
      [(23, 18), (21, 25), (28, 25)],
    ],
    [
      [(3, 27), (29, 27)],
    ],
  ),
  dip(
    (18, 6),
    [
      [(17, 10), (15, 18), (20, 22), (17, 27), (12, 27)],
      [(17, 11), (12, 13), (9, 18)],
      [(18, 11), (23, 13), (25, 18)],
    ],
    [
      [(4, 18), (11, 18)],
      [(6, 18), (6, 28)],
      [(23, 18), (29, 18)],
      [(27, 18), (27, 28)],
    ],
  ),
  squat(
    (20, 7),
    [
      [(18, 11), (12, 20), (21, 21), (18, 27), (22, 27)],
      [(18, 12), (23, 16), (28, 15)],
    ],
    [
      [(6, 29), (28, 29)],
    ],
  ),
  wallSit(
    (9, 7),
    [
      [(8, 11), (8, 20), (21, 20), (21, 27), (25, 27)],
      [(8, 12), (12, 17), (17, 19)],
    ],
    [
      [(4, 4), (4, 29), (28, 29)],
    ],
  ),
  hollowHold(
    (6, 15),
    [
      [(9, 18), (14, 23), (19, 24), (28, 17)],
      [(10, 19), (14, 18), (19, 18)],
    ],
    [
      [(3, 27), (29, 27)],
    ],
  ),
  lunge(
    (16, 6),
    [
      [(16, 10), (16, 17), (24, 19), (24, 27), (28, 27)],
      [(16, 17), (12, 24), (6, 24), (4, 27)],
      [(16, 11), (11, 15), (14, 17)],
    ],
    [
      [(3, 29), (29, 29)],
    ],
  ),
  sitUp(
    (12, 9),
    [
      [(11, 13), (10, 18), (14, 25), (21, 18), (26, 25), (29, 25)],
      [(11, 14), (15, 18), (19, 17)],
    ],
    [
      [(3, 27), (29, 27)],
    ],
  ),
  deadlift(
    (21, 7),
    [
      [(19, 11), (11, 16), (15, 22), (13, 28), (17, 28)],
      [(19, 11), (20, 19), (22, 25)],
    ],
    [
      [(17, 25), (29, 25)],
      [(19, 22), (19, 28)],
      [(27, 22), (27, 28)],
      [(5, 30), (29, 30)],
    ],
  ),
  benchPress(
    (6, 16),
    [
      [(10, 18), (18, 19), (23, 21), (25, 27), (29, 27)],
      [(12, 18), (12, 8)],
    ],
    [
      [(7, 8), (18, 8)],
      [(9, 5), (9, 11)],
      [(16, 5), (16, 11)],
      [(3, 22), (22, 22)],
      [(7, 22), (7, 28)],
      [(20, 22), (20, 28)],
    ],
  );

  const _Pose(this.head, this.figure, this.support);

  final _Point head;
  final List<List<_Point>> figure, support;
}

class _PosePainter extends CustomPainter {
  const _PosePainter(this.pose, this.figureColor, this.supportColor);

  final _Pose pose;
  final Color figureColor, supportColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 32, size.height / 32);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 1.4
      ..color = supportColor;

    void draw(List<List<_Point>> lines) {
      for (final line in lines) {
        final (x, y) = line.first;
        final path = Path()..moveTo(x, y);
        for (final (x, y) in line.skip(1)) {
          path.lineTo(x, y);
        }
        canvas.drawPath(path, paint);
      }
    }

    draw(pose.support);
    paint
      ..strokeWidth = 1.9
      ..color = figureColor;
    draw(pose.figure);
    final (x, y) = pose.head;
    canvas.drawCircle(Offset(x, y), 2.2, paint..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_PosePainter oldDelegate) =>
      pose != oldDelegate.pose ||
      figureColor != oldDelegate.figureColor ||
      supportColor != oldDelegate.supportColor;
}
