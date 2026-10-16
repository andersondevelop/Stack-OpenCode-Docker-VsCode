# OpenCode Docker Sandbox

> Container Docker multiplataforma com **OpenCode v2** + plugins (`oc-tps`, `opencode-mem`) para desenvolvimento com **LLM local** (llama.cpp), com **memória de conversa** e **Web UI de memória**.

---

## Índice

1. [Visão Geral](#visão-geral)
2. [Arquitetura](#arquitetura)
3. [Construção Multi-Arquitetura (Multi-Arch)](#construção-multi-arquitetura-multi-arch)
4. [Estrutura do Projeto](#estrutura-do-projeto)
5. [Pasta `teste/` — Uso em Computadores de Desenvolvedores](#pastateste--uso-em-computadores-de-desenvolvedores)
6. [Uso Rápido](#uso-rápido)
7. [Variáveis de Ambiente](#variáveis-de-ambiente)
8. [Plugins](#plugins)
9. [opencode-mem (Memória)](#opencode-mem-memória)
10. [Múltiplos Projetos](#múltiplos-projetos)
11. [Comandos Úteis](#comandos-úteis)
12. [Estrutura de Arquivos do Container](#estrutura-de-arquivos-do-container)

---

## Visão Geral

| Recurso | Descrição |
|---------|-----------|
| **Ferramenta Principal** | OpenCode v2 (CLI + servidor) |
| **Versão do OpenCode** | 2.0.25 |
| **Base da Imagem** | Debian Bookworm Slim |
| **Runtime Node.js** | Node 20 (Bookworm Slim) |
| **Modelo LLM** | Qualquer servidor compatível com OpenAI API (ex: llama.cpp) |
| **Plugins Incluídos** | `oc-tps` (TUI/CLI), `opencode-mem` (memória + Web UI) |
| **Web UI de Memória** | Porta 4747 |
| **Sistema de Memória** | Vetorial local com embeddings (Xenova/nomic-embed-text-v1) |
| **Tamanho da Imagem** | ~517 MB |

### O que este projeto faz

- Empacota o **OpenCode v2** em um container Docker isolado
- Conecta a um **servidor LLM local** (llama.cpp ou qualquer compatível com OpenAI API)
- Gerencia **contexto longo** com compaction automática
- Armazena **memória de conversa** com busca vetorial local
- Expõe uma **Web UI** para gerenciar a memória
- Suporta **múltiplos projetos** com a mesma imagem (isolamento completo)

---

## Arquitetura

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        Host (macOS / Linux / Windows)                        │
│                                                                              │
│  ┌───────────────────────┐                ┌────────────────────────┐         │
│  │  Desenvolvedor        │                │  Servidor LLM Local     │         │
│  │                       │                │                        │         │
│  │  VS Code / Terminal   │                │  llama.cpp / Ollama    │         │
│  │  (opencode CLI)       │                │  (qualquer OpenAI API) │         │
│  └───────────┬───────────┘                └───────────┬────────────┘         │
│              │                                       │                      │
│              │  Docker Container                     │  Requisições         │
│              │         ┌────────────────────────────────────────┐          │
│              │         │       OpenCode Sandbox                 │          │
│              │         │                                        │          │
│              │         │  ┌──────────────┐  ┌────────────────┐ │          │
│              │         │  │  OpenCode    │  │  opencode-mem  │ │          │
│              │         │  │  CLI/Server  │→ │  (memória +    │ │          │
│              │         │  │              │  │   Web UI)      │ │          │
│              │         │  └──────────────┘  └────────────────┘ │          │
│              │         │                                        │          │
│              │         │  ┌────────────────────────────────┐   │          │
│              │         │  │  Volumes                       │   │          │
│              │         │  │  /workspace        (bind mount)│   │          │
│              │         │  │  /home/opencode  (named vol.)  │   │          │
│              │         │  └────────────────────────────────┘   │          │
│              │         └────────────────────────────────────────┘          │
│              └─────────────────────────────────────────────────────────────┘
│                                                                              │
│  Web UI de Memória: http://localhost:4747                                   │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Componentes

| Componente | Função | Localização |
|------------|--------|-------------|
| `Dockerfile` | Define a imagem multi-estágio | Raiz do projeto |
| `entrypoint.sh` | Configuração automática no início | Raiz do projeto |
| `docker-compose.yaml` | Orquestração do container | Raiz do projeto |
| `build.sh` | Script de build multi-arquitetura | Raiz do projeto |
| `.env` | Variáveis de ambiente (configuração) | Raiz do projeto |
| `.env.example` | Template de variáveis de ambiente | Raiz do projeto |
| `.devcontainer/` | Integração com VS Code Dev Containers | `.devcontainer/` |
| `teste/` | Ambiente pronto para desenvolvedores | `teste/` |

---

## Construção Multi-Arquitetura (Multi-Arch)

A imagem é construída usando **Docker BuildKit** com suporte a múltiplas arquiteturas, permitindo que a mesma imagem funcione em diferentes tipos de hardware.

### Arquiteturas Suportadas

| Arquitetura | Plataforma | Uso |
|-------------|------------|-----|
| **AMD64** | `linux/amd64` | Servidores Linux, PCs x64 |
| **ARM64** | `linux/arm64` | Mac M-series, Raspberry Pi, ARM servers |

### Como Construir

```bash
# Build local rápido (somente AMD64)
./build.sh

# Build multi-arquitetura (linux/amd64 + linux/arm64)
PLATFORM=linux/amd64,linux/arm64 ./build.sh

# Build e push para registro
PLATFORM=linux/amd64,linux/arm64 ./build.sh
```

### Detalhes Técnicos do Build

| Parâmetro | Descrição | Padrão |
|-----------|-----------|--------|
| `PLATFORM` | Arquiteturas alvo | `linux/amd64,linux/arm64` |
| `IMAGE` | Nome da imagem construída | `<usuario>/<projeto>:latest` |
| `OPENCODE_VERSION` | Versão do OpenCode CLI | `2.0.25` |

### Por que Multi-Arch?

- **Portabilidade**: A mesma imagem funciona em Mac (M1/M2/M3/M4), PCs Linux x64, servidores ARM
- **Consistência**: Mesma imagem para todos os ambientes
- **Buildx**: Usa `docker buildx` com emulação QEMU para cross-compilation

> **Nota**: O build multi-arquitetura requer `docker buildx` e pode demorar mais. Para desenvolvimento local, use `PLATFORM=linux/amd64` para build mais rápido.

### Publicação no Docker Hub

Para publicar a imagem multi-arquitetura no Docker Hub:

```bash
# Login no Docker Hub
docker login

# Build multi-arquitetura e push automático
PLATFORM=linux/amd64,linux/arm64 ./build.sh
```

O build multi-arquitetura gera um **manifest list** que contém imagens para todas as arquiteturas especificadas. Quando um usuário faz `docker pull`, o Docker automaticamente seleciona a imagem correta para a arquitetura do host.

---

## Estrutura do Projeto

```
.
├── Dockerfile                    # Imagem multi-estágio (builder + production)
├── entrypoint.sh                 # Configuração automática do container
├── docker-compose.yaml           # Orquestração principal
├── build.sh                      # Script de build multi-arquitetura
├── .env                          # Variáveis de ambiente (configuração atual)
├── .env.example                  # Template de variáveis de ambiente
├── .dockerignore                 # Arquivos ignorados no build do Docker
├── .devcontainer/
│   └── devcontainer.json         # Integração com VS Code Dev Containers
├── teste/                        # Ambiente pronto para desenvolvedores
│   ├── docker-compose.yaml       # Compose para uso direto
│   ├── .env                      # Configuração de uso
│   └── .env.example              # Template de configuração
├── PLANO_MIGRACAO_BI.md          # Documentação de projeto secundário
└── STATUS_*.md                   # Logs de status e notas de desenvolvimento
```

---

## Pasta `teste/` — Uso em Computadores de Desenvolvedores

A pasta `teste/` foi criada especificamente para ser **copiada e usada diretamente nos computadores dos desenvolvedores**. Ela contém todos os arquivos necessários para rodar o OpenCode Sandbox em qualquer projeto local.

### Por que usar a pasta `teste/`?

| Vantagem | Descrição |
|----------|-----------|
| **Pronta para uso** | Contém `docker-compose.yaml` e `.env.example` configurados |
| **Copiar e colar** | Basta copiar a pasta para qualquer projeto e começar a usar |
| **Isolamento** | Cada desenvolvedor tem seu próprio container e volume |
| **Sem conflito** | Sem `container_name` fixo, múltiplos containers coexistem |
| **Porta configurável** | Cada projeto pode usar porta diferente na Web UI |

### Como usar em seu computador

```bash
# 1. Copie a pasta teste/ para o seu projeto
cp -r /caminho/do/projeto/teste /seu/projeto

# 2. Ou copie os arquivos diretamente
cp /caminho/do/projeto/teste/docker-compose.yaml /seu/projeto/
cp /caminho/do/projeto/teste/.env.example /seu/projeto/.env

# 3. Configure seu servidor LLM no .env
nano .env
# Edite LLAMA_BASE_URL com o endereço do seu servidor LLM

# 4. Suba o container
docker compose up -d

# 5. Acesse a Web UI de memória
open http://localhost:4747
```

### Estrutura da pasta `teste/`

| Arquivo | Função |
|---------|--------|
| `docker-compose.yaml` | Configuração do container para uso direto |
| `.env.example` | Template de variáveis de ambiente |
| `.env` | Configuração atual (não versionado) |

### Diferenças entre a raiz e `teste/`

| Aspecto | Raiz do Projeto | Pasta `teste/` |
|---------|-----------------|----------------|
| **Propósito** | Desenvolvimento da imagem | Uso em projetos de desenvolvedores |
| **Build** | Tem `Dockerfile` + `build:` | Só consome a imagem (sem `build:`) |
| **Imagem** | Constrói a imagem | Usa imagem já construída |
| **Porta Web UI** | Fixa (4747) | Configurável via variável |
| **Uso** | Quem desenvolve a imagem | Desenvolvedores que usam a imagem |

### Exemplo de uso em projeto real

```bash
# No computador de um desenvolvedor
cd ~/Projetos/MeuProjeto
cp /caminho/para/StackOpenCodeDockerVsCode/teste/docker-compose.yaml .
cp /caminho/para/StackOpenCodeDockerVsCode/teste/.env.example .env

# Edite o .env com a URL do seu servidor LLM
sed -i '' 's|http://SEU-SERVIDOR-LLM:9090/v1|http://192.168.1.100:9090/v1|' .env

# Suba o container
docker compose up -d

# O container montará a pasta atual (/) em /workspace dentro do container
docker exec -it MeuProjeto-opencode-1 bash
```

---

## Uso Rápido

### Pré-requisitos

| Software | Versão Mínima | Plataforma |
|----------|---------------|------------|
| Docker Desktop | 4.0+ | macOS, Windows, Linux |
| Docker Compose | V2 | macOS, Windows, Linux |
| Docker Buildx | Habilitado | macOS, Windows, Linux |

### Passo a Passo

```bash
# 1. Clone ou extraia o projeto
cd /caminho/do/projeto

# 2. Configure as variáveis de ambiente
cp .env.example .env
# Edite o .env com as configurações do seu servidor LLM

# 3. Construa a imagem (build local rápido)
./build.sh

# 4. Suba o container
docker compose up -d

# 5. Acesse a Web UI de memória
open http://localhost:4747

# 6. Abra o terminal no container
docker exec -it <nome-do-container> bash
```

### Integração com VS Code

```bash
# Abra o projeto no VS Code
code .

# Ou use o Dev Container
# Abra .devcontainer/devcontainer.json no VS Code
# Clique em "Reopen in Container"
```

---

## Variáveis de Ambiente

### Configuração do LLM

| Variável | Descrição | Padrão | Exemplo |
|----------|-----------|--------|---------|
| `LLAMA_BASE_URL` | URL do servidor LLM | `http://localhost:9090/v1` | `http://10.0.1.158:9090/v1` |
| `MODEL_PROVIDER` | Provedor do modelo | `local` | `local` |
| `MODEL_ID` | ID do modelo (provider/id) | `qwen` | `qwen` |
| `MODEL_NAME` | Nome exibido | `qwen` | `Qwen3.6-35B` |

### Limites de Contexto

| Variável | Descrição | Padrão | Observação |
|----------|-----------|--------|------------|
| `CONTEXT_LIMIT` | Limite de tokens de contexto | `122880` | Deve ser ≤ n_ctx do llama.cpp |
| `OUTPUT_LIMIT` | Limite de tokens de saída | `8192` | Consome o mesmo contexto |

### Compaction (Gerenciamento de Contexto)

| Variável | Descrição | Padrão | Observação |
|----------|-----------|--------|------------|
| `COMPACTION_AUTO` | Compaction automática | `true` | Ativa/desativa |
| `COMPACTION_KEEP_TOKENS` | Tokens recentes preservados | `15000` | Após compactação |
| `COMPACTION_BUFFER` | Folga antes do limite | `20000` | Dispara compactação |

### opencode-mem (Memória)

| Variável | Descrição | Padrão | Observação |
|----------|-----------|--------|------------|
| `AUTO_CAPTURE_LANGUAGE` | Idioma dos resumos | `pt` | `pt`, `en`, `es`, etc. |
| `OPENCODE_MEM_WEB_PASSWORD` | Senha da Web UI | _(vazio)_ | Gere com `openssl rand -hex 24` |
| `OPENCODE_MEM_WEB_TOKEN` | Token da API | _(vazio)_ | Protege `/api/*` |

### Permissões

| Variável | Descrição | Padrão | Observação |
|----------|-----------|--------|------------|
| `PUID` | UID do usuário no container | `1000` | Só relevante em Linux nativo |
| `PGID` | GID do grupo no container | `1000` | Só relevante em Linux nativo |
| `CHOWN_WORKSPACE` | Comportamento do chown | `auto` | `auto`, `true`, `false` |

### CHOWN_WORKSPACE

| Valor | Comportamento |
|-------|---------------|
| `auto` | Pula em Docker Desktop (virtiofs/9p), faz em Linux nativo (padrão) |
| `true` | Sempre faz o chown recursivo |
| `false` | Nunca faz o chown (pula em Linux nativo ou monorepos gigantes) |

---

## Plugins

### oc-tps (TUI/CLI Plugin)

| Recurso | Descrição |
|---------|-----------|
| **Tipo** | Plugin de TUI/CLI |
| **Registro** | `cli.json` (plugins da CLI) |
| **Entry Point** | `dist/tui.js` |
| **Stage** | `load`, `setup` |

### opencode-mem (Memória)

| Recurso | Descrição |
|---------|-----------|
| **Tipo** | Plugin de servidor |
| **Registro** | `opencode.json` (plugins do servidor) |
| **Função** | Memória de conversa com busca vetorial |
| **Web UI** | `http://localhost:4747` |
| **Embedding** | Xenova/nomic-embed-text-v1 (~90 MB, 1º uso) |

### Comparação de Plugins

| Plugin | Tipo | Carregamento | Instalação |
|--------|------|--------------|------------|
| `oc-tps` | CLI/TUI | `cli.json` | Primeiro start (cache volume) |
| `opencode-mem` | Servidor | `opencode.json` | Primeiro start (cache volume) |

> **Nota**: Os plugins **NÃO** ficam na imagem. São instalados no primeiro start no volume de cache (`~/.cache/opencode/npm/...`). Exige conexão de rede na 1ª vez.

---

## opencode-mem (Memória)

### Configuração

| Parâmetro | Valor | Descrição |
|-----------|-------|-----------|
| `autoCaptureEnabled` | `true` | Captura automática de prompts |
| `opencodeProvider` | `local` | Provedor do modelo |
| `opencodeModel` | `qwen` | Modelo usado |
| `autoCaptureLanguage` | `pt` | Idioma dos resumos |
| `webServerHost` | `0.0.0.0` | Host do servidor Web UI |
| `webServerPort` | `4747` | Porta do servidor Web UI |
| `webServerAuthUsername` | `admin` | Usuário da Web UI |
| `similarityThreshold` | `0.6` | Limiar de similaridade |
| `maxMemories` | `10` | Máximo de memórias injetadas |
| `defaultScope` | `project` | Escopo da memória |

### Retenção e Limpeza

| Parâmetro | Valor | Descrição |
|-----------|-------|-----------|
| `autoCleanupEnabled` | `true` | Limpeza automática ativada |
| `autoCleanupRetentionDays` | `30` | Dias de retenção |
| `aiSessionRetentionDays` | `7` | Retenção de sessões |
| `userProfileStaleDays` | `2` | Dias até perfil ficar obsoleto |
| `userProfileConfidenceDecayDays` | `30` | Decaimento de confiança do perfil |
| `cleanupInterval` | `100` | Limpeza a cada 100 prompts |

### Armazenamento de Dados

| Arquivo | Descrição |
|---------|-----------|
| `user-prompts.db` | Prompts capturados pelo usuário |
| `user-profiles.db` | Perfis de usuário |
| `metadata.db` | Metadados do sistema |
| `project_<hash>_shard_0.db` | Memórias do projeto (vetores) |

### Acesso à Web UI

| Recurso | URL | Autenticação |
|---------|-----|--------------|
| Web UI | `http://localhost:4747` | `admin` + `OPENCODE_MEM_WEB_PASSWORD` |
| API | `http://localhost:4747/api/*` | Header `X-Opencode-Mem-Token: <OPENCODE_MEM_WEB_TOKEN>` |

---

## Múltiplos Projetos

### Visão Geral

A mesma imagem pode ser usada por **múltiplos projetos**, cada um com seu próprio container e volume HOME isolado.

### Estratégia Recomendada

| Aspecto | Recomendação |
|---------|--------------|
| **Container** | Um container por projeto |
| **Nome do container** | Sem `container_name` fixo (Compose nomeia por projeto) |
| **Volume HOME** | Isolado por projeto (`<projeto>_opencode_home`) |
| **Porta Web UI** | Configurável por projeto (`OPENCODE_MEM_WEB_PORT`) |
| **Memória** | Isolada automaticamente por projeto (shard baseado em hash) |

### Fluxo de Trabalho

```bash
# Projeto 1: /caminho/projeto-a/
cp docker-compose.yaml .
cp .env.example .env
# Edite o .env
docker compose up -d

# Projeto 2: /caminho/projeto-b/
cp docker-compose.yaml .
cp .env.example .env
# Edite o .env (porta diferente se necessário)
docker compose up -d
```

### Identidade do Projeto (Memória)

O shard de memória é calculado como `sha256(identidade)[:16]`, onde a identidade é:

1. Marcador `.opencode-mem-project` na árvore → `path:<root>`
2. Git → `git-common:<caminho do .git>`
3. Remote → `remote:<url>`
4. Padrão → `path:<dir absoluto>`

> **Importante**: Cada projeto deve ter seu próprio container/volume para evitar mistura de memórias.

---

## Comandos Úteis

### Build e Deploy

| Comando | Descrição |
|---------|-----------|
| `./build.sh` | Build local (AMD64) |
| `PLATFORM=linux/amd64,linux/arm64 ./build.sh` | Build multi-arquitetura + push |
| `docker compose build` | Build da imagem |
| `docker compose up -d` | Subir container em segundo plano |
| `docker compose down` | Parar container (preserva volume) |
| `docker compose down -v` | Parar e remover volume (perde dados) |

### Monitoramento

| Comando | Descrição |
|---------|-----------|
| `docker ps` | Listar containers rodando |
| `docker logs -f <container>` | Logs do container |
| `docker exec -it <container> bash` | Shell no container |
| `docker inspect <container>` | Detalhes do container |
| `docker volume ls` | Listar volumes |

### Web UI e API

| Comando | Descrição |
|---------|-----------|
| `open http://localhost:4747` | Abrir Web UI (macOS) |
| `curl -u admin:senha http://localhost:4747/` | Testar Web UI |
| `curl -H "X-Opencode-Mem-Token: <token>" http://localhost:4747/api/*` | Testar API |

### Debug

| Comando | Descrição |
|---------|-----------|
| `opencode run --standalone --print-logs --log-level debug` | Logs detalhados |
| `opencode plugin list` | Listar plugins instalados |
| `sqlite3 ~/.opencode-mem/data/projects/project_<hash>_shard_0.db "SELECT COUNT(*) FROM memories;"` | Contar memórias |

---

## Estrutura de Arquivos do Container

### Sistema de Arquivos

| Caminho | Tipo | Descrição |
|---------|------|-----------|
| `/workspace` | Bind mount | Pasta do projeto (mapeada do host) |
| `/home/opencode` | Named volume | HOME do container (config, cache, memória) |
| `/usr/local/bin/opencode` | Symlink | Binário do OpenCode CLI |
| `/usr/local/bin/node` | Copiado | Runtime Node.js |
| `/usr/local/bin/npm` | Symlink | Gerenciador de pacotes npm |

### Ferramentas Instaladas

| Ferramenta | Versão | Uso |
|------------|--------|-----|
| `opencode` | 2.0.25 | CLI do OpenCode |
| `node` | 20.x | Runtime Node.js |
| `npm` | Último | Gerenciador de pacotes |
| `git` | Último | Controle de versão |
| `ripgrep (rg)` | Último | Busca de texto rápida |
| `fd-find (fd)` | Último | Busca de arquivos |
| `python3` | Último | Scripts de configuração |
| `sqlite3` | Último | Banco de dados da memória |
| `curl` | Último | HTTP client |
| `wget` | Último | Download de arquivos |
| `unzip` | Último | Extração de arquivos |
| `gosu` | Último | Execução como usuário não-root |

### Configurações

| Arquivo | Localização | Descrição |
|---------|-------------|-----------|
| `opencode.json` | `/home/opencode/.config/opencode/` | Configuração principal do OpenCode |
| `cli.json` | `/home/opencode/.config/opencode/` | Configuração de plugins da CLI |
| `opencode-mem.jsonc` | `/home/opencode/.config/opencode/` | Configuração do plugin de memória |

---

## Licença

Este projeto é fornecido "como está" para fins de desenvolvimento e teste.
