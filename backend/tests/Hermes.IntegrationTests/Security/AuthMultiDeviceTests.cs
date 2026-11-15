using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using FluentAssertions;
using Hermes.Api.Features.Admin;
using Hermes.Api.Features.Auth;
using Hermes.Api.Features.Setup;
using Hermes.IntegrationTests.Infrastructure;
using Xunit;

namespace Hermes.IntegrationTests.Security;

public class AuthMultiDeviceTests
{
    [Fact]
    public async Task InviteRegistration_MultiDeviceLoginAndRefresh_PreservesOtherDeviceSession_AndPasswordChangeRevokesAll()
    {
        await using var factory = new PostgresWebApplicationFactory();
        await factory.InitializeAsync();

        using var client = factory.CreateClient();

        var setupResponse = await client.PostAsJsonAsync(
            "/api/v1/setup",
            new SetupRequest("admin", "AdminPass!123", "Hermes Home"));
        setupResponse.StatusCode.Should().Be(HttpStatusCode.Created);

        var adminLogin = await LoginAsync(client, "admin", "AdminPass!123", "admin-pc", "Admin Workstation");

        using var adminClient = factory.CreateClient();
        adminClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", adminLogin.AccessToken);

        var inviteResponse = await adminClient.PostAsJsonAsync(
            "/api/v1/admin/invites",
            new CreateInviteRequest(MaxUses: 2, ExpiresInHours: 24));
        inviteResponse.StatusCode.Should().Be(HttpStatusCode.Created);
        var invite = await inviteResponse.Content.ReadFromJsonAsync<InviteResponse>();
        invite.Should().NotBeNull();

        var registerResponse = await client.PostAsJsonAsync(
            "/api/v1/auth/register",
            new RegisterRequest("alice", "AlicePass!123", invite!.Code));
        registerResponse.StatusCode.Should().Be(HttpStatusCode.Created);

        var desktopSession = await LoginAsync(client, "alice", "AlicePass!123", "device-desktop", "Windows Desktop");
        var androidSession = await LoginAsync(client, "alice", "AlicePass!123", "device-android", "Pixel Phone");

        var desktopRefreshResponse = await client.PostAsJsonAsync(
            "/api/v1/auth/refresh",
            new RefreshTokenRequest("device-desktop", desktopSession.RefreshToken));
        desktopRefreshResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        var refreshedDesktop = await desktopRefreshResponse.Content.ReadFromJsonAsync<AuthTokenResponse>();
        refreshedDesktop.Should().NotBeNull();
        refreshedDesktop!.RefreshToken.Should().NotBe(desktopSession.RefreshToken);

        // Replaying the rotated token must fail
        var replayDesktop = await client.PostAsJsonAsync(
            "/api/v1/auth/refresh",
            new RefreshTokenRequest("device-desktop", desktopSession.RefreshToken));
        replayDesktop.StatusCode.Should().Be(HttpStatusCode.Unauthorized);

        // Other device remains independent and active
        var androidRefreshResponse = await client.PostAsJsonAsync(
            "/api/v1/auth/refresh",
            new RefreshTokenRequest("device-android", androidSession.RefreshToken));
        androidRefreshResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        var refreshedAndroid = await androidRefreshResponse.Content.ReadFromJsonAsync<AuthTokenResponse>();
        refreshedAndroid.Should().NotBeNull();

        // Password change revokes all device refresh tokens
        using var aliceClient = factory.CreateClient();
        aliceClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", refreshedDesktop.AccessToken);
        var changePasswordResponse = await aliceClient.PostAsJsonAsync(
            "/api/v1/auth/change-password",
            new ChangePasswordRequest("AlicePass!123", "NewAlicePass!456"));
        changePasswordResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var desktopAfterReset = await client.PostAsJsonAsync(
            "/api/v1/auth/refresh",
            new RefreshTokenRequest("device-desktop", refreshedDesktop.RefreshToken));
        desktopAfterReset.StatusCode.Should().Be(HttpStatusCode.Unauthorized);

        var androidAfterReset = await client.PostAsJsonAsync(
            "/api/v1/auth/refresh",
            new RefreshTokenRequest("device-android", refreshedAndroid!.RefreshToken));
        androidAfterReset.StatusCode.Should().Be(HttpStatusCode.Unauthorized);

        var relogin = await LoginAsync(client, "alice", "NewAlicePass!456", "device-desktop", "Windows Desktop");
        relogin.Username.Should().Be("alice");
    }

    [Fact]
    public async Task AdminOneTimeResetCode_AllowsUserPasswordReset()
    {
        await using var factory = new PostgresWebApplicationFactory();
        await factory.InitializeAsync();

        using var client = factory.CreateClient();
        await client.PostAsJsonAsync("/api/v1/setup", new SetupRequest("admin", "AdminPass!123", "Hermes Home"));
        var adminLogin = await LoginAsync(client, "admin", "AdminPass!123", "admin-pc", "Admin Workstation");

        using var adminClient = factory.CreateClient();
        adminClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", adminLogin.AccessToken);

        var invite = await (await adminClient.PostAsJsonAsync("/api/v1/admin/invites", new CreateInviteRequest(1, 24)))
            .Content.ReadFromJsonAsync<InviteResponse>();

        var registerResponse = await client.PostAsJsonAsync(
            "/api/v1/auth/register",
            new RegisterRequest("bob", "BobInitial!123", invite!.Code));
        registerResponse.StatusCode.Should().Be(HttpStatusCode.Created);
        var bobSession = await LoginAsync(client, "bob", "BobInitial!123", "bob-laptop", "Bob Laptop");

        var resetCodeResponse = await adminClient.PostAsync($"/api/v1/admin/users/{bobSession.UserId}/reset-code", content: null);
        resetCodeResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        var reset = await resetCodeResponse.Content.ReadFromJsonAsync<ResetCodeResponse>();
        reset.Should().NotBeNull();

        var resetPasswordResponse = await client.PostAsJsonAsync(
            "/api/v1/auth/reset-password",
            new ResetPasswordRequest("bob", reset!.ResetCode, "BobNewPass!789"));
        resetPasswordResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        // Old refresh token revoked and one-time reset code cannot be reused
        var refreshAfterReset = await client.PostAsJsonAsync(
            "/api/v1/auth/refresh",
            new RefreshTokenRequest("bob-laptop", bobSession.RefreshToken));
        refreshAfterReset.StatusCode.Should().Be(HttpStatusCode.Unauthorized);

        var reuseCodeResponse = await client.PostAsJsonAsync(
            "/api/v1/auth/reset-password",
            new ResetPasswordRequest("bob", reset.ResetCode, "AnotherPass!000"));
        reuseCodeResponse.StatusCode.Should().Be(HttpStatusCode.BadRequest);

        var newSession = await LoginAsync(client, "bob", "BobNewPass!789", "bob-laptop", "Bob Laptop");
        newSession.Username.Should().Be("bob");
    }

    private static async Task<AuthTokenResponse> LoginAsync(
        HttpClient client,
        string username,
        string password,
        string deviceId,
        string deviceName)
    {
        var response = await client.PostAsJsonAsync(
            "/api/v1/auth/login",
            new LoginRequest(username, password, deviceId, deviceName));
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var payload = await response.Content.ReadFromJsonAsync<AuthTokenResponse>();
        payload.Should().NotBeNull();
        return payload!;
    }
}
