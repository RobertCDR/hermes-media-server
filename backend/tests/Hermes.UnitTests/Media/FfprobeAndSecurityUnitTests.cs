using FluentAssertions;
using Hermes.Infrastructure.Media;
using Hermes.Infrastructure.Security;
using Xunit;

namespace Hermes.UnitTests.Media;

public class FfprobeAndSecurityUnitTests
{
    [Fact]
    public async Task FfprobeMediaProbeService_ReturnsNullForMissingFile_AndFallsBackFromFilenameForDummyFiles()
    {
        var svc = new FfprobeMediaProbeService();
        var missingPath = Path.Combine(Path.GetTempPath(), $"hermes-missing-{Guid.NewGuid():N}.mkv");
        (await svc.ProbeAsync(missingPath, CancellationToken.None)).Should().BeNull();

        var invalidFile = Path.Combine(Path.GetTempPath(), $"hermes-dummy-{Guid.NewGuid():N}.2160p.HDR.mp4");
        await File.WriteAllTextAsync(invalidFile, "not a real mp4 file");
        try
        {
            var probed = await svc.ProbeAsync(invalidFile, CancellationToken.None);
            probed.Should().NotBeNull();
            probed!.Container.Should().Be("mp4");
            probed.Width.Should().Be(3840);
            probed.Height.Should().Be(2160);
            probed.IsHdr.Should().BeTrue();
        }
        finally
        {
            if (File.Exists(invalidFile))
            {
                File.Delete(invalidFile);
            }
        }
    }

    [Fact]
    public void JwtTokenService_CreateOpaqueRefreshToken_GeneratesUrlSafeUnpaddedTokens()
    {
        var svc = new JwtTokenService(
            "this-is-a-strong-signing-key-at-least-32-bytes",
            "hermes-issuer",
            "hermes-audience");

        var t1 = svc.CreateOpaqueRefreshToken();
        var t2 = svc.CreateOpaqueRefreshToken();

        t1.Should().NotBeNullOrWhiteSpace();
        t1.Should().NotContain("+");
        t1.Should().NotContain("/");
        t1.Should().NotContain("=");
        t1.Should().NotBe(t2);
        svc.HashToken(t1).Should().HaveLength(64);
    }

    [Fact]
    public void HmacStreamTicketService_ValidatesRoundTrip_AndRejectsInvalidTamperedAndExpiredTickets()
    {
        var now = new DateTimeOffset(2026, 11, 22, 12, 0, 0, TimeSpan.Zero);
        var timeProvider = new MutableTimeProvider(now);
        var svc = new HmacStreamTicketService("stream-secret-at-least-16-chars", timeProvider);

        var userId = Guid.NewGuid();
        var sourceId = Guid.NewGuid();
        var ticket = svc.CreateStreamTicket(userId, sourceId, TimeSpan.FromMinutes(10));

        svc.TryValidateStreamTicket(ticket, sourceId, out var parsedUser).Should().BeTrue();
        parsedUser.Should().Be(userId);

        // Wrong source rejected
        svc.TryValidateStreamTicket(ticket, Guid.NewGuid(), out _).Should().BeFalse();

        // Malformed / whitespace / tampered tickets rejected
        svc.TryValidateStreamTicket("", sourceId, out _).Should().BeFalse();
        svc.TryValidateStreamTicket("not-two-parts", sourceId, out _).Should().BeFalse();
        svc.TryValidateStreamTicket("bad*chars.sig", sourceId, out _).Should().BeFalse();
        svc.TryValidateStreamTicket($"{ticket}x", sourceId, out _).Should().BeFalse();

        // Expired ticket rejected
        timeProvider.Advance(TimeSpan.FromMinutes(11));
        svc.TryValidateStreamTicket(ticket, sourceId, out _).Should().BeFalse();
    }

    private sealed class MutableTimeProvider(DateTimeOffset startUtc) : TimeProvider
    {
        private DateTimeOffset _utcNow = startUtc;

        public override DateTimeOffset GetUtcNow() => _utcNow;

        public void Advance(TimeSpan delta) => _utcNow = _utcNow.Add(delta);
    }
}
