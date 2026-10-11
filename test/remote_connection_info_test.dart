import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/localist/connection_info.dart';

void main() {
  test('smart connection clipboard round trips encoded credentials', () {
    final original = RemoteConnectionInfo(id: '1234567890', password: 'p&?= فارسی');
    final parsed = RemoteConnectionInfo.parse(original.toClipboardText());
    expect(parsed.id, original.id);
    expect(parsed.password, original.password);
    expect(RemoteConnectionInfo.displayId(original.id), '1 234 567 890');
  });

  test('labelled copy text is accepted and plain IDs remain supported', () {
    final labelled = RemoteConnectionInfo.parse('ID: 123 456\nPassword: abc-123');
    expect(labelled.id, '123456');
    expect(labelled.password, 'abc-123');
    expect(RemoteConnectionInfo.parse('10.0.0.5:21116').id, '10.0.0.5:21116');
  });

  test('malformed links and unsafe IDs are rejected', () {
    expect(() => RemoteConnectionInfo.parse('localist://connect?v=2&id=123&password=x'),
        throwsFormatException);
    expect(() => RemoteConnectionInfo(id: 'bad id'), throwsFormatException);
    expect(() => RemoteConnectionInfo(id: '123', password: 'x\n'),
        throwsFormatException);
  });
}
