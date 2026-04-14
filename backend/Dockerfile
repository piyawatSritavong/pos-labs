# Stage 1: Build the Go binary
FROM golang:1.24-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o main ./cmd/server/main.go

# Stage 2: Final image (เล็กและปลอดภัย)
FROM alpine:latest
WORKDIR /root/
COPY --from=builder /app/main .
COPY --from=builder /app/migrations ./migrations
COPY --from=builder /app/static ./static

EXPOSE 8080
CMD ["./main"]
