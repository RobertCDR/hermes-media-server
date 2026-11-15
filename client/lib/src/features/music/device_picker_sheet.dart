import 'package:material_ui/material_ui.dart';
import '../../core/theme/hermes_theme_tokens.dart';
import 'music_models.dart';

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

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connect to a Device',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (devices.isEmpty)
              Text(
                'No connected devices reported.',
                style: TextStyle(color: tokens.textSecondary),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: devices.map((device) {
                    final isActive = device.deviceId == activeRendererDeviceId;
                    final isThisDevice = device.deviceId == localDeviceId;
                    final label = isThisDevice ? '${device.deviceName} (This device)' : device.deviceName;

                    return ListTile(
                      leading: Icon(
                        device.platform.toLowerCase().contains('android')
                            ? Icons.smartphone
                            : Icons.computer,
                        color: isActive ? tokens.accentPrimary : tokens.textSecondary,
                      ),
                      title: Text(
                        label,
                        style: TextStyle(
                          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                          color: isActive ? tokens.accentHover : tokens.textPrimary,
                        ),
                      ),
                      subtitle: Text(isActive ? 'Playing here' : device.platform),
                      trailing: isActive ? Icon(Icons.graphic_eq, color: tokens.accentPrimary) : null,
                      onTap: () => onSelectDevice(device.deviceId),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
