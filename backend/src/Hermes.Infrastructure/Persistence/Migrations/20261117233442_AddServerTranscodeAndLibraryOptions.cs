using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Hermes.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddServerTranscodeAndLibraryOptions : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "HardwareAccelerationMode",
                table: "ServerSettings",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<bool>(
                name: "FetchMetadata",
                table: "MediaLibraryRoots",
                type: "boolean",
                nullable: false,
                defaultValue: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "HardwareAccelerationMode",
                table: "ServerSettings");

            migrationBuilder.DropColumn(
                name: "FetchMetadata",
                table: "MediaLibraryRoots");
        }
    }
}
