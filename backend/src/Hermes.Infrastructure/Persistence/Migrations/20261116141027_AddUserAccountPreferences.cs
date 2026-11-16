using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Hermes.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddUserAccountPreferences : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "AutoplayNextEpisode",
                table: "Users",
                type: "boolean",
                nullable: false,
                defaultValue: true);

            migrationBuilder.AddColumn<bool>(
                name: "MatchTitleColors",
                table: "Users",
                type: "boolean",
                nullable: false,
                defaultValue: true);

            migrationBuilder.AddColumn<bool>(
                name: "NormalizeVolume",
                table: "Users",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "SubtitleBackground",
                table: "Users",
                type: "character varying(16)",
                maxLength: 16,
                nullable: false,
                defaultValue: "shadow");

            migrationBuilder.AddColumn<string>(
                name: "SubtitleSize",
                table: "Users",
                type: "character varying(16)",
                maxLength: 16,
                nullable: false,
                defaultValue: "medium");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "AutoplayNextEpisode",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "MatchTitleColors",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "NormalizeVolume",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "SubtitleBackground",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "SubtitleSize",
                table: "Users");
        }
    }
}
