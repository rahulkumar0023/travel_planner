class BalanceRow {
  final String from;
  final String to;
  final double amount;
  final String currency;

  BalanceRow({
    required this.from,
    required this.to,
    required this.amount,
    required this.currency,
  });

  factory BalanceRow.fromJson(Map<String, dynamic> j) => BalanceRow(
        from: j['from'] ?? j['payer'] ?? j['owes'],
        to: j['to'] ?? j['payee'] ?? j['owedTo'],
        amount: (j['amount'] as num).toDouble(),
        currency: j['currency'] ?? 'EUR',
      );
}
