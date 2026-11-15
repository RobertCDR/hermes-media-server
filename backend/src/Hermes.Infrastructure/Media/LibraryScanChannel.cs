using System.Threading.Channels;

namespace Hermes.Infrastructure.Media;

public sealed class LibraryScanChannel
{
    private readonly Channel<Guid> _channel = Channel.CreateUnbounded<Guid>(
        new UnboundedChannelOptions { SingleReader = true, SingleWriter = false });

    public ValueTask EnqueueScanAsync(Guid libraryRootId, CancellationToken cancellationToken) =>
        _channel.Writer.WriteAsync(libraryRootId, cancellationToken);

    public IAsyncEnumerable<Guid> ReadAllAsync(CancellationToken cancellationToken) =>
        _channel.Reader.ReadAllAsync(cancellationToken);
}
