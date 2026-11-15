using FluentAssertions;
using NetArchTest.Rules;
using Xunit;

namespace Hermes.UnitTests;

public class ArchitectureTests
{
    [Fact]
    public void Domain_ShouldNotDependOn_InfrastructureOrApi()
    {
        var result = Types.InAssembly(typeof(Hermes.Domain.AssemblyReference).Assembly)
            .ShouldNot()
            .HaveDependencyOnAny("Hermes.Infrastructure", "Hermes.Api")
            .GetResult();

        result.IsSuccessful.Should().BeTrue();
    }

    [Fact]
    public void Infrastructure_ShouldNotDependOn_Api()
    {
        var result = Types.InAssembly(typeof(Hermes.Infrastructure.AssemblyReference).Assembly)
            .ShouldNot()
            .HaveDependencyOn("Hermes.Api")
            .GetResult();

        result.IsSuccessful.Should().BeTrue();
    }
}
