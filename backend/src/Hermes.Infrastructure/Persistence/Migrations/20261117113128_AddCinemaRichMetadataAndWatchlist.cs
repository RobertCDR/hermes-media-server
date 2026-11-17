using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Hermes.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddCinemaRichMetadataAndWatchlist : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "CastJson",
                table: "TvSeries",
                type: "character varying(4000)",
                maxLength: 4000,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "GenresCsv",
                table: "TvSeries",
                type: "character varying(512)",
                maxLength: 512,
                nullable: true);

            migrationBuilder.AddColumn<double>(
                name: "Rating",
                table: "TvSeries",
                type: "double precision",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "ExpectedEpisodeCount",
                table: "TvSeasons",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "CastJson",
                table: "Movies",
                type: "character varying(4000)",
                maxLength: 4000,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "GenresCsv",
                table: "Movies",
                type: "character varying(512)",
                maxLength: 512,
                nullable: true);

            migrationBuilder.AddColumn<double>(
                name: "Rating",
                table: "Movies",
                type: "double precision",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "RuntimeMinutes",
                table: "Movies",
                type: "integer",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "WatchlistItems",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    MovieId = table.Column<Guid>(type: "uuid", nullable: true),
                    TvSeriesId = table.Column<Guid>(type: "uuid", nullable: true),
                    AddedAtUtc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_WatchlistItems", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_WatchlistItems_UserId_MovieId",
                table: "WatchlistItems",
                columns: new[] { "UserId", "MovieId" },
                unique: true,
                filter: "\"MovieId\" IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_WatchlistItems_UserId_TvSeriesId",
                table: "WatchlistItems",
                columns: new[] { "UserId", "TvSeriesId" },
                unique: true,
                filter: "\"TvSeriesId\" IS NOT NULL");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "WatchlistItems");

            migrationBuilder.DropColumn(
                name: "CastJson",
                table: "TvSeries");

            migrationBuilder.DropColumn(
                name: "GenresCsv",
                table: "TvSeries");

            migrationBuilder.DropColumn(
                name: "Rating",
                table: "TvSeries");

            migrationBuilder.DropColumn(
                name: "ExpectedEpisodeCount",
                table: "TvSeasons");

            migrationBuilder.DropColumn(
                name: "CastJson",
                table: "Movies");

            migrationBuilder.DropColumn(
                name: "GenresCsv",
                table: "Movies");

            migrationBuilder.DropColumn(
                name: "Rating",
                table: "Movies");

            migrationBuilder.DropColumn(
                name: "RuntimeMinutes",
                table: "Movies");
        }
    }
}
