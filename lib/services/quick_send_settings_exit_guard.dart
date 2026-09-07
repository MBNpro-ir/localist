class QuickSendSettingsExitGuard {
  QuickSendSettingsExitGuard._();

  static final instance = QuickSendSettingsExitGuard._();

  Future<bool> Function()? _prepareForExit;

  void attach(Future<bool> Function() prepareForExit) {
    _prepareForExit = prepareForExit;
  }

  void detach() {
    _prepareForExit = null;
  }

  Future<bool> prepareForExit() async {
    return _prepareForExit?.call() ?? true;
  }
}
