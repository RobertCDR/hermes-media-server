using System.Collections.Concurrent;
using Hermes.Domain.Entities;
using Hermes.Domain.Ports;
using Hermes.Infrastructure.Persistence;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace Hermes.Api.Features.Music;

public sealed class PlaybackSessionLockProvider
{
    private readonly ConcurrentDictionary<Guid, SemaphoreSlim> _locks = new();

    public SemaphoreSlim GetLock(Guid userId) => _locks.GetOrAdd(userId, _ => new SemaphoreSlim(1, 1));
}

public sealed class PlaybackConnectService(
    HermesDbContext db,
    IDevicePresenceRegistry presenceRegistry,
    PlaybackSessionLockProvider lockProvider,
    TimeProvider timeProvider)
{
    public async Task<PlaybackSessionDto> GetOrCreateSessionAsync(Guid userId, CancellationToken cancellationToken)
    {
        var gate = lockProvider.GetLock(userId);
        await gate.WaitAsync(cancellationToken);
        try
        {
            var session = await EnsureSessionAsync(userId, cancellationToken);
            return MapSession(session);
        }
        finally
        {
            gate.Release();
        }
    }

    public async Task<PlaybackSessionDto> StartPlaybackAsync(
        Guid userId,
        string callerDeviceId,
        string callerDeviceName,
        StartPlaybackCommand command,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(command);

        if (command.QueueSongIds.Count == 0)
        {
            throw new HubException("Playback queue cannot be empty.");
        }

        var gate = lockProvider.GetLock(userId);
        await gate.WaitAsync(cancellationToken);
        try
        {
            var session = await EnsureSessionAsync(userId, cancellationToken);
            session.StartPlayback(
                callerDeviceId,
                callerDeviceName,
                command.QueueSongIds,
                command.StartIndex,
                timeProvider.GetUtcNow());

            await db.SaveChangesAsync(cancellationToken);
            return MapSession(session);
        }
        finally
        {
            gate.Release();
        }
    }

    public async Task<PlaybackSessionDto> ApplyTransportAsync(
        Guid userId,
        RemoteTransportCommand command,
        CancellationToken cancellationToken,
        string? callerDeviceId = null,
        string? callerDeviceName = null)
    {
        ArgumentNullException.ThrowIfNull(command);

        var gate = lockProvider.GetLock(userId);
        await gate.WaitAsync(cancellationToken);
        try
        {
            var session = await EnsureSessionAsync(userId, cancellationToken);
            session.ApplyRemoteTransport(
                command.State,
                command.CurrentIndex,
                command.PositionMs,
                timeProvider.GetUtcNow(),
                command.RepeatMode,
                command.Shuffle,
                command.Volume,
                command.QueueSongIds,
                callerDeviceId,
                callerDeviceName);

            await db.SaveChangesAsync(cancellationToken);
            return MapSession(session);
        }
        finally
        {
            gate.Release();
        }
    }

    public async Task<PlaybackSessionDto> TransferOutputAsync(
        Guid userId,
        TransferOutputCommand command,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(command);

        var target = presenceRegistry.GetOnlineDevices(userId)
            .FirstOrDefault(d => string.Equals(d.DeviceId, command.TargetDeviceId, StringComparison.Ordinal));
        if (target is null)
        {
            throw new HubException("Target device is not currently connected.");
        }

        var gate = lockProvider.GetLock(userId);
        await gate.WaitAsync(cancellationToken);
        try
        {
            var session = await EnsureSessionAsync(userId, cancellationToken);
            session.TransferOutput(target.DeviceId, target.DeviceName, timeProvider.GetUtcNow(), command.PositionMs);
            await db.SaveChangesAsync(cancellationToken);
            return MapSession(session);
        }
        finally
        {
            gate.Release();
        }
    }

    public async Task<PlaybackSessionDto?> UpdateProgressAsync(
        Guid userId,
        string callerDeviceId,
        long positionMs,
        CancellationToken cancellationToken)
    {
        var gate = lockProvider.GetLock(userId);
        await gate.WaitAsync(cancellationToken);
        try
        {
            var session = await db.PlaybackSessions
                .SingleOrDefaultAsync(s => s.UserId == userId, cancellationToken);
            if (session is null || !string.Equals(session.ActiveRendererDeviceId, callerDeviceId, StringComparison.Ordinal))
            {
                return null;
            }

            session.UpdateProgress(positionMs, timeProvider.GetUtcNow());
            await db.SaveChangesAsync(cancellationToken);
            return MapSession(session);
        }
        finally
        {
            gate.Release();
        }
    }

    public async Task<PlaybackSessionDto?> HandleDisconnectAsync(
        Guid userId,
        string disconnectedDeviceId,
        CancellationToken cancellationToken)
    {
        var gate = lockProvider.GetLock(userId);
        await gate.WaitAsync(cancellationToken);
        try
        {
            var session = await db.PlaybackSessions
                .SingleOrDefaultAsync(s => s.UserId == userId, cancellationToken);
            if (session is null)
            {
                return null;
            }

            if (!session.HandleDeviceDisconnected(disconnectedDeviceId, timeProvider.GetUtcNow()))
            {
                return null;
            }

            await db.SaveChangesAsync(cancellationToken);
            return MapSession(session);
        }
        finally
        {
            gate.Release();
        }
    }

    private async Task<PlaybackSession> EnsureSessionAsync(Guid userId, CancellationToken cancellationToken)
    {
        var session = await db.PlaybackSessions
            .SingleOrDefaultAsync(s => s.UserId == userId, cancellationToken);
        if (session is null)
        {
            session = PlaybackSession.CreateForUser(userId);
            db.PlaybackSessions.Add(session);
            await db.SaveChangesAsync(cancellationToken);
        }

        return session;
    }

    public static PlaybackSessionDto MapSession(PlaybackSession session) =>
        new(
            session.Id,
            session.UserId,
            session.Version,
            session.ActiveRendererDeviceId,
            session.ActiveRendererDeviceName,
            session.State,
            session.RepeatMode,
            session.Shuffle,
            session.Volume,
            session.CurrentIndex,
            session.CurrentSongId,
            session.PositionMs,
            session.QueueSongIds,
            session.UpdatedAtUtc);
}
