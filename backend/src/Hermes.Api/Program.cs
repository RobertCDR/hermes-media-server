using Hermes.Api.Features.System;

var builder = WebApplication.CreateBuilder(args);

var app = builder.Build();

app.MapSystemEndpoints();

await app.RunAsync();

public partial class Program;
