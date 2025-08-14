class GroupBalance {
  final String from; // who owes
  final String to; // who gets paid
  final double amount;
  final String currency;

  GroupBalance({
    required this.from,
    required this.to,
    required this.amount,
    required this.currency,
  });

  factory GroupBalance.fromJson(Map<String, dynamic> json) => GroupBalance(
        from: json['from'],
        to: json['to'],
        amount: (json['amount'] ?? 0).toDouble(),
        currency: json['currency'] ?? 'EUR',
      );
}
