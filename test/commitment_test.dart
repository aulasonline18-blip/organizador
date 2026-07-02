import 'package:flutter_test/flutter_test.dart';
import 'package:organizador/main.dart';

void main() {
  test('Commitment serializes and restores core fields', () {
    final dueAt = DateTime(2026, 7, 2, 14, 30);
    final createdAt = DateTime(2026, 7, 1, 9);
    final commitment = Commitment(
      id: 'abc',
      title: 'Pagar internet',
      description: 'Vencimento mensal',
      dueAt: dueAt,
      category: CommitmentCategory.conta,
      status: CommitmentStatus.pending,
      reminderOffsets: const [1440, 60, 0],
      createdAt: createdAt,
      repeatRule: RepeatRule.monthly,
      amount: 129.9,
      hasSensitiveData: true,
    );

    final restored = Commitment.fromJson(commitment.toJson());

    expect(restored.id, 'abc');
    expect(restored.title, 'Pagar internet');
    expect(restored.dueAt, dueAt);
    expect(restored.category, CommitmentCategory.conta);
    expect(restored.status, CommitmentStatus.pending);
    expect(restored.repeatRule, RepeatRule.monthly);
    expect(restored.reminderOffsets, [1440, 60, 0]);
    expect(restored.amount, 129.9);
    expect(restored.hasSensitiveData, isTrue);
  });
}
