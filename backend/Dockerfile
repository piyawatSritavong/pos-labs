# Stage 1: Build the Go binary
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o main .

# Stage 2: Final image (เล็กและปลอดภัย)
FROM alpine:latest
WORKDIR /root/
COPY --from=builder /app/main .
# ถ้ามีไฟล์ .env หรือโฟลเดอร์ assets ให้ copy มาด้วย
# COPY --from=builder /app/.env . 

EXPOSE 8080
CMD ["./main"]