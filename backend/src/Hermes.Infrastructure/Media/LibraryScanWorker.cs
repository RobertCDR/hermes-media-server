using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Hermes.Infrastructure.Media;

public sealed class LibraryScanWorker(
    LibraryScanChannel scanChannel,
    IServiceScopeFactory scopeFactory,
    ILogger<LibraryScanWorker>? logger = null) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await foreach (var libraryRootId in scanChannel.ReadAllAsync(stoppingToken))
        {
            try
            {
                using var scope = scopeFactory.CreateScope();
                var scanner = scope.ServiceProvider.GetRequiredService<LibraryScannerService>();
                await scanner.ScanLibraryAsync(libraryRootId, stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                logger?.LogError(ex, "Failed to scan library root {LibraryRootId}.", libraryRootId);
            }
        }
    }
}
