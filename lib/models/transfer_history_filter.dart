import '../services/quick_send_service.dart';

enum HistorySort { newest, oldest, name, largest, smallest, device }

enum HistoryPeriod { all, today, week, month }

class TransferHistoryFilter {
  const TransferHistoryFilter({
    this.query = '',
    this.category = 'All',
    this.period = HistoryPeriod.all,
    this.state,
    this.sort = HistorySort.newest,
  });
  final String query;
  final String category;
  final HistoryPeriod period;
  final QuickSendTransferState? state;
  final HistorySort sort;

  List<QuickSendTransfer> apply(
    List<QuickSendTransfer> records, {
    DateTime? now,
  }) {
    final date = now ?? DateTime.now();
    final cutoff = switch (period) {
      HistoryPeriod.all => null,
      HistoryPeriod.today => DateTime(date.year, date.month, date.day),
      HistoryPeriod.week => date.subtract(const Duration(days: 7)),
      HistoryPeriod.month => date.subtract(const Duration(days: 30)),
    };
    final text = query.trim().toLowerCase();
    final result = records
        .where(
          (file) =>
              (category == 'All' || categoryOf(file) == category) &&
              (cutoff == null || !file.updatedAt.isBefore(cutoff)) &&
              (state == null || file.state == state) &&
              (text.isEmpty ||
                  '${file.fileName} ${file.deviceName} ${file.path}'
                      .toLowerCase()
                      .contains(text)),
        )
        .toList();
    result.sort((a, b) {
      final value = switch (sort) {
        HistorySort.newest => b.updatedAt.compareTo(a.updatedAt),
        HistorySort.oldest => a.updatedAt.compareTo(b.updatedAt),
        HistorySort.name => a.fileName.toLowerCase().compareTo(
          b.fileName.toLowerCase(),
        ),
        HistorySort.largest => b.totalBytes.compareTo(a.totalBytes),
        HistorySort.smallest => a.totalBytes.compareTo(b.totalBytes),
        HistorySort.device => a.deviceName.toLowerCase().compareTo(
          b.deviceName.toLowerCase(),
        ),
      };
      return value == 0 ? a.id.compareTo(b.id) : value;
    });
    return result;
  }

  static String categoryOf(QuickSendTransfer file) =>
      QuickSendService.receiveCategoryFor(
        file.fileName,
        'application/octet-stream',
      );
}
