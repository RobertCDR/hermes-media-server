using Hermes.Domain.Ports;

namespace Hermes.Infrastructure.Realtime;

public sealed class InMemoryDevicePresenceRegistry : IDevicePresenceRegistry
{
    private readonly Lock _sync = new();
    private readonly Dictionary<string, (Guid UserId, OnlineDeviceInfo Device)> _connections = new(StringComparer.Ordinal);
    private readonly Dictionary<Guid, Dictionary<string, OnlineDeviceInfo>> _userConnections = new();

    public void RegisterConnection(Guid userId, string connectionId, OnlineDeviceInfo device)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(connectionId);
        ArgumentNullException.ThrowIfNull(device);

        lock (_sync)
        {
            _connections[connectionId] = (userId, device);
            if (!_userConnections.TryGetValue(userId, out var userMap))
            {
                userMap = new Dictionary<string, OnlineDeviceInfo>(StringComparer.Ordinal);
                _userConnections[userId] = userMap;
            }

            userMap[connectionId] = device;
        }
    }

    public (Guid UserId, string DeviceId)? RemoveConnection(string connectionId)
    {
        if (string.IsNullOrWhiteSpace(connectionId))
        {
            return null;
        }

        lock (_sync)
        {
            if (!_connections.Remove(connectionId, out var entry))
            {
                return null;
            }

            if (_userConnections.TryGetValue(entry.UserId, out var userMap))
            {
                userMap.Remove(connectionId);
                if (userMap.Count == 0)
                {
                    _userConnections.Remove(entry.UserId);
                }
            }

            return (entry.UserId, entry.Device.DeviceId);
        }
    }

    public IReadOnlyList<OnlineDeviceInfo> GetOnlineDevices(Guid userId)
    {
        lock (_sync)
        {
            if (!_userConnections.TryGetValue(userId, out var userMap))
            {
                return [];
            }

            return userMap.Values
                .GroupBy(d => d.DeviceId, StringComparer.Ordinal)
                .Select(g => g.OrderByDescending(d => d.ConnectedAtUtc).First())
                .OrderBy(d => d.DeviceName, StringComparer.OrdinalIgnoreCase)
                .ThenBy(d => d.DeviceId, StringComparer.Ordinal)
                .ToList();
        }
    }

    public bool IsDeviceConnected(Guid userId, string deviceId)
    {
        if (string.IsNullOrWhiteSpace(deviceId))
        {
            return false;
        }

        lock (_sync)
        {
            return _userConnections.TryGetValue(userId, out var userMap) &&
                   userMap.Values.Any(d => string.Equals(d.DeviceId, deviceId, StringComparison.Ordinal));
        }
    }
}
