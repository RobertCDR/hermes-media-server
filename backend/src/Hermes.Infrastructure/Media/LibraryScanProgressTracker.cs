using System.Collections.Concurrent;

namespace Hermes.Infrastructure.Media;

public sealed record LibraryScanProgressSnapshot(
    Guid LibraryRootId,
    bool IsScanning,
    int ProcessedFiles,
    int TotalFiles,
    DateTimeOffset StartedAtUtc);

/// <summary>
/// Thread-safe tracker recording live file discovery progress for active library scans.
/// </summary>
public sealed class LibraryScanProgressTracker
{
    private sealed class MutableScanState
    {
        public int ProcessedFiles;
        public int TotalFiles;
        public DateTimeOffset StartedAtUtc;
    }

    private readonly ConcurrentDictionary<Guid, MutableScanState> _active = new();
    private readonly ConcurrentDictionary<Guid, SemaphoreSlim> _locks = new();

    public async Task<IDisposable> AcquireScanLockAsync(Guid libraryRootId, CancellationToken cancellationToken)
    {
        var gate = _locks.GetOrAdd(libraryRootId, static _ => new SemaphoreSlim(1, 1));
        await gate.WaitAsync(cancellationToken);
        return new LockReleaser(gate);
    }

    private sealed class LockReleaser(SemaphoreSlim gate) : IDisposable
    {
        private int _disposed;

        public void Dispose()
        {
            if (Interlocked.Exchange(ref _disposed, 1) == 0)
            {
                gate.Release();
            }
        }
    }

    public void BeginScan(Guid libraryRootId, int totalFiles, DateTimeOffset? utcNow = null)
    {
        _active[libraryRootId] = new MutableScanState
        {
            ProcessedFiles = 0,
            TotalFiles = Math.Max(0, totalFiles),
            StartedAtUtc = utcNow ?? DateTimeOffset.UtcNow,
        };
    }

    public void Advance(Guid libraryRootId)
    {
        if (_active.TryGetValue(libraryRootId, out var state))
        {
            Interlocked.Increment(ref state.ProcessedFiles);
        }
    }

    public void Complete(Guid libraryRootId) => _active.TryRemove(libraryRootId, out _);

    public LibraryScanProgressSnapshot? GetProgress(Guid libraryRootId)
    {
        if (!_active.TryGetValue(libraryRootId, out var state))
        {
            return null;
        }

        var total = state.TotalFiles;
        var processed = Math.Clamp(Volatile.Read(ref state.ProcessedFiles), 0, Math.Max(total, Volatile.Read(ref state.ProcessedFiles)));
        return new LibraryScanProgressSnapshot(libraryRootId, true, processed, total, state.StartedAtUtc);
    }
}
