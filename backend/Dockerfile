FROM golang:1.21-alpine

# Install air for hot reload
RUN go install github.com/cosmtrek/air@latest

WORKDIR /app

# Copy go mod files (if they exist)
COPY go.mod go.sum* ./
RUN if [ -f go.mod ]; then go mod download; fi

# Copy source code
COPY . .

# Default command runs air for hot reload
CMD ["air", "-c", ".air.toml"]

