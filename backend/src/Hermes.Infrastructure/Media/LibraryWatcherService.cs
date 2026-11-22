using Hermes.Domain.Enums;
using Hermes.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Hermes.Infrastructure.Media;

/// <summary>
/// Watches <see cref="Domain.Entities.MediaLibraryRoot"/> folders with <c>WatchEnabled = true</c>
/// and enqueues debounced scans via <see cref="LibraryScanChannel"/> when media files change.
/// </summary>
public sealed class LibraryWatcherService : BackgroundService
{
    private static readonly string[] IgnoredSuffixes = [".tmp", ".part", ".crdownload", ".partial"];

    private readonly IServiceScopeFactory _scopeFactory;
    private readonly LibraryScanChannel _scanChannel;
    private readonly ILogger<LibraryWatcherService> _logger;
    private readonly TimeSpan _debounceDelay;
    private readonly TimeSpan _syncInterval;
    private readonly Lock _gate = new();
    private readonly SemaphoreSlim _refreshLock = new(1, 1);
    private readonly Dictionary<Guid, WatchedRootEntry> _watchers = [];
    private readonly Dictionary<Guid, CancellationTokenSource> _pendingDebounces = [];
    private CancellationToken _stoppingToken = CancellationToken.None;

    [ActivatorUtilitiesConstructor]
    public LibraryWatcherService(
        IServiceScopeFactory scopeFactory,
        LibraryScanChannel scanChannel,
        ILogger<LibraryWatcherService> logger)
        : this(scopeFactory, scanChannel, logger, TimeSpan.FromSeconds(3), TimeSpan.FromSeconds(60))
    {
    }

    internal LibraryWatcherService(
        IServiceScopeFactory scopeFactory,
        LibraryScanChannel scanChannel,
        ILogger<LibraryWatcherService> logger,
        TimeSpan debounceDelay,
        TimeSpan syncInterval)
    {
        _scopeFactory = scopeFactory;
        _scanChannel = scanChannel;
        _logger = logger;
        _debounceDelay = debounceDelay;
        _syncInterval = syncInterval;
    }

    internal IReadOnlyCollection<Guid> ActiveWatchedLibraryIds
    {
        get
        {
            lock (_gate)
            {
                return [.. _watchers.Keys];
            }
        }
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _stoppingToken = stoppingToken;

        try
        {
            await RefreshWatchersAsync(stoppingToken);

            using var timer = new PeriodicTimer(_syncInterval);
            while (await timer.WaitForNextTickAsync(stoppingToken))
            {
                await RefreshWatchersAsync(stoppingToken);
            }
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        {
            // Normal graceful shutdown.
        }
    }

    public async Task RefreshWatchersAsync(CancellationToken cancellationToken)
    {
        if (cancellationToken.IsCancellationRequested)
        {
            return;
        }

        await _refreshLock.WaitAsync(cancellationToken);
        try
        {
            List<WatchedRootSpec> desiredRoots;
            using (var scope = _scopeFactory.CreateScope())
            {
                var db = scope.ServiceProvider.GetRequiredService<HermesDbContext>();
                if (!await db.Database.CanConnectAsync(cancellationToken))
                {
                    return;
                }

                desiredRoots = await db.MediaLibraryRoots
                    .AsNoTracking()
                    .Where(r => r.WatchEnabled)
                    .Select(r => new WatchedRootSpec(r.Id, r.MediaType, r.RootPath))
                    .ToListAsync(cancellationToken);
            }

            SyncWatchers(desiredRoots);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            // Ignore shutdown cancellations.
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to synchronize library filesystem watchers.");
        }
        finally
        {
            _refreshLock.Release();
        }
    }

    internal void SyncWatchers(IReadOnlyList<WatchedRootSpec> desiredRoots)
    {
        var desiredById = desiredRoots
            .Where(r => !string.IsNullOrWhiteSpace(r.RootPath) && Directory.Exists(r.RootPath))
            .ToDictionary(r => r.Id);

        lock (_gate)
        {
            foreach (var existingId in _watchers.Keys.ToList())
            {
                var existing = _watchers[existingId];
                if (!desiredById.TryGetValue(existingId, out var desired) ||
                    existing.MediaType != desired.MediaType ||
                    !string.Equals(existing.RootPath, desired.RootPath, StringComparison.Ordinal))
                {
                    existing.Watcher.EnableRaisingEvents = false;
                    existing.Watcher.Dispose();
                    _watchers.Remove(existingId);
                }
            }

            foreach (var spec in desiredById.Values)
            {
                if (_watchers.ContainsKey(spec.Id))
                {
                    continue;
                }

                try
                {
                    var watcher = CreateWatcher(spec);
                    _watchers[spec.Id] = new WatchedRootEntry(spec.MediaType, spec.RootPath, watcher);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Unable to watch library folder {RootPath}.", spec.RootPath);
                }
            }
        }
    }

    internal static bool ShouldTriggerScan(LibraryMediaType mediaType, string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return false;
        }

        var fileName = Path.GetFileName(path);
        if (string.IsNullOrWhiteSpace(fileName) ||
            fileName.StartsWith('.') ||
            IgnoredSuffixes.Any(s => fileName.EndsWith(s, StringComparison.OrdinalIgnoreCase)))
        {
            return false;
        }

        if (Directory.Exists(path))
        {
            return true;
        }

        var ext = Path.GetExtension(path);
        if (string.IsNullOrEmpty(ext))
        {
            // Directory renames/deletes or extensionless paths should trigger reconciliation.
            return true;
        }

        return LibraryScannerService.IsSupportedMediaFileExtension(mediaType, ext);
    }

