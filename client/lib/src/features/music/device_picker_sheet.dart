import 'package:material_ui/material_ui.dart';

import '../../core/theme/hermes_theme_tokens.dart';
import 'music_models.dart';
import 'music_shared_widgets.dart';

/// Compact Spotify-style Connect device switcher matching Figma `.connect-popover`.
/// Can be rendered either inside a floating popover overlay (desktop) or compact sheet (mobile).
class DevicePickerSheet extends StatelessWidget {
  const DevicePickerSheet({
    super.key,
    required this.devices,
    required this.activeRendererDeviceId,
    required this.localDeviceId,
    required this.onSelectDevice,
    this.volume,
    this.onVolumeChanged,
    this.onVolumeChangeEnd,
    this.onToggleMute,
    this.volumeTargetLabel,
  });

  final List<OnlineDeviceModel> devices;
  final String? activeRendererDeviceId;
  final String localDeviceId;
  final ValueChanged<String> onSelectDevice;
  final double? volume;
  final ValueChanged<double>? onVolumeChanged;
  final ValueChanged<double>? onVolumeChangeEnd;
  final VoidCallback? onToggleMute;
  final String? volumeTargetLabel;

  IconData _deviceIcon(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('android') || p.contains('ios') || p.contains('phone')) {
      return Icons.smartphone_rounded;
    }
    if (p.contains('tv') || p.contains('cast') || p.contains('speaker')) {
      return Icons.speaker_rounded;
    }
    return Icons.computer_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final activeDevice = devices
        .where((d) => d.deviceId == activeRendererDeviceId)
        .firstOrNull;
    final localInList = devices
        .where((d) => d.deviceId == localDeviceId)
        .firstOrNull;
    final currentDeviceName = activeDevice != null
        ? (activeDevice.deviceId == localDeviceId
            ? 'This Device (${activeDevice.deviceName})'
            : activeDevice.deviceName)
        : (localInList != null ? 'This Device (${localInList.deviceName})' : 'This Device');

    final excludeId = activeDevice?.deviceId ?? localDeviceId;
    final otherDevices = devices
        .where((d) => d.deviceId != excludeId)
        .toList();

    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: tokens.surface3,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                HermesEqBars(color: tokens.accent, height: 14),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current device',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: tokens.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        currentDeviceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: tokens.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Text(
              'Select another device',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: tokens.text,
              ),
            ),
          ),
          if (otherDevices.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Text(
                devices.isEmpty
                    ? 'No other Hermes clients online.'
                    : 'Open Hermes on another device to switch playback.',
                style: TextStyle(fontSize: 12, color: tokens.text2),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: otherDevices.length,
                itemBuilder: (context, index) {
                  final device = otherDevices[index];
                  final isThisDevice = device.deviceId == localDeviceId;
                  final label = isThisDevice
                      ? '${device.deviceName} (This device)'
                      : device.deviceName;

                  return InkWell(
                    onTap: () => onSelectDevice(device.deviceId),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _deviceIcon(device.platform),
                            size: 20,
                            color: tokens.text2,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: tokens.text,
                                  ),
                                ),
                                Text(
                                  device.platform,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: tokens.text2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          if (volume != null && onVolumeChanged != null)
            _DeviceVolumeSection(
              volume: volume!,
              label: volumeTargetLabel ?? 'Device volume',
              onVolumeChanged: onVolumeChanged!,
              onVolumeChangeEnd: onVolumeChangeEnd,
              onToggleMute: onToggleMute,
            ),
        ],
      ),
    );
  }
}

class _DeviceVolumeSection extends StatefulWidget {
  const _DeviceVolumeSection({
    required this.volume,
    required this.label,
    required this.onVolumeChanged,
    this.onVolumeChangeEnd,
    this.onToggleMute,
  });

  final double volume;
  final String label;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<double>? onVolumeChangeEnd;
  final VoidCallback? onToggleMute;

  @override
  State<_DeviceVolumeSection> createState() => _DeviceVolumeSectionState();
}

class _DeviceVolumeSectionState extends State<_DeviceVolumeSection> {
  double? _dragVolume;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effective = (_dragVolume ?? widget.volume).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(
            height: 1,
            color: Colors.white.withValues(alpha: 0.08),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton(
                tooltip: effective == 0 ? 'Unmute' : 'Mute',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                onPressed: widget.onToggleMute,
                icon: Icon(
                  effective == 0
                      ? Icons.volume_off_rounded
                      : effective < 0.5
                          ? Icons.volume_down_rounded
                          : Icons.volume_up_rounded,
                  size: 20,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(effective * 100).round()}%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 24,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          activeTrackColor: scheme.primary,
                          inactiveTrackColor:
                              Colors.white.withValues(alpha: 0.16),
                          thumbColor: scheme.onSurface,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 12,
                          ),
                        ),
                        child: Slider(
                          value: effective,
                          min: 0.0,
                          max: 1.0,
                          onChanged: (v) {
                            setState(() => _dragVolume = v);
                            widget.onVolumeChanged(v);
                          },
                          onChangeEnd: (v) {
                            setState(() => _dragVolume = null);
                            widget.onVolumeChangeEnd?.call(v);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
