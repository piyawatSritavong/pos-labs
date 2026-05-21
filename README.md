# POS Labs

A modern Point of Sale (POS) system built with Flutter and Go.

## Tech Stack

- **Frontend**: Flutter (Windows/Linux desktop, future iOS/Android support)
- **Backend**: Go
- **Database**: PostgreSQL

## Project Structure

```
pos-labs/
├── frontend/          # Flutter application
├── backend/           # Go API server
└── web-app-old/       # Legacy code (ignored)
```

## Getting Started

### Prerequisites

- Flutter SDK (for desktop development)
- Go 1.21+ (or use Docker)
- PostgreSQL 18+ (or use Docker)
- Docker and Docker Compose (for containerized development)

### Development with Docker

1. Clone the repository
2. Copy `env.example` to `.env` and adjust values if needed:
   ```bash
   cp env.example .env
   ```
   
   **How it works:** Docker Compose automatically reads the `.env` file from the same directory as `docker-compose.yml`. The syntax `${VAR:-default}` in `docker-compose.yml` means:
   - Use the value from `.env` if it exists
   - Otherwise, use the default value (e.g., `posuser`, `pospass`)
   
   You can customize values in `.env` or use the defaults. The `.env` file is gitignored for security.

3. Start services with Docker Compose:
   ```bash
   docker-compose up -d
   ```
4. Backend will be available at `http://localhost:8080`
5. PostgreSQL will be available at `localhost:5432`

**Docker Commands:**
- Start services: `docker-compose up -d`
- View logs: `docker-compose logs -f backend` or `docker-compose logs -f postgres`
- Stop services: `docker-compose down`
- Stop and remove volumes: `docker-compose down -v`
- Rebuild backend: `docker-compose build backend`

**Note:** The backend uses Air for hot reload in development. Code changes will automatically rebuild and restart the server.

### Development without Docker

1. Clone the repository
2. Set up PostgreSQL database
3. Configure environment variables (copy from `env.example`)
4. Run backend server
5. Run Flutter application

### Cloud Deployment

For Vercel + Render + Supabase deployment, see `docs/CLOUD_DEPLOYMENT.md`.

## License

[Add your license here]
