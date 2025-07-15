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

# Install EF Core tools globally and create migration bundle
RUN dotnet tool install --global dotnet-ef --version 7.0.4
ENV PATH="$PATH:/root/.dotnet/tools"
RUN dotnet ef migrations bundle --self-contained -o /app/efbundle

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
COPY --from=build-env /app/efbundle /app/efbundle
RUN chmod +x /app/efbundle

# Change ownership to appuser
RUN chown -R appuser:appuser /app
USER appuser

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Entry point
ENTRYPOINT ["dotnet", "ZoneAPI.dll"] 