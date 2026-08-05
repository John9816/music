class Membership {
  const Membership({
    required this.type,
    required this.typeName,
    required this.active,
    required this.lifetime,
    required this.expiresAt,
    required this.remainingSeconds,
  });

  final String? type;
  final String? typeName;
  final bool active;
  final bool lifetime;
  final DateTime? expiresAt;
  final int? remainingSeconds;

  factory Membership.fromJson(Map<String, dynamic> json) {
    return Membership(
      type: json['type'] as String?,
      typeName: json['typeName'] as String?,
      active: json['active'] as bool? ?? false,
      lifetime: json['lifetime'] as bool? ?? false,
      expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
      remainingSeconds: (json['remainingSeconds'] as num?)?.toInt(),
    );
  }
}

class RedeemResult {
  const RedeemResult({required this.message, required this.membership});

  final String message;
  final Membership membership;

  factory RedeemResult.fromJson(Map<String, dynamic> json) {
    return RedeemResult(
      message: json['message'] as String? ?? '兑换成功',
      membership: Membership.fromJson(
        json['membership'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}
