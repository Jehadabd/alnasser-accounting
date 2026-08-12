// lib/models/smart_pricing_models.dart

class PriceCandidate {
  final double price;
  int score = 0;
  final List<String> reasons = [];

  PriceCandidate({required this.price});

  void addPoints(int points, String reason) {
    score += points;
    reasons.add(reason);
  }
}

class SmartPricingResult {
  final double price;
  final double confidence;
  final String source;
  final String reason;
  final Map<double, int>? candidateScores;

  SmartPricingResult({
    required this.price,
    required this.confidence,
    required this.source,
    required this.reason,
    this.candidateScores,
  });
}
