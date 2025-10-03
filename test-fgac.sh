#!/bin/bash
# FGAC Testing Helper Script
# Simplifies testing the FGAC UI implementation

set -e

COMPOSE_FILE="examples/access-control-fgac/docker-compose-test.yaml"
BUILD_FILE="examples/access-control-fgac/docker-compose-build.yaml"
PROJECT_NAME="fgac-test"

cd "$(dirname "$0")"

show_help() {
    cat << EOF
FGAC Testing Helper

Usage: ./test-fgac.sh [command]

Commands:
    build       Build the lakekeeper Docker image with FGAC changes
    start       Start all services (build if needed)
    stop        Stop all services
    restart     Stop and start all services
    logs        Show lakekeeper logs (follow mode)
    status      Show status of all services
    clean       Stop services and remove volumes (clean slate)
    url         Show the UI URL to access
    help        Show this help message

Examples:
    ./test-fgac.sh build          # Build the image
    ./test-fgac.sh start          # Start everything
    ./test-fgac.sh logs           # Watch logs
    ./test-fgac.sh restart        # Restart after code changes
    ./test-fgac.sh clean          # Clean everything and start fresh

Access Points:
    UI:       http://localhost:8181/ui
    MinIO:    http://localhost:9001 (user: minio-root-user, pass: minio-root-password)
    Keycloak: http://localhost:30080 (admin: admin, pass: admin)

Test User Credentials (for UI login):
    Username: alice
    Password: alice
EOF
}

build_image() {
    echo "🔨 Building lakekeeper image with FGAC changes..."
    docker-compose -f "$BUILD_FILE" build
    echo "✅ Build complete!"
}

start_services() {
    if ! docker images | grep -q "access-control-fgac-lakekeeper"; then
        echo "⚠️  Image not found. Building first..."
        build_image
    fi
    
    echo "🚀 Starting services..."
    docker-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d
    
    echo ""
    echo "⏳ Waiting for services to be healthy..."
    sleep 5
    
    # Wait for lakekeeper to be healthy
    local max_wait=60
    local waited=0
    while [ $waited -lt $max_wait ]; do
        if docker-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" ps lakekeeper | grep -q "healthy"; then
            echo "✅ Lakekeeper is healthy!"
            break
        fi
        echo -n "."
        sleep 2
        waited=$((waited + 2))
    done
    
    echo ""
    echo "🎉 All services started!"
    echo ""
    show_urls
}

stop_services() {
    echo "🛑 Stopping services..."
    docker-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down
    echo "✅ Services stopped"
}

restart_services() {
    echo "🔄 Restarting services..."
    stop_services
    start_services
}

show_logs() {
    echo "📋 Showing lakekeeper logs (Ctrl+C to exit)..."
    docker-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" logs -f lakekeeper
}

show_status() {
    echo "📊 Service Status:"
    echo ""
    docker-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" ps
}

clean_all() {
    echo "🧹 Cleaning everything (this will delete all data)..."
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down -v
        echo "✅ Clean complete!"
    else
        echo "❌ Cancelled"
    fi
}

show_urls() {
    cat << EOF
🌐 Access Points:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  📱 Lakekeeper UI:    http://localhost:8181/ui
  📦 MinIO Console:     http://localhost:9001
  🔐 Keycloak Admin:    http://localhost:30080

Test Credentials:
  UI Login:         alice / alice
  MinIO:            minio-root-user / minio-root-password
  Keycloak Admin:   admin / admin

To test FGAC:
  1. Login at http://localhost:8181/ui
  2. Navigate to a table (you may need to create a warehouse first)
  3. Click the "FGAC" tab
  4. Create column permissions and row policies

View logs: ./test-fgac.sh logs
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
}

# Main command dispatcher
case "${1:-help}" in
    build)
        build_image
        ;;
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    restart)
        restart_services
        ;;
    logs)
        show_logs
        ;;
    status)
        show_status
        ;;
    clean)
        clean_all
        ;;
    url)
        show_urls
        ;;
    help|*)
        show_help
        ;;
esac
