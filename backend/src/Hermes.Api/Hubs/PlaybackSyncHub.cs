using Hermes.Api.Features.Music;
using Hermes.Api.Features.System;
using Hermes.Domain.Ports;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;

namespace Hermes.Api.Hubs;

[Authorize]
public sealed class PlaybackSyncHub(
    PlaybackConnectService connectService,
    IDevicePresenceRegistry presenceRegistry,
    TimeProvider timeProvider) : Hub
{
    public static string UserGroupName(Guid userId) => $"user:{userId:D}";

    public override async Task OnConnectedAsync()
    {
        var (userId, deviceId, deviceName, platform) = GetCallerIdentity();
        var groupName = UserGroupName(userId);

        presenceRegistry.RegisterConnection(
            userId,
            Context.ConnectionId,
            new OnlineDeviceInfo(deviceId, deviceName, platform, timeProvider.GetUtcNow()));

        await Groups.AddToGroupAsync(Context.ConnectionId, groupName, Context.ConnectionAborted);

        var session = await connectService.GetOrCreateSessionAsync(userId, Context.ConnectionAborted);
        await Clients.Caller.SendAsync("SessionStateUpdated", session, Context.ConnectionAborted);

        var devices = MapDevices(presenceRegistry.GetOnlineDevices(userId));
        await Clients.Group(groupName).SendAsync("DevicesUpdated", devices, Context.ConnectionAborted);

        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        var removed = presenceRegistry.RemoveConnection(Context.ConnectionId);
        if (removed is { } info)
        {
            var groupName = UserGroupName(info.UserId);
            if (!presenceRegistry.IsDeviceConnected(info.UserId, info.DeviceId))
            {
                var pausedSession = await connectService.HandleDisconnectAsync(
                    info.UserId,
                    info.DeviceId,
                    CancellationToken.None);

                if (pausedSession is not null)
                {
                    await Clients.Group(groupName).SendAsync("SessionStateUpdated", pausedSession, CancellationToken.None);
                }
            }

            var devices = MapDevices(presenceRegistry.GetOnlineDevices(info.UserId));
            await Clients.Group(groupName).SendAsync("DevicesUpdated", devices, CancellationToken.None);
        }

        await base.OnDisconnectedAsync(exception);
    }

    public async Task<PlaybackSessionDto> StartPlayback(StartPlaybackCommand command)
    {
        var (userId, deviceId, deviceName, _) = GetCallerIdentity();
        var updated = await connectService.StartPlaybackAsync(
            userId,
            deviceId,
            deviceName,
            command,
            Context.ConnectionAborted);

        await Clients.Group(UserGroupName(userId))
            .SendAsync("SessionStateUpdated", updated, Context.ConnectionAborted);

        return updated;
    }

    public async Task<PlaybackSessionDto> SendTransportCommand(RemoteTransportCommand command)
    {
        var (userId, _, _, _) = GetCallerIdentity();
        var updated = await connectService.ApplyTransportAsync(userId, command, Context.ConnectionAborted);

        await Clients.Group(UserGroupName(userId))
            .SendAsync("SessionStateUpdated", updated, Context.ConnectionAborted);

        return updated;
    }

    public async Task<PlaybackSessionDto> TransferOutput(TransferOutputCommand command)
    {
        var (userId, _, _, _) = GetCallerIdentity();
        var updated = await connectService.TransferOutputAsync(userId, command, Context.ConnectionAborted);

        await Clients.Group(UserGroupName(userId))
            .SendAsync("SessionStateUpdated", updated, Context.ConnectionAborted);

        return updated;
    }

    public async Task ReportProgress(ProgressHeartbeatCommand command)
    {
        var (userId, deviceId, _, _) = GetCallerIdentity();
        var updated = await connectService.UpdateProgressAsync(userId, deviceId, command.PositionMs, Context.ConnectionAborted);
        if (updated is not null)
        {
            await Clients.Group(UserGroupName(userId))
                .SendAsync("SessionStateUpdated", updated, Context.ConnectionAborted);
        }
    }

    public Task<IReadOnlyList<OnlineDeviceDto>> GetOnlineDevices()
    {
        var (userId, _, _, _) = GetCallerIdentity();
        return Task.FromResult(MapDevices(presenceRegistry.GetOnlineDevices(userId)));
    }

    private (Guid UserId, string DeviceId, string DeviceName, string Platform) GetCallerIdentity()
    {
        if (Context.User is null || !Context.User.TryGetUserId(out var userId))
        {
            throw new HubException("Unauthorized connection.");
        }

        var query = Context.GetHttpContext()?.Request.Query;
        var deviceId = query?["deviceId"].ToString();
        if (string.IsNullOrWhiteSpace(deviceId))
        {
            deviceId = Context.ConnectionId;
        }

        var deviceName = query?["deviceName"].ToString();
        if (string.IsNullOrWhiteSpace(deviceName))
        {
            deviceName = "Hermes Client";
        }

        var platform = query?["platform"].ToString();
        if (string.IsNullOrWhiteSpace(platform))
        {
            platform = "Unknown";
        }

        return (userId, deviceId.Trim(), deviceName.Trim(), platform.Trim());
    }

    private static IReadOnlyList<OnlineDeviceDto> MapDevices(IReadOnlyList<OnlineDeviceInfo> devices) =>
        devices.Select(d => new OnlineDeviceDto(d.DeviceId, d.DeviceName, d.Platform, d.ConnectedAtUtc)).ToList();
}
