import 'package:flutter_test/flutter_test.dart';
import 'package:localist/models/transfer_history_filter.dart';
import 'package:localist/services/quick_send_service.dart';

void main() {
  final now = DateTime(2026, 10, 10, 12);
  QuickSendTransfer file(
    String id,
    String name,
    int size,
    DateTime date, {
    String device = 'iPhone',
    QuickSendTransferState state = QuickSendTransferState.completed,
  }) => QuickSendTransfer(
    id: id,
    deviceName: device,
    fileName: name,
    path: '/Download/Localist/$name',
    totalBytes: size,
    transferredBytes: size,
    direction: QuickSendDirection.receiving,
    state: state,
    message: '',
    updatedAt: date,
  );
  final records = [
    file('1', 'photo.jpg', 20, now),
    file('2', 'movie.mp4', 100, now.subtract(const Duration(days: 2))),
    file(
      '3',
      'song.mp3',
      30,
      now.subtract(const Duration(days: 10)),
      device: 'Windows',
    ),
    file('4', 'broken.pdf', 5, now, state: QuickSendTransferState.failed),
  ];
  test('history composes category/date/status and text search', () {
    expect(
      const TransferHistoryFilter(
        category: 'Images',
        period: HistoryPeriod.today,
        query: 'IPHONE',
        state: QuickSendTransferState.completed,
      ).apply(records, now: now).map((f) => f.id),
      ['1'],
    );
    expect(
      const TransferHistoryFilter(
        period: HistoryPeriod.week,
      ).apply(records, now: now),
      hasLength(3),
    );
    expect(
      const TransferHistoryFilter(query: 'missing').apply(records, now: now),
      isEmpty,
    );
  });
  test('history sorts size/name deterministically and preserves input', () {
    expect(
      const TransferHistoryFilter(
        sort: HistorySort.largest,
      ).apply(records).map((f) => f.id),
      ['2', '3', '1', '4'],
    );
    expect(
      const TransferHistoryFilter(
        sort: HistorySort.name,
      ).apply(records).first.fileName,
      'broken.pdf',
    );
    expect(records.first.id, '1');
  });
  test(
    'progress stays below completion until acknowledged; elapsed persists',
    () {
      final pending = file(
        'pending',
        'large.mp4',
        1000,
        now,
        state: QuickSendTransferState.transferring,
      );
      expect(pending.progress, .99);
      final updated = pending.copyWith(transferredBytes: 500);
      expect(updated.startedAt, pending.startedAt);
      expect(
        QuickSendTransfer.fromJson(updated.toJson()).startedAt,
        pending.startedAt,
      );
      expect(
        pending.copyWith(state: QuickSendTransferState.completed).progress,
        1,
      );
    },
  );
}
