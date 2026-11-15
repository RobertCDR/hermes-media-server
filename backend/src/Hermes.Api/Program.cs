using Hermes.Api.Features.System;
using Hermes.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

var builder = WebApplication.CreateBuilder(args);

var connectionString = builder.Configuration.GetConnectionString("Postgres")
    ?? "Host=localhost;Port=5432;Database=hermes;Username=hermes;Password=hermes";

builder.Services.AddDbContext<HermesDbContext>(options =>
    options.UseNpgsql(connectionString));

var app = builder.Build();

app.MapSystemEndpoints();

await app.RunAsync();

public partial class Program;
