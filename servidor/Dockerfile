FROM alpine:latest

# Instala ferramentas básicas e dependências de compilação
RUN apk add --no-cache \
    lua5.3 \
    lua5.3-dev \
    gcc \
    musl-dev \
    make \
    wget \
    unzip \
    curl \
    git

# Instala LuaRocks com -L no curl para seguir redirecionamentos
RUN curl -L -O https://luarocks.org/releases/luarocks-3.9.2.tar.gz && \
    tar zxpf luarocks-3.9.2.tar.gz && \
    cd luarocks-3.9.2 && \
    # lua --version &&\
    ./configure && \
    make && make install && \
    cd .. && rm -rf luarocks-3.9.2 luarocks-3.9.2.tar.gz

RUN apk add --no-cache pcre2-dev

# Instala bibliotecas necessárias via LuaRocks
RUN luarocks install pcre2 &&\
    # luarocks install lua-http && \
    luarocks install luasocket && \
    luarocks install dkjson && \
    luarocks install mime

# Define diretório de trabalho
WORKDIR /app

# Copia o código do servidor
COPY server.lua .
CMD sh -c 'lua5.3 server.lua "$SERVER_ID"'

# CMD ["sh", "-c", "lua5.3 server.lua $SERVER_ID"]
# CMD ["lua", "server.lua"]

    # CMD ["lua", "server.lua"]