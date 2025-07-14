# Multi-stage Dockerfile for ZoneAPI
# Build stage
FROM mcr.microsoft.com/dotnet/sdk:7.0 AS build-env
WORKDIR /app

# Copy csproj and restore as distinct layers
COPY ZoneAPI/ZoneAPI.csproj ZoneAPI/
RUN dotnet restore ZoneAPI/ZoneAPI.csproj

# Copy everything else and build
COPY ZoneAPI/ ZoneAPI/
WORKDIR /app/ZoneAPI
RUN dotnet publish -c Release -o out

# Install EF Core tools globally and add to PATH
RUN dotnet tool install --global dotnet-ef --version 7.0.4
ENV PATH="$PATH:/root/.dotnet/tools"

# Create migration bundle
RUN dotnet ef migrations bundle -o efbundle --self-contained -r linux-x64 --verbose

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:7.0
WORKDIR /app

# Create non-root user for security
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Install curl for health checks
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Copy published application
COPY --from=build-env /app/ZoneAPI/out .

# Copy migration bundle
COPY --from=build-env /app/ZoneAPI/efbundle ./efbundle

# Change ownership to appuser
RUN chown -R appuser:appuser /app
USER appuser

# Expose port
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

# Entry point
ENTRYPOINT ["dotnet", "ZoneAPI.dll"] 