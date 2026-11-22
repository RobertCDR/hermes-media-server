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

    [Fact]
    public async Task AccountPreferences_GetAndUpdate_SyncsAndValidatesInputs()
    {
        await using var factory = new PostgresWebApplicationFactory();
        await factory.InitializeAsync();

        using var client = factory.CreateClient();
        await client.PostAsJsonAsync("/api/v1/setup", new SetupRequest("admin", "AdminPass!123", "Hermes Home"));
        var login = await LoginAsync(client, "admin", "AdminPass!123", "admin-pc", "Admin Workstation");

        using var authed = factory.CreateClient();
        authed.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", login.AccessToken);

        var initial = await authed.GetFromJsonAsync<AccountPreferencesDto>("/api/v1/auth/me/preferences");
        initial.Should().NotBeNull();
        initial!.AutoplayNextEpisode.Should().BeTrue();
        initial.NormalizeVolume.Should().BeFalse();
        initial.MatchTitleColors.Should().BeTrue();
        initial.SubtitleSize.Should().Be("medium");
        initial.SubtitleBackground.Should().Be("shadow");

        var updateResponse = await authed.PutAsJsonAsync(
            "/api/v1/auth/me/preferences",
            new UpdateAccountPreferencesRequest(false, true, false, "large", "box"));
        updateResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        var updated = await updateResponse.Content.ReadFromJsonAsync<AccountPreferencesDto>();
        updated!.AutoplayNextEpisode.Should().BeFalse();
        updated.NormalizeVolume.Should().BeTrue();
        updated.MatchTitleColors.Should().BeFalse();
        updated.SubtitleSize.Should().Be("large");
        updated.SubtitleBackground.Should().Be("box");

        var fetchedAgain = await authed.GetFromJsonAsync<AccountPreferencesDto>("/api/v1/auth/me/preferences");
        fetchedAgain.Should().Be(updated);

        var badResponse = await authed.PutAsJsonAsync(
            "/api/v1/auth/me/preferences",
            new UpdateAccountPreferencesRequest(true, false, true, "invalid", "shadow"));
        badResponse.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Register_ConcurrentSingleUseInvite_AndCaseInsensitiveUsername_EnforceAtomicity()
    {
        await using var factory = new PostgresWebApplicationFactory();
        await factory.InitializeAsync();

        using var client = factory.CreateClient();
        await client.PostAsJsonAsync("/api/v1/setup", new SetupRequest("admin", "AdminPass!123", "Hermes Home"));
        var adminLogin = await LoginAsync(client, "admin", "AdminPass!123", "admin-pc", "Admin Workstation");

        using var adminClient = factory.CreateClient();
        adminClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", adminLogin.AccessToken);

        var singleInvite = (await (await adminClient.PostAsJsonAsync("/api/v1/admin/invites", new CreateInviteRequest(MaxUses: 1, ExpiresInHours: 24)))
            .Content.ReadFromJsonAsync<InviteResponse>())!;

        // 6 concurrent registrations against a MaxUses=1 invite: only 1 may succeed.
        var barrier = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var registerTasks = Enumerable.Range(0, 6).Select(async idx =>
        {
            await barrier.Task;
            using var raceClient = factory.CreateClient();
            return await raceClient.PostAsJsonAsync(
                "/api/v1/auth/register",
                new RegisterRequest($"racer_{idx}", "RacerPass!123", singleInvite.Code));
        }).ToArray();

        barrier.SetResult();
        var responses = await Task.WhenAll(registerTasks);
        responses.Count(r => r.StatusCode == HttpStatusCode.Created).Should().Be(1);
        responses.Count(r => r.StatusCode == HttpStatusCode.BadRequest).Should().Be(5);

        // Case-insensitive duplicate username ("ADMIN") must be rejected with 409 Conflict.
        var extraInvite = (await (await adminClient.PostAsJsonAsync("/api/v1/admin/invites", new CreateInviteRequest(MaxUses: 2, ExpiresInHours: 24)))
            .Content.ReadFromJsonAsync<InviteResponse>())!;
        var duplicateCase = await client.PostAsJsonAsync(
            "/api/v1/auth/register",
            new RegisterRequest("ADMIN", "OtherPass!123", extraInvite.Code));
        duplicateCase.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task Refresh_ConcurrentReplay_AllowsOnlySingleRotation()
    {
        await using var factory = new PostgresWebApplicationFactory();
        await factory.InitializeAsync();

        using var client = factory.CreateClient();
        await client.PostAsJsonAsync("/api/v1/setup", new SetupRequest("admin", "AdminPass!123", "Hermes Home"));
        var login = await LoginAsync(client, "admin", "AdminPass!123", "admin-pc", "Admin Workstation");

        var barrier = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var refreshTasks = Enumerable.Range(0, 6).Select(async _ =>
        {
            await barrier.Task;
            using var raceClient = factory.CreateClient();
            return await raceClient.PostAsJsonAsync(
                "/api/v1/auth/refresh",
                new RefreshTokenRequest("admin-pc", login.RefreshToken));
        }).ToArray();

        barrier.SetResult();
        var responses = await Task.WhenAll(refreshTasks);
        responses.Count(r => r.StatusCode == HttpStatusCode.OK).Should().Be(1);
        responses.Count(r => r.StatusCode == HttpStatusCode.Unauthorized).Should().Be(5);
    }

    [Fact]
    public async Task JwtValidation_RejectsTokensIssuedBeforePasswordChange_AndDeactivatedUsers()
    {
        await using var factory = new PostgresWebApplicationFactory();
        await factory.InitializeAsync();

        using var client = factory.CreateClient();
        await client.PostAsJsonAsync("/api/v1/setup", new SetupRequest("admin", "AdminPass!123", "Hermes Home"));
        var adminLogin = await LoginAsync(client, "admin", "AdminPass!123", "admin-pc", "Admin Workstation");

        using var adminClient = factory.CreateClient();
        adminClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", adminLogin.AccessToken);

        var invite = (await (await adminClient.PostAsJsonAsync("/api/v1/admin/invites", new CreateInviteRequest(1, 24)))
            .Content.ReadFromJsonAsync<InviteResponse>())!;
        (await client.PostAsJsonAsync("/api/v1/auth/register", new RegisterRequest("charlie", "CharliePass!123", invite.Code)))
            .StatusCode.Should().Be(HttpStatusCode.Created);

        var charlieSession1 = await LoginAsync(client, "charlie", "CharliePass!123", "dev-1", "Phone");
        using var oldTokenClient = factory.CreateClient();
        oldTokenClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", charlieSession1.AccessToken);
        (await oldTokenClient.GetAsync("/api/v1/auth/me/preferences")).StatusCode.Should().Be(HttpStatusCode.OK);

        // Advance past iat_ms tick before password change.
        await Task.Delay(25);
        (await oldTokenClient.PostAsJsonAsync(
            "/api/v1/auth/change-password",
            new ChangePasswordRequest("CharliePass!123", "CharlieNew!456"))).StatusCode.Should().Be(HttpStatusCode.OK);

        // Pre-change JWT must immediately fail for both endpoints and stream tickets.
        (await oldTokenClient.GetAsync("/api/v1/auth/me/preferences")).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        (await oldTokenClient.PostAsJsonAsync("/api/v1/auth/stream-tickets", new CreateStreamTicketRequest(Guid.NewGuid())))
            .StatusCode.Should().Be(HttpStatusCode.Unauthorized);

        // Fresh login after password change works immediately.
        var charlieSession2 = await LoginAsync(client, "charlie", "CharlieNew!456", "dev-1", "Phone");
        using var freshTokenClient = factory.CreateClient();
        freshTokenClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", charlieSession2.AccessToken);
        (await freshTokenClient.GetAsync("/api/v1/auth/me/preferences")).StatusCode.Should().Be(HttpStatusCode.OK);

        // Admin deactivates Charlie -> fresh JWT must be rejected immediately.
        (await adminClient.DeleteAsync($"/api/v1/admin/users/{charlieSession2.UserId}"))
            .StatusCode.Should().Be(HttpStatusCode.NoContent);
        (await freshTokenClient.GetAsync("/api/v1/auth/me/preferences")).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        (await freshTokenClient.PostAsJsonAsync("/api/v1/auth/stream-tickets", new CreateStreamTicketRequest(Guid.NewGuid())))
            .StatusCode.Should().Be(HttpStatusCode.Unauthorized);
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
