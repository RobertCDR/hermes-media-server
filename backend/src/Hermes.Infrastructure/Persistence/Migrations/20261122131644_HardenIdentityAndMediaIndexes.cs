using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Hermes.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class HardenIdentityAndMediaIndexes : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateIndex(
                name: "IX_Songs_LibraryRootId",
                table: "Songs",
                column: "LibraryRootId");

            migrationBuilder.Sql(
                """CREATE UNIQUE INDEX IF NOT EXISTS "IX_Users_Username_Lower" ON "Users" (LOWER("Username"));""");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(
                """DROP INDEX IF EXISTS "IX_Users_Username_Lower";""");

            migrationBuilder.DropIndex(
                name: "IX_Songs_LibraryRootId",
                table: "Songs");
        }
    }
}
