using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Hermes.Api.Features.Setup;
using Hermes.Api.Features.System;
using Hermes.Infrastructure.Persistence;
using Hermes.IntegrationTests.Infrastructure;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Hermes.IntegrationTests.Security;

public class SetupEndpointTests
{
    [Fact]
    public async Task ConcurrentFirstRunSetup_AllowsExactlyOneAdminCreation_AndRejectsSecondWith409()
    {
        await using var factory = new PostgresWebApplicationFactory();
        await factory.InitializeAsync();

        using var client1 = factory.CreateClient();
        using var client2 = factory.CreateClient();

        var request = new SetupRequest("admin", "StrongAdminPass!123", "Hermes Cinema");

        var responses = await Task.WhenAll(
            client1.PostAsJsonAsync("/api/v1/setup", request),
            client2.PostAsJsonAsync("/api/v1/setup", request));

        responses.Count(r => r.StatusCode == HttpStatusCode.Created).Should().Be(1);
        responses.Count(r => r.StatusCode == HttpStatusCode.Conflict).Should().Be(1);

        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<HermesDbContext>();
        (await db.Users.CountAsync()).Should().Be(1);
        var settings = await db.ServerSettings.SingleAsync();
        settings.ServerName.Should().Be("Hermes Cinema");

        var info = await client1.GetFromJsonAsync<SystemInfoDto>("/api/v1/system/info");
        info.Should().NotBeNull();
        info!.SetupCompleted.Should().BeTrue();
        info.ServerName.Should().Be("Hermes Cinema");
        info.ServerId.Should().Be(settings.ServerId);
    }
}
