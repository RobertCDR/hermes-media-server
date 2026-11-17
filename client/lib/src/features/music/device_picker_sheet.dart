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
  });

  final List<OnlineDeviceModel> devices;
  final String? activeRendererDeviceId;
  final String localDeviceId;
  final ValueChanged<String> onSelectDevice;

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

    final otherDevices = devices
        .where((d) => d.deviceId != activeDevice?.deviceId)
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
        ],
      ),
    );
  }
}
