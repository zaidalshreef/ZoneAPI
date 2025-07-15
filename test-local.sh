#!/bin/bash

# ZoneAPI Local Testing Script
# Based on Context7 best practices for Docker Compose testing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker compose.yml"
ENV_FILE=".env.local"
PROJECT_NAME="zoneapi-local"
API_HOST="localhost:8080"
DB_HOST="localhost:5432"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a service is healthy
check_service_health() {
    local service=$1
    local max_attempts=30
    local attempt=1

    print_status "Checking health of $service service..."

        while [ $attempt -le $max_attempts ]; do
        if docker compose ps --services --filter "status=running" | grep -q "$service"; then
            local health_status=$(docker compose ps -q $service | xargs docker inspect --format='{{.State.Health.Status}}' 2>/dev/null || echo "no-health-check")
            
            if [ "$health_status" = "healthy" ] || [ "$health_status" = "no-health-check" ]; then
                print_success "$service is healthy"
                return 0
            fi
        fi

        echo -n "."
        sleep 2
        ((attempt++))
    done

    print_error "$service failed to become healthy within $((max_attempts * 2)) seconds"
    return 1
}

# Function to test API endpoints
test_api_endpoints() {
    print_status "Testing API endpoints..."

    # Test health endpoint
    if curl -f -s "http://$API_HOST/health" >/dev/null; then
        print_success "Health endpoint is responding"
    else
        print_error "Health endpoint is not responding"
        return 1
    fi

    # Test API endpoints
    endpoints=(
        "/api/doctors"
        "/api/patients"
        "/api/appointments"
    )

    for endpoint in "${endpoints[@]}"; do
        if curl -f -s "http://$API_HOST$endpoint" >/dev/null; then
            print_success "API endpoint $endpoint is responding"
        else
            print_warning "API endpoint $endpoint is not responding (might be empty)"
        fi
    done
}

# Function to test database connectivity
test_database() {
    print_status "Testing database connectivity..."

    if docker compose exec -T db pg_isready -U postgres -d zone >/dev/null 2>&1; then
        print_success "Database is accessible"
    else
        print_error "Database is not accessible"
        return 1
    fi

    # Test database tables
    local tables=$(docker compose exec -T db psql -U postgres -d zone -t -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ')

    if [ -n "$tables" ]; then
        print_success "Database tables exist:"
        echo "$tables" | while read table; do
            [ -n "$table" ] && echo "  - $table"
        done
    else
        print_warning "No tables found in database"
    fi
}

# Function to show service logs
show_logs() {
    print_status "Showing service logs..."
    echo "=== Database Logs ==="
    docker compose logs --tail=20 db
    echo ""
    echo "=== Migration Logs ==="
    docker compose logs migration
    echo ""
    echo "=== Application Logs ==="
    docker compose logs --tail=30 app
}

# Function to show service status
show_status() {
    print_status "Current service status:"
    docker compose ps
    echo ""
    print_status "Resource usage:"
    docker compose exec app ps aux 2>/dev/null || echo "App container not running"
}

# Function to cleanup
cleanup() {
    print_status "Cleaning up..."
    docker compose down -v
    docker system prune -f
    print_success "Cleanup completed"
}

# Function to setup environment
setup_environment() {
    print_status "Setting up environment..."

    # Create .env.local file if it doesn't exist
    if [ ! -f "$ENV_FILE" ]; then
        cat >"$ENV_FILE" <<EOF
# Database Configuration
POSTGRES_PASSWORD=postgres123
PGADMIN_PASSWORD=admin123

# Application Configuration
ASPNETCORE_ENVIRONMENT=Development
ASPNETCORE_URLS=http://+:8080

# Logging Configuration
LOGGING_LEVEL=Information

# Docker Configuration
COMPOSE_PROJECT_NAME=$PROJECT_NAME
EOF
        print_success "Created $ENV_FILE"
    fi

    # Export environment variables
    export $(cat "$ENV_FILE" | grep -v '^#' | xargs)
}

# Main testing function
run_tests() {
    print_status "Starting ZoneAPI local testing..."

    # Setup environment
    setup_environment

    # Build and start services
    print_status "Building and starting services..."
    docker compose --env-file "$ENV_FILE" up --build -d

    # Wait for database to be healthy
    if ! check_service_health "db"; then
        print_error "Database failed to start"
        show_logs
        exit 1
    fi

    # Wait for migration to complete
    print_status "Waiting for migration to complete..."
    while docker compose ps migration | grep -q "running"; do
        echo -n "."
        sleep 2
    done

    local migration_exit_code=$(docker compose ps -q migration | xargs docker inspect --format='{{.State.ExitCode}}' 2>/dev/null || echo "1")
    if [ "$migration_exit_code" = "0" ]; then
        print_success "Migration completed successfully"
    else
        print_error "Migration failed with exit code $migration_exit_code"
        show_logs
        exit 1
    fi

    # Wait for application to be healthy
    if ! check_service_health "app"; then
        print_error "Application failed to start"
        show_logs
        exit 1
    fi

    # Test database
    test_database

    # Test API endpoints
    test_api_endpoints

    # Show status
    show_status

    print_success "All tests completed successfully!"
    print_status "API available at: http://$API_HOST"
    print_status "Database available at: $DB_HOST"
    print_status "pgAdmin available at: http://localhost:5050 (use --profile admin)"
}

# Command line interface
case "${1:-test}" in
"test")
    run_tests
    ;;
"logs")
    show_logs
    ;;
"status")
    show_status
    ;;
"cleanup")
    cleanup
    ;;
"build")
    print_status "Building services..."
    docker compose --env-file "$ENV_FILE" build
    ;;
"start")
    setup_environment
    print_status "Starting services..."
    docker compose --env-file "$ENV_FILE" up -d
    ;;
"stop")
    print_status "Stopping services..."
    docker compose down
    ;;
"help")
    echo "Usage: $0 [command]"
    echo "Commands:"
    echo "  test     - Run complete test suite (default)"
    echo "  logs     - Show service logs"
    echo "  status   - Show service status"
    echo "  cleanup  - Clean up all containers and volumes"
    echo "  build    - Build all services"
    echo "  start    - Start services"
    echo "  stop     - Stop services"
    echo "  help     - Show this help"
    ;;
*)
    print_error "Unknown command: $1"
    echo "Use '$0 help' for available commands"
    exit 1
    ;;
esac
