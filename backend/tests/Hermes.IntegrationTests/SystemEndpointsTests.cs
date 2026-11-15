using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Hermes.Api.Features.System;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace Hermes.IntegrationTests;

public class SystemEndpointsTests(WebApplicationFactory<Program> factory)
    : IClassFixture<WebApplicationFactory<Program>>
{
    [Fact]
    public async Task HealthLive_ReturnsOkHealthy()
    {
        using var client = factory.CreateClient();

        var response = await client.GetAsync("/health/live");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task SystemInfo_ReturnsServerMetadataAndUnconfiguredSetupState()
    {
        using var client = factory.CreateClient();

        var dto = await client.GetFromJsonAsync<SystemInfoDto>("/api/v1/system/info");

        dto.Should().NotBeNull();
        dto!.ServerId.Should().NotBe(Guid.Empty);
        dto.ServerName.Should().Be("Hermes Media Server");
        dto.SetupCompleted.Should().BeFalse();
    }
}
