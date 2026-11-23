FROM mcr.microsoft.com/dotnet/sdk:10.0@sha256:bef136a371963aaa46ec97882845ef6f54dec15728bb4b128b1c2a400ffbc9b4 AS build
WORKDIR /src

COPY global.json nuget.config ./
COPY backend/Hermes.slnx backend/Directory.Build.props backend/Directory.Packages.props ./backend/
COPY backend/src/Hermes.Domain/Hermes.Domain.csproj ./backend/src/Hermes.Domain/
COPY backend/src/Hermes.Infrastructure/Hermes.Infrastructure.csproj ./backend/src/Hermes.Infrastructure/
COPY backend/src/Hermes.Api/Hermes.Api.csproj ./backend/src/Hermes.Api/

RUN dotnet restore ./backend/src/Hermes.Api/Hermes.Api.csproj

COPY backend/src/ ./backend/src/
RUN dotnet publish ./backend/src/Hermes.Api/Hermes.Api.csproj \
    --configuration Release \
    --no-restore \
    --output /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:10.0@sha256:12b1135f5f8b3c0a214f2a680ff2033dff4f684f445d6c697d9524ceeb303586 AS runtime
WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg curl \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /data/artwork /tmp/hermes-transcodes \
    && chown -R $APP_UID:$APP_UID /data /tmp/hermes-transcodes /app

USER $APP_UID
EXPOSE 8080

ENV ASPNETCORE_HTTP_PORTS=8080 \
    DOTNET_EnableDiagnostics=0

COPY --from=build --chown=$APP_UID:$APP_UID /app/publish ./

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD ["curl", "-fsS", "--max-time", "3", "http://127.0.0.1:8080/health/live"]

ENTRYPOINT ["dotnet", "Hermes.Api.dll"]
