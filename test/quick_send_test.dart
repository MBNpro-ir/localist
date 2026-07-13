import 'package:flutter_test/flutter_test.dart';
import 'package:localist/services/quick_send_service.dart';

void main() {
  test('Quick Send strips traversal and invalid file-name characters', () {
    expect(
      QuickSendService.sanitizeFileName(r'..\..\report:final?.pdf'),
      'report_final_.pdf',
    );
    expect(QuickSendService.sanitizeFileName('../'), 'received-file');
  });
}
