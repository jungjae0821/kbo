enum PlateOutcome {
  strikeout('strikeout'),
  walk('walk'),
  hitByPitch('hit_by_pitch'),
  single('single'),
  doubleHit('double'),
  triple('triple'),
  homeRun('home_run'),
  otherOut('other_out');

  const PlateOutcome(this.key);
  final String key;
}

/// Event order is part of the engine's reproducibility contract (rules 2.0.0).
class EventProbabilities {
  EventProbabilities._(List<double> values)
      : values = List.unmodifiable(values);

  factory EventProbabilities.fromJson(Map<String, dynamic> json) {
    final values = PlateOutcome.values.map((event) {
      final value = json[event.key];
      if (value is! num || !value.isFinite || value < 0 || value > 1) {
        throw FormatException('Invalid probability: ${event.key}');
      }
      return value.toDouble();
    }).toList();
    final sum = values.fold(0.0, (a, b) => a + b);
    if ((sum - 1).abs() > 1e-8) {
      throw FormatException('Profile probabilities must sum to 1: $sum');
    }
    return EventProbabilities._(values);
  }

  /// Profiles are already smoothed by the Python dataset generator.
  static EventProbabilities matchup(
    EventProbabilities batter,
    EventProbabilities pitcher,
  ) {
    final values = List.generate(
      PlateOutcome.values.length,
      (i) => (batter.values[i] + pitcher.values[i]) / 2,
    );
    final sum = values.fold(0.0, (a, b) => a + b);
    return EventProbabilities._(values.map((p) => p / sum).toList());
  }

  final List<double> values;

  PlateOutcome sample(double draw) {
    if (!draw.isFinite || draw < 0 || draw >= 1) {
      throw ArgumentError.value(draw, 'draw', 'Expected 0 <= draw < 1');
    }
    var cumulative = 0.0;
    var lastPositive = PlateOutcome.otherOut;
    for (final event in PlateOutcome.values) {
      final probability = values[event.index];
      if (probability > 0) lastPositive = event;
      cumulative += probability;
      if (draw < cumulative) return event;
    }
    // Floating-point rounding must never select an event with zero weight.
    return lastPositive;
  }

  Map<String, double> toJson() => {
        for (final event in PlateOutcome.values) event.key: values[event.index],
      };
}

/// Park–Miller minimal standard. Integer products stay below 2^53, including
/// Dart web. Unlike dart:math Random, its algorithm is explicitly versioned.
class SeededRandom {
  SeededRandom(int seed) : _state = seed + 1 {
    if (seed < 0 || seed > 2147483645) {
      throw RangeError.range(seed, 0, 2147483645, 'seed');
    }
  }

  static const algorithm = 'park_miller_16807_v1';
  int _state;
  int get state => _state;

  double nextDouble() {
    _state = (_state * 16807) % 2147483647;
    return (_state - 1) / 2147483646;
  }
}
