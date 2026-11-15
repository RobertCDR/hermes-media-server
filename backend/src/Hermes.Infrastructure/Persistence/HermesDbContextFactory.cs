using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace Hermes.Infrastructure.Persistence;

public sealed class HermesDbContextFactory : IDesignTimeDbContextFactory<HermesDbContext>
{
    public HermesDbContext CreateDbContext(string[] args)
    {
        var optionsBuilder = new DbContextOptionsBuilder<HermesDbContext>();
        var connectionString = Environment.GetEnvironmentVariable("ConnectionStrings__Postgres")
            ?? "Host=localhost;Port=5432;Database=hermes;Username=hermes;Password=hermes";

        optionsBuilder.UseNpgsql(connectionString);
        return new HermesDbContext(optionsBuilder.Options);
    }
}
