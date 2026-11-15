using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using FluentAssertions;
using Hermes.Api.Features.Auth;
using Hermes.Api.Features.Setup;
using Hermes.Domain.Ports;
using Hermes.Infrastructure.Security;
using Hermes.IntegrationTests.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Hermes.IntegrationTests.Security;

public class StreamTicketServiceTests
{
    [Fact]
    public void CreateAndValidate_AcceptsMatchingMediaSource_AndRejectsWrongSourceExpiredOrTampered()
    {
        var secret = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
        var service = new HmacStreamTicketService(secret);

        var userId = Guid.NewGuid();
        var mediaSourceId = Guid.NewGuid();
        var otherMediaSourceId = Guid.NewGuid();

        var validTicket = service.CreateStreamTicket(userId, mediaSourceId, TimeSpan.FromHours(6));
        service.TryValidateStreamTicket(validTicket, mediaSourceId, out var parsedUserId).Should().BeTrue();
        parsedUserId.Should().Be(userId);

        service.TryValidateStreamTicket(validTicket, otherMediaSourceId, out _).Should().BeFalse();

        var tamperedTicket = validTicket[..^2] + (validTicket[^2..] == "AA" ? "BB" : "AA");
        service.TryValidateStreamTicket(tamperedTicket, mediaSourceId, out _).Should().BeFalse();

        var expiredTicket = service.CreateStreamTicket(userId, mediaSourceId, TimeSpan.FromSeconds(-5));
        service.TryValidateStreamTicket(expiredTicket, mediaSourceId, out _).Should().BeFalse();
    }

    [Fact]
    public async Task IssueStreamTicketEndpoint_ReturnsTicketValidForRequestedMediaSource()
    {
        await using var factory = new PostgresWebApplicationFactory();
        await factory.InitializeAsync();

        using var client = factory.CreateClient();
        await client.PostAsJsonAsync("/api/v1/setup", new SetupRequest("admin", "AdminPass!123", "Hermes Home"));

        var loginResponse = await client.PostAsJsonAsync(
            "/api/v1/auth/login",
            new LoginRequest("admin", "AdminPass!123", "pc-1", "Desktop"));
        var login = await loginResponse.Content.ReadFromJsonAsync<AuthTokenResponse>();

        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", login!.AccessToken);
        var mediaSourceId = Guid.NewGuid();

        var ticketResponse = await client.PostAsJsonAsync(
            "/api/v1/auth/stream-tickets",
            new CreateStreamTicketRequest(mediaSourceId));
        ticketResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        var payload = await ticketResponse.Content.ReadFromJsonAsync<StreamTicketResponse>();
        payload.Should().NotBeNull();

        var ticketService = factory.Services.GetRequiredService<IStreamTicketService>();
        ticketService.TryValidateStreamTicket(payload!.Ticket, mediaSourceId, out var validatedUserId).Should().BeTrue();
        validatedUserId.Should().Be(login.UserId);
    }
}
