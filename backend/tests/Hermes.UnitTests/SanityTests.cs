using FluentAssertions;
using Hermes.Api.Features.System;
using Xunit;

namespace Hermes.UnitTests;

public class SanityTests
{
    [Fact]
    public void SystemInfoDto_PreservesServerIdentityAndSetupFlag()
    {
        var id = Guid.NewGuid();
        var dto = new SystemInfoDto(id, "Hermes Media Server", "1.0.0", false);

        dto.ServerId.Should().Be(id);
        dto.ServerName.Should().Be("Hermes Media Server");
        dto.Version.Should().Be("1.0.0");
        dto.SetupCompleted.Should().BeFalse();
    }
}
