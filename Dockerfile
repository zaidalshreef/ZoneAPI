# Build Stage
FROM mcr.microsoft.com/dotnet/sdk:7.0 AS build
WORKDIR /src

# Copy project files
COPY ["ZoneAPI/ZoneAPI.csproj", "ZoneAPI/"]
RUN dotnet restore "ZoneAPI/ZoneAPI.csproj"

# Copy everything else and build
COPY . .
WORKDIR "/src/ZoneAPI"
RUN dotnet build "ZoneAPI.csproj" -c Release -o /app/build

# Publish the application
FROM build AS publish
RUN dotnet publish "ZoneAPI.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Generate EF Core Migration Bundle (Industry Best Practice)
FROM build AS migrations
RUN dotnet tool install --global dotnet-ef
ENV PATH="$PATH:/root/.dotnet/tools"
RUN dotnet ef migrations bundle --configuration Release --output /app/efbundle --self-contained --target-runtime linux-x64

# Runtime Stage
FROM mcr.microsoft.com/dotnet/aspnet:7.0 AS final
WORKDIR /app
EXPOSE 8080

# Copy published application
COPY --from=publish /app/publish .

# Copy migration bundle
COPY --from=migrations /app/efbundle .

# Make migration bundle executable
RUN chmod +x efbundle

# Set non-root user
USER $APP_UID
ENTRYPOINT ["dotnet", "ZoneAPI.dll"] 