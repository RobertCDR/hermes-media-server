using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

namespace Hermes.Infrastructure.Media;

public sealed class LibraryScanWorker(
    LibraryScanChannel scanChannel,
    IServiceScopeFactory scopeFactory) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await foreach (var libraryRootId in scanChannel.ReadAllAsync(stoppingToken))
        {
            using var scope = scopeFactory.CreateScope();
            var scanner = scope.ServiceProvider.GetRequiredService<LibraryScannerService>();
            await scanner.ScanLibraryAsync(libraryRootId, stoppingToken);
        }
    }
}
