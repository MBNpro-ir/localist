import 'package:flutter/material.dart';
import '../services/capture_audio_settings.dart';

/// The same controls configure the sender or one independent receiver.
class CaptureAudioControls extends StatefulWidget {
  const CaptureAudioControls({
    super.key,
    required this.settings,
    required this.onChanged,
    this.sender = false,
    this.windows = false,
    this.enabled = true,
    this.echo = true,
    this.noise = true,
    this.autoGain = true,
    this.onEffects,
    this.loadDevices,
  });
  final CaptureAudioSettings settings;
  final ValueChanged<CaptureAudioSettings> onChanged;
  final bool sender, windows, enabled, echo, noise, autoGain;
  final ValueChanged<Map<String, dynamic>>? onEffects;
  final Future<Map<String, dynamic>> Function()? loadDevices;
  @override
  State<CaptureAudioControls> createState() => _CaptureAudioControlsState();
}

class _CaptureAudioControlsState extends State<CaptureAudioControls> {
  Future<Map<String, dynamic>>? _devices;
  double? _gain;
  double? _minimum, _maximum;
  String t(String fa, String en) =>
      Localizations.localeOf(context).languageCode == 'fa' ? fa : en;
  @override
  void initState() {
    super.initState();
    _devices = widget.loadDevices?.call();
  }

