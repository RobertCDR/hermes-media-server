FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
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

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /data/artwork /tmp/hermes-transcodes \
    && chown -R $APP_UID:$APP_UID /data/artwork /tmp/hermes-transcodes /app

USER $APP_UID
EXPOSE 8080

ENV ASPNETCORE_HTTP_PORTS=8080 \
    DOTNET_EnableDiagnostics=0

COPY --from=build --chown=$APP_UID:$APP_UID /app/publish ./

ENTRYPOINT ["dotnet", "Hermes.Api.dll"]
