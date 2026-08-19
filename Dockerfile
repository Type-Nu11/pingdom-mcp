# Use a plain Lua runtime, because the current Lapis server is cqueues-based.
FROM alpine:3.23

LABEL maintainer="developer"

# Install the Lua 5.3 toolchain and build deps used by Lapis modules.
RUN apk add --no-cache \
    build-base \
    git \
    openssl-dev \
    pcre-dev \
    zlib-dev \
    postgresql-dev \
    lua5.3-dev \
    lua5.3 \
    luarocks

WORKDIR /app

# Copy project files
COPY . /app

# Install Lapis and required libraries into the Lua 5.3 runtime.
RUN /usr/bin/luarocks-5.3 install lapis \
    && /usr/bin/luarocks-5.3 install lua-dotenv \
    && /usr/bin/luarocks-5.3 install luasec \
    && /usr/bin/luarocks-5.3 install lua-cjson \
    && /usr/bin/luarocks-5.3 install luasocket \
    && /usr/bin/luarocks-5.3 install pgmoon || true

# cqueues 기반 Lapis 서버(OpenResty 없이 구동)에 필요한 런타임.
# musl 에는 sys/queue.h 가 없어 libbsd 헤더를 표준 경로로 복사 (cqueues 컴파일에 필요)
RUN apk add --no-cache linux-headers libbsd-dev m4 \
    && cp /usr/include/bsd/sys/queue.h /usr/include/sys/queue.h \
    && cp /usr/include/bsd/sys/tree.h /usr/include/sys/tree.h \
    && /usr/bin/luarocks-5.3 install cqueues \
    && /usr/bin/luarocks-5.3 install http

EXPOSE 8080

# Use the current Lapis CLI without the old OpenResty/Nginx flags.
CMD ["sh", "-lc", "export PATH=/usr/local/bin:/usr/bin:$PATH && cd /app && lapis server"]