    internal void ScheduleDebouncedScan(Guid libraryRootId)
    {
        CancellationTokenSource? previous;
        CancellationTokenSource next;

        lock (_gate)
        {
            if (_stoppingToken.IsCancellationRequested)
            {
                return;
            }

            _pendingDebounces.TryGetValue(libraryRootId, out previous);
            next = CancellationTokenSource.CreateLinkedTokenSource(_stoppingToken);
            _pendingDebounces[libraryRootId] = next;
        }

        if (previous is not null)
        {
            try
            {
                previous.Cancel();
            }
            catch (ObjectDisposedException)
            {
                // Debounce task already exited and disposed this token source.
            }
        }

        _ = DebounceAndEnqueueAsync(libraryRootId, next);
    }

    private FileSystemWatcher CreateWatcher(WatchedRootSpec spec)
    {
        var watcher = new FileSystemWatcher(spec.RootPath)
        {
            IncludeSubdirectories = true,
            NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName | NotifyFilters.LastWrite | NotifyFilters.Size,
            InternalBufferSize = 32 * 1024,
        };

        void HandlePathEvent(string? path)
        {
            if (ShouldTriggerScan(spec.MediaType, path))
            {
                ScheduleDebouncedScan(spec.Id);
            }
        }

        watcher.Created += (_, e) => HandlePathEvent(e.FullPath);
        watcher.Changed += (_, e) => HandlePathEvent(e.FullPath);
        watcher.Deleted += (_, e) => HandlePathEvent(e.FullPath);
        watcher.Renamed += (_, e) =>
        {
            if (ShouldTriggerScan(spec.MediaType, e.FullPath) || ShouldTriggerScan(spec.MediaType, e.OldFullPath))
            {
                ScheduleDebouncedScan(spec.Id);
            }
        };
        watcher.Error += (_, e) =>
        {
            _logger.LogWarning(e.GetException(), "Filesystem watcher error for {RootPath}; scheduling recovery scan.", spec.RootPath);
            ScheduleDebouncedScan(spec.Id);
        };

        watcher.EnableRaisingEvents = true;
        return watcher;
    }

    private async Task DebounceAndEnqueueAsync(Guid libraryRootId, CancellationTokenSource cts)
    {
        try
        {
            await Task.Delay(_debounceDelay, cts.Token);
            await _scanChannel.EnqueueScanAsync(libraryRootId, _stoppingToken);
        }
        catch (OperationCanceledException)
        {
            // Superseded by newer event or shutting down.
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to enqueue debounced library scan for {LibraryRootId}.", libraryRootId);
        }
        finally
        {
            lock (_gate)
            {
                if (_pendingDebounces.TryGetValue(libraryRootId, out var current) && ReferenceEquals(current, cts))
                {
                    _pendingDebounces.Remove(libraryRootId);
                }
            }

            cts.Dispose();
        }
    }

    public override void Dispose()
    {
        List<FileSystemWatcher> watchers;
        List<CancellationTokenSource> debounces;

        lock (_gate)
        {
            watchers = _watchers.Values.Select(v => v.Watcher).ToList();
            debounces = [.. _pendingDebounces.Values];
            _watchers.Clear();
            _pendingDebounces.Clear();
        }

        foreach (var cts in debounces)
        {
            try
            {
                cts.Cancel();
            }
            catch
            {
                // Best-effort cancellation during shutdown; DebounceAndEnqueueAsync owns disposal.
            }
        }

        foreach (var watcher in watchers)
        {
            watcher.EnableRaisingEvents = false;
            watcher.Dispose();
        }

        _refreshLock.Dispose();
        base.Dispose();
    }

    internal sealed record WatchedRootSpec(Guid Id, LibraryMediaType MediaType, string RootPath);

    private sealed record WatchedRootEntry(LibraryMediaType MediaType, string RootPath, FileSystemWatcher Watcher);
}