  void change(Map<String, dynamic> values) {
    if (widget.enabled) widget.onChanged(widget.settings.withValues(values));
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.sender) ...[
          DropdownButtonFormField<bool>(
            key: ValueKey('audio-quality-${settings.uncompressed}'),
            isExpanded: true,
            initialValue: settings.uncompressed,
            decoration: InputDecoration(
              labelText: t('کیفیت انتقال صدا', 'Audio quality'),
            ),
            items: [
              DropdownMenuItem(
                value: false,
                child: Text(t('فشرده · Opus', 'Compressed · Opus')),
              ),
              DropdownMenuItem(
                value: true,
                child: Text(t('بدون فشرده‌سازی · PCM', 'Uncompressed · PCM')),
              ),
            ],
            onChanged: widget.enabled
                ? (value) => change({'audioUncompressed': value})
                : null,
          ),
          if (!settings.uncompressed) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: ValueKey('audio-bitrate-${settings.bitrateKbps}'),
              isExpanded: true,
              initialValue: settings.bitrateKbps,
              decoration: InputDecoration(
                labelText: t('بیت‌ریت صدا', 'Audio bitrate'),
              ),
              items: [
                for (final rate in CaptureAudioSettings.bitrates)
                  DropdownMenuItem(
                    value: rate,
                    child: Text('$rate kb/s', textDirection: TextDirection.ltr),
                  ),
              ],
              onChanged: widget.enabled
                  ? (value) => change({'audioBitrate': value})
                  : null,
            ),
          ],
        ],
        if (widget.onEffects != null) ...[
          for (final entry in <String, ({String title, bool value})>{
            'echo': (
              title: t('حذف اکو', 'Echo cancellation'),
              value: widget.echo,
            ),
            'noise': (
              title: t('کاهش نویز', 'Noise suppression'),
              value: widget.noise,
            ),
            'gain': (
              title: t('تنظیم خودکار گین', 'Automatic gain'),
              value: widget.autoGain,
            ),
          }.entries)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(entry.value.title),
              value: entry.value.value,
              onChanged: widget.enabled
                  ? (v) => widget.onEffects!({entry.key: v})
                  : null,
            ),
        ],
        if (widget.sender)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              t('انتقال پیوسته در سکوت', 'Continuous audio through silence'),
            ),
            value: settings.continuous,
            onChanged: widget.enabled
                ? (v) => change({'audioContinuous': v})
                : null,
          ),
        const SizedBox(height: 12),
        Text(
          '${t('گین دستی', 'Manual gain')}: ${(_gain ?? settings.gainDb).toStringAsFixed(0)} dB',
        ),
        Slider(
          min: -30,
          max: 40,
          divisions: 70,
          value: _gain ?? settings.gainDb,
          label: '${(_gain ?? settings.gainDb).round()} dB',
          onChanged: widget.enabled ? (v) => setState(() => _gain = v) : null,
          onChangeEnd: (v) {
            setState(() => _gain = null);
            change({'audioGainDb': v});
          },
        ),
        if (!widget.sender) ...[
          if (!widget.windows) ...[
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: settings.outputBackend,
              key: ValueKey('audio-backend-${settings.outputBackend}'),
              decoration: InputDecoration(
                labelText: t('موتور خروجی صدا', 'Audio output engine'),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'audiotrack',
                  child: Text('AudioTrack'),
                ),
                DropdownMenuItem(value: 'opensl', child: Text('OpenSL ES')),
              ],
              onChanged: widget.enabled
                  ? (value) => change({
                      'audioOutputBackend': value,
                      'audioOutputDevice': '',
                    })
                  : null,
            ),
          ],
          if (widget.windows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'mic',
                    icon: const Icon(Icons.mic_none),
                    label: Text(t('میکروفون مجازی', 'Virtual microphone')),
                  ),
                  ButtonSegment(
                    value: 'playback',
                    icon: const Icon(Icons.headphones),
                    label: Text(t('پخش صدا', 'Playback')),
                  ),
                ],
                selected: {settings.outputMode},
                onSelectionChanged: widget.enabled
                    ? (v) => change({
                        'audioOutputMode': v.first,
                        'audioOutputDevice': '',
                      })
                    : null,
              ),
            ),
          if (_devices != null &&
              (widget.windows || settings.outputBackend == 'audiotrack'))
            FutureBuilder<Map<String, dynamic>>(
              future: _devices,
              builder: (context, snapshot) {
                final entries =
                    (snapshot.data?[settings.outputMode == 'mic'
                                    ? 'endpoints'
                                    : 'playbackEndpoints']
                                as List? ??
                            [])
                        .cast<Map>();
                final selected = settings.outputDevice;
                return DropdownButtonFormField<String>(
                  key: ValueKey(
                    'audio-device-${settings.outputMode}-$selected',
                  ),
                  isExpanded: true,
                  initialValue: entries.any((e) => e['id'] == selected)
                      ? selected
                      : '',
                  decoration: InputDecoration(
                    labelText: t('دستگاه خروجی صدا', 'Audio output device'),
                    suffixIcon: IconButton(
                      tooltip: t('تازه‌سازی', 'Refresh'),
                      icon: const Icon(Icons.refresh),
                      onPressed: () =>
                          setState(() => _devices = widget.loadDevices?.call()),
                    ),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(
                        settings.outputMode == 'mic'
                            ? t(
                                'کابل مستقل خالی',
                                'An unused independent cable',
                              )
                            : t('خروجی فعلی دستگاه', 'Current device output'),
                      ),
                    ),
                    for (final e in entries)
                      DropdownMenuItem(
                        value: e['id'] as String,
                        child: Text(
                          e['name'] as String,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: widget.enabled
                      ? (v) => change({'audioOutputDevice': v ?? ''})
                      : null,
                );
              },
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('audio-buffer-${settings.bufferMode}'),
            isExpanded: true,
            initialValue: settings.bufferMode,
            decoration: InputDecoration(
              labelText: t('حالت بافر', 'Buffer mode'),
            ),
            items: [
              for (final e in {
                'low': t('کم · بازی و گفت‌وگو', 'Low · games and conversation'),
                'medium': t('متعادل', 'Balanced'),
                'high': t('زیاد · شبکهٔ ناپایدار', 'High · unstable networks'),
                'custom': t('سفارشی', 'Custom'),
              }.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: widget.enabled
                ? (v) => change({'audioBufferMode': v})
                : null,
          ),
          if (settings.bufferMode == 'custom') ...[
            const SizedBox(height: 12),
            Text(
              '${t('حداقل بافر', 'Minimum buffer')}: ${(_minimum ?? settings.minBufferMs.toDouble()).round()} ms',
            ),
            Slider(
              min: 0,
              max: 1000,
              divisions: 100,
              value: _minimum ?? settings.minBufferMs.toDouble(),
              onChanged: widget.enabled
                  ? (v) => setState(() => _minimum = v)
                  : null,
              onChangeEnd: (v) {
                setState(() => _minimum = null);
                change({
                  'audioMinBuffer': v.round(),
                  'audioMaxBuffer': settings.maxBufferMs < v
                      ? v.round()
                      : settings.maxBufferMs,
                });
              },
            ),
            Text(
              '${t('حداکثر بافر', 'Maximum buffer')}: ${(_maximum ?? settings.maxBufferMs.toDouble()).round()} ms',
            ),
            Slider(
              min: 10,
              max: 1000,
              divisions: 99,
              value: _maximum ?? settings.maxBufferMs.toDouble(),
              onChanged: widget.enabled
                  ? (v) => setState(() => _maximum = v)
                  : null,
              onChangeEnd: (v) {
                setState(() => _maximum = null);
                change({
                  'audioMaxBuffer': v.round(),
                  'audioMinBuffer': settings.minBufferMs > v
                      ? v.round()
                      : settings.minBufferMs,
                });
              },
            ),
          ],
        ],
        if (!widget.sender)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(t('تنظیمات پیشرفتهٔ صدا', 'Advanced audio settings')),
            children: [
              if (!widget.sender && widget.windows)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('EventSync'),
                  value: settings.eventSync,
                  onChanged: widget.enabled
                      ? (v) => change({'audioEventSync': v})
                      : null,
                ),
              if (!widget.sender && !widget.windows) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    t(
                      'فعال‌سازی افکت‌های خروجی',
                      'Enable output audio effects',
                    ),
                  ),
                  value: settings.outputEffects,
                  onChanged: widget.enabled
                      ? (v) => change({'audioOutputEffects': v})
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    t('خروجی کم‌تأخیر AudioTrack', 'Low latency AudioTrack'),
                  ),
                  value: settings.lowLatency,
                  onChanged: widget.enabled
                      ? (v) => change({'audioLowLatency': v})
                      : null,
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey('audio-focus-${settings.focus}'),
                  isExpanded: true,
                  initialValue: settings.focus,
                  decoration: InputDecoration(
                    labelText: t('هم‌زمانی صدای برنامه‌ها', 'Audio focus'),
                  ),
                  items: [
                    for (final e in {
                      'exclusive': t(
                        'انحصاری · توقف با صدای برنامهٔ دیگر',
                        'Exclusive · pause for another app',
                      ),
                      'shared': t('پخش هم‌زمان', 'Mix with other apps'),
                      'calls': t(
                        'ادامه هنگام تماس، در صورت پشتیبانی دستگاه',
                        'Continue during calls, when supported',
                      ),
                    }.entries)
                      DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: widget.enabled
                      ? (v) => change({'audioFocus': v})
                      : null,
                ),
              ],
            ],
          ),
      ],
    );
  }
}
