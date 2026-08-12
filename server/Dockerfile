# 多阶段构建：编译Go代码
FROM golang:1.25-alpine AS builder

RUN apk add --no-cache git

ENV GOPROXY=https://goproxy.cn,direct

WORKDIR /build

# 复制go.mod和go.sum
COPY server/go.mod server/go.sum ./

# 下载依赖
RUN go mod download

# 复制源代码
COPY server/ ./

# 编译
RUN CGO_ENABLED=0 GOOS=linux go build -o jisign-server ./cmd/server/

# 最终镜像
FROM alpine:3.21

RUN apk --no-cache add ca-certificates tzdata
ENV TZ=Asia/Shanghai

WORKDIR /app

# 从编译阶段复制二进制文件
COPY --from=builder /build/jisign-server ./jisign-server
RUN chmod +x ./jisign-server

# 复制网站和证书
COPY website ./website
COPY server/certs ./certs

EXPOSE 8080

CMD ["./jisign-server"]
