FROM openresty/openresty:alpine-fat

LABEL maintainer="developer"

# Lapis의 OpenResty 어댑터로 HTTP 응답을 완료한다. cqueues 실행 경로는
# 요청을 처리한 뒤에도 응답 바이트를 전송하지 않아 MCP 호출을 무한 대기시켰다.
RUN apk add --no-cache \
    build-base \
    git \
    openssl-dev \
    pcre-dev \
    postgresql-dev \
    zlib-dev \
    luarocks

RUN luarocks install lapis \
    && luarocks install lua-dotenv \
    && luarocks install luasec \
    && luarocks install lua-cjson \
    && luarocks install luasocket \
    && luarocks install pgmoon

WORKDIR /app

COPY . /app

EXPOSE 8080

CMD ["openresty", "-p", "/app", "-c", "/app/nginx.conf"]
