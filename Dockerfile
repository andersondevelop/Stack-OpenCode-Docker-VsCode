# ==========================================
# Estágio 1: Builder (Instalação global da CLI e Plugins)
# ==========================================
FROM node:20-bookworm-slim AS builder

# OpenCode v2 vive no npm como @opencode/cli (o pacote antigo `opencode-ai` é a linha 1.x)
ARG OPENCODE_VERSION=2.0.25

# Os plugins (oc-tps, opencode-mem) NAO sao gravados na imagem: a config referencia
# por nome bare e o opencode os instala no volume de cache (~/.cache/opencode/npm)
# no primeiro start (precisa de rede nessa primeira vez).
RUN npm install -g \
      @opencode/cli@${OPENCODE_VERSION} && \
    npm cache clean --force && \
    opencode --version

# ==========================================
# Estágio 2: Imagem Final de Produção
# ==========================================
FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="OpenCode Sandbox" \
      org.opencontainers.image.description="OpenCode AI com plugins nativos adaptados para LLM local" \
      org.opencontainers.image.source="https://github.com"

# Garante privilégios root para a configuração inicial do sistema
USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    sqlite3 \
    ca-certificates \
    bash \
    ripgrep \
    fd-find \
    unzip \
    wget \
    python3 \
    gosu \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/* \
    && rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/locale/*

# 2) Cria o link simbólico absoluto para o 'fd' (Debian usa 'fdfind' para evitar conflitos)
RUN ln -s /usr/bin/fdfind /usr/local/bin/fd

# 3) Copia o ambiente Node.js e os pacotes globais do builder para o sistema de produção
COPY --from=builder /usr/local/bin/node /usr/local/bin/node
COPY --from=builder /usr/local/lib/node_modules /usr/local/lib/node_modules

# 4) Liga os binários globais: OpenCode v2 (nativo) e npm
#    O binário do @opencode/cli é o arquivo opencode.exe dentro do próprio pacote
RUN ln -sf ../lib/node_modules/@opencode/cli/bin/opencode.exe /usr/local/bin/opencode && \
    ln -sf ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    chmod 755 /usr/local/lib/node_modules/@opencode/cli/bin/opencode.exe

# 5) Define o diretório de trabalho restrito da Jail
WORKDIR /workspace

# HOME fica FORA do workspace (no volume opencode_home, montado no compose),
# para que .cache/.config/.local/etc. nao poluam a pasta do projeto.
ENV HOME=/home/opencode

# 6) Configuração do Entrypoint com barreira de segurança contra quebras de linha do Windows (CRLF)
COPY entrypoint.sh /entrypoint.sh
RUN if grep -qU $'\r' /entrypoint.sh; then \
      echo "ERRO: entrypoint.sh contem CRLF - rode: dos2unix entrypoint.sh"; \
      exit 1; \
    fi && chmod 755 /entrypoint.sh

# 7) Monitoramento de Saúde do Container (Validando que o OpenCode está operando)
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD command -v opencode >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]

