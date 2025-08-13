class GroupBalance {
  final String from; // who owes
  final String to; // who is owed
  final double amount;
  final String currency;

  GroupBalance({
    required this.from,
    required this.to,
    required this.amount,
    required this.currency,
  });

  factory GroupBalance.fromJson(Map<String, dynamic> j) => GroupBalance(
        from: j['from'] as String,
        to: j['to'] as String,
        amount: (j['amount'] as num).toDouble(),
        currency: (j['currency'] ?? 'EUR') as String,
      );
}

