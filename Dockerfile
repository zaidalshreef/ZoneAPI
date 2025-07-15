# --- Simple one‑stage build + runtime ----------------------------------------
FROM mcr.microsoft.com/dotnet/sdk:7.0

# ---------- prerequisites ----------------------------------------------------
# NuGet uses HTTPS; make sure root CAs exist, then install EF CLI tool
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && dotnet tool install --global dotnet-ef --version 7.0.20

ENV PATH="$PATH:/root/.dotnet/tools"

# ---------- restore, build, publish -----------------------------------------
WORKDIR /workspace
COPY ZoneAPI/ZoneAPI.csproj ZoneAPI/
RUN dotnet restore ZoneAPI/ZoneAPI.csproj

COPY . .
WORKDIR /workspace/ZoneAPI
RUN dotnet publish -c Release -o /out /p:UseAppHost=false

# ---------- build EF Core bundle and place at expected location --------------
RUN mkdir -p /app \
    && dotnet ef migrations bundle \
    --configuration Release \
    --output /app/efbundle \
    --self-contained --target-runtime linux-x64 \
    && chmod +x /app/efbundle

# ---------- switch to app directory & non‑root user --------------------------
ARG APP_UID=10001
RUN adduser --disabled-login --gecos '' --uid ${APP_UID} appuser
WORKDIR /out
USER ${APP_UID}

EXPOSE 8080
ENTRYPOINT ["dotnet", "ZoneAPI.dll"] 