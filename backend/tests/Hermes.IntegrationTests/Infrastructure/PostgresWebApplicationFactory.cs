using System.Security.Cryptography;
using Hermes.Infrastructure.Persistence;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Testcontainers.PostgreSql;
using Xunit;

namespace Hermes.IntegrationTests.Infrastructure;

public sealed class PostgresWebApplicationFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder("postgres:17-alpine").Build();
    private readonly string _jwtSigningKey = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
    private readonly string _streamTicketSecret = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
    private readonly string _artworkDirectory = Path.Combine(Path.GetTempPath(), $"hermes-art-{Guid.NewGuid():N}");

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        var connectionString = _postgres.GetConnectionString();
        builder.UseSetting("ConnectionStrings:Postgres", connectionString);
        builder.UseSetting("Security:JwtIssuer", "HermesMediaServer");
        builder.UseSetting("Security:JwtAudience", "HermesClients");
        builder.UseSetting("Security:JwtSigningKey", _jwtSigningKey);
        builder.UseSetting("Security:StreamTicketSecret", _streamTicketSecret);
        builder.UseSetting("Hermes:ArtworkDirectory", _artworkDirectory);

        builder.ConfigureAppConfiguration((_, config) =>
        {
            config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:Postgres"] = connectionString,
                ["Security:JwtIssuer"] = "HermesMediaServer",
                ["Security:JwtAudience"] = "HermesClients",
                ["Security:JwtSigningKey"] = _jwtSigningKey,
                ["Security:StreamTicketSecret"] = _streamTicketSecret,
                ["Hermes:ArtworkDirectory"] = _artworkDirectory
            });
        });
    }

    public async Task InitializeAsync()
    {
        Directory.CreateDirectory(_artworkDirectory);
        await _postgres.StartAsync();
        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<HermesDbContext>();
        await db.Database.MigrateAsync();
    }

    public new async Task DisposeAsync()
    {
        await base.DisposeAsync();
        await _postgres.DisposeAsync();
        if (Directory.Exists(_artworkDirectory))
        {
            Directory.Delete(_artworkDirectory, recursive: true);
        }
    }
}
