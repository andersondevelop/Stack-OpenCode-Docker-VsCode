#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
export TERM=${TERM:-xterm-256color}

echo "============================================================"
echo "  Inicializando container OpenCode (Sandbox Jail)"
echo "============================================================"
echo ""

# 1) Gerenciamento Dinâmico de Usuário (Ajuste de Permissões PUID/PGID)
# Se PUID for passado e for diferente de 0 (root), reconfiguramos o ambiente para o usuário correto.
TARGET_USER="root"
TARGET_HOME="/home/opencode"

if [ -n "$PUID" ] && [ "$PUID" -ne 0 ]; then
  PGID=${PGID:-1000}
  echo "[1/4] CONFIGURANDO PERMISSÕES DO USUÁRIO DE HOSPEDAGEM"
  echo "      > Mapeando usuário interno para UID:$PUID e GID:$PGID..."
  
  # Cria o grupo se não existir
  if ! getent group opencode >/dev/null; then
    groupadd -g "$PGID" opencode 2>/dev/null || true
  fi
  # Cria o usuário dev se não existir
  if ! id -u opencode >/dev/null 2>&1; then
    useradd -u "$PUID" -g "$PGID" -d "$TARGET_HOME" -s /bin/bash opencode 2>/dev/null || true
  fi
  
  TARGET_USER="opencode"
  # Ajusta a propriedade do /workspace para permitir escrita pelo usuario final.
  # Em Linux nativo (bind mount real) isso e util; em Docker Desktop (macOS/Windows)
  # o mount e virtiofs/9p/grpc-fuse com ownership JA virtualizado, entao o chown
  # recursivo e no-op e so custa tempo (cresce com node_modules e afins).
  # Detecta pelo tipo do mount; CHOWN_WORKSPACE=true|false forca o comportamento.
  WS_FSTYPE=$(awk '$2=="/workspace"{print $3; exit}' /proc/mounts 2>/dev/null)
  DO_CHOWN="${CHOWN_WORKSPACE:-auto}"
  if [ "$DO_CHOWN" = "auto" ]; then
    if echo "$WS_FSTYPE" | grep -qiE 'virtiofs|grpcfuse|fuse|9p|smb|vboxsf'; then
      DO_CHOWN="false"
    else
      DO_CHOWN="true"
    fi
  fi
  if [ "$DO_CHOWN" = "true" ]; then
    chown -R $PUID:$PGID /workspace 2>/dev/null || true
  else
    echo "      > mount '$WS_FSTYPE' (Docker Desktop): pulando chown recursivo do /workspace"
  fi
else
  echo "[1/4] Configuração de usuário: Mantido como ROOT (Ambiente Virtualizado/macOS/Windows)"
fi

# HOME do container fica FORA do projeto (/home/opencode, montada em volume),
# para que .cache/.config/.local/etc. nao poluam a pasta do projeto.
# Plugins (oc-tps, opencode-mem) NAO ficam na imagem: a config usa nomes bare
# e o proprio opencode instala no cache (~/.cache/opencode/npm) no primeiro start.
export HOME="$TARGET_HOME"
mkdir -p "$HOME"
mkdir -p "$HOME/.config/opencode/plugins"
mkdir -p "$HOME/.cache/opencode"

if [ "$TARGET_USER" != "root" ]; then
  chown -R $PUID:$PGID "$HOME" 2>/dev/null || true
fi

# 2) Geração automática do arquivo opencode.json
# Formato OpenCode v2: "model" (provider/id), provider custom com
# "package": "@opencode/ai/providers/openai-compatible" e limites em models.<id>.limit.
CONFIG_FILE="$HOME/.config/opencode/opencode.json"
CLI_CONFIG_FILE="$HOME/.config/opencode/cli.json"
NEED_CONFIG=0
if [ ! -f "$CONFIG_FILE" ]; then
  NEED_CONFIG=1
elif grep -q '"contextLimit"' "$CONFIG_FILE"; then
  echo "      > Formato antigo (v1) detectado em opencode.json; migrando para v2..."
  NEED_CONFIG=1
elif grep -qE '"model"[[:space:]]*:[[:space:]]*"[^"]*:' "$CONFIG_FILE"; then
  echo "      > Separador de modelo invalido (provider:id) detectado; migrando para provider/id..."
  NEED_CONFIG=1
else
  # Regenera se o .env mudou (modelo ou limites) depois da ultima subida
  CUR_CONTEXT=$(grep -oE '"context"[[:space:]]*:[[:space:]]*[0-9]+' "$CONFIG_FILE" | grep -oE '[0-9]+' | head -1)
  CUR_OUTPUT=$(grep -oE '"output"[[:space:]]*:[[:space:]]*[0-9]+' "$CONFIG_FILE" | grep -oE '[0-9]+' | head -1)
  CUR_MODEL=$(grep -oE '"model"[[:space:]]*:[[:space:]]*"[^"]+"' "$CONFIG_FILE" | sed -E 's/.*"model"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)
  CUR_KEEP=$(grep -oE '"tokens"[[:space:]]*:[[:space:]]*[0-9]+' "$CONFIG_FILE" | grep -oE '[0-9]+' | head -1)
  CUR_BUFFER=$(grep -oE '"buffer"[[:space:]]*:[[:space:]]*[0-9]+' "$CONFIG_FILE" | grep -oE '[0-9]+' | head -1)
  WANT_MODEL="${MODEL_PROVIDER:-local}/${MODEL_ID:-qwen}"
  if [ "$CUR_CONTEXT" != "${CONTEXT_LIMIT:-49152}" ] || \
     [ "$CUR_OUTPUT" != "${OUTPUT_LIMIT:-8192}" ] || \
     [ "$CUR_MODEL" != "$WANT_MODEL" ] || \
     [ "$CUR_KEEP" != "${COMPACTION_KEEP_TOKENS:-15000}" ] || \
     [ "$CUR_BUFFER" != "${COMPACTION_BUFFER:-20000}" ]; then
    echo "      > .env mudou (modelo/limites/compaction) em relacao ao opencode.json; regenerando..."
    NEED_CONFIG=1
  fi
fi

if [ "$NEED_CONFIG" = "1" ]; then
  echo "      > Injetando parâmetros do .env no opencode.json..."

  # Usamos chaves de escape \$ e variáveis padrão em Bash para garantir valores de fallback
  cat <<EOF > "$CONFIG_FILE"
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "${MODEL_PROVIDER:-local}/${MODEL_ID:-qwen}",
  "providers": {
    "${MODEL_PROVIDER:-local}": {
      "name": "LLM local (llama.cpp)",
      "package": "@opencode/ai/providers/openai-compatible",
      "settings": {
        "baseURL": "${LLAMA_BASE_URL:-http://localhost:9090/v1}",
        "apiKey": "${LLM_API_KEY:-local-sandbox-token}"
      },
      "models": {
        "${MODEL_ID:-qwen}": {
          "name": "${MODEL_NAME:-qwen}",
          "limit": {
            "context": ${CONTEXT_LIMIT:-49152},
            "output": ${OUTPUT_LIMIT:-8192}
          }
        }
      }
    }
  },
  "update": "disable",
  "compaction": {
    "auto": ${COMPACTION_AUTO:-true},
    "keep": {
      "tokens": ${COMPACTION_KEEP_TOKENS:-15000}
    },
    "buffer": ${COMPACTION_BUFFER:-20000}
  },
  "plugins": [
    "opencode-mem"
  ]
}
EOF
fi

# 2b) cli.json: plugins de TUI/CLI.
# O oc-tps só exporta "./tui" (sem "."), então como "plugins" do opencode.json o
# servidor falharia com "Plugin entrypoint not found: oc-tps". Ele é registrado
# na CLI, que carrega o entrypoint dist/tui.js (stage=load + stage=setup).
python3 - <<'PY' || true
import json, os
p = os.path.join(os.environ["HOME"], ".config/opencode/cli.json")
try:
    cfg = json.load(open(p)) if os.path.exists(p) else {}
except Exception:
    cfg = {}
plugins = cfg.get("plugins") or []
if "oc-tps" not in plugins:
    plugins.append("oc-tps")
cfg["plugins"] = plugins
cfg["$schema"] = "https://opencode.ai/v2/cli.json"
os.makedirs(os.path.dirname(p), exist_ok=True)
with open(p, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PY

# 2c) opencode-mem.jsonc: garante auto-capture local + Web UI exposta.
# Respeita config manual ativa: so altera quando a chave esta ausente/comentada
# (ou, no caso de webServerHost, quando ainda esta no stock "127.0.0.1").
echo "      > opencode-mem.jsonc: habilitando auto-capture local (${MODEL_PROVIDER:-local}/${MODEL_ID:-qwen}, lingua ${AUTO_CAPTURE_LANGUAGE:-pt}) + Web UI 0.0.0.0:4747..."
python3 - <<'PY' || true
import os, re, json

def ensure(s, key, value, replace_default=None):
    m = re.search(r'^\s*"' + re.escape(key) + r'"\s*:\s*("[^"]*"|true|false|[-0-9.]+)\s*,', s, re.M)
    if m:
        # respeita config manual, exceto quando ainda e o valor padrao do arquivo
        if replace_default is not None and m.group(1).strip('"') == replace_default:
            return re.sub(r'^([ \t]*)("' + re.escape(key) + r'"[ \t]*:)[ \t]*[^\r\n]+,\r?$',
                          '\\1\\2 ' + json.dumps(value) + ',', s, count=1, flags=re.M)
        return s
    # comentada no padrao
    commented = re.compile(r'^([ \t]*)//[ \t]*"' + re.escape(key) + r'"[ \t]*:[ \t]*[^,]*,?[ \t]*$', re.M)
    if commented.search(s):
        return commented.sub('\\1"' + key + '": ' + json.dumps(value) + ',', s, count=1)
    # insere apos a primeira chave existente
    s2, n = re.subn(r'^([ \t]*)("[^"\n]+"[ \t]*:[ \t]*[^\n]+),?[ \t]*$',
                    lambda m: m.group(0) + '\n' + m.group(1) + '"' + key + '": ' + json.dumps(value) + ',',
                    s, count=1, flags=re.M)
    return s2 if n else s

provider = os.environ.get("MODEL_PROVIDER", "local")
model = os.environ.get("MODEL_ID", "qwen")
lang = os.environ.get("AUTO_CAPTURE_LANGUAGE", "pt")
p = os.path.join(os.environ["HOME"], ".config/opencode/opencode-mem.jsonc")
os.makedirs(os.path.dirname(p), exist_ok=True)
if os.path.exists(p):
    s = open(p).read()
else:
    s = '{\n  "autoCaptureEnabled": true,\n}'
for k, v, rep in (("opencodeProvider", provider, None),
                  ("opencodeModel", model, None),
                  ("autoCaptureLanguage", lang, None),
                  ("webServerHost", "0.0.0.0", "127.0.0.1"),
                  ("webServerAuthUsername", "admin", None),
                  ("webServerAuthPassword", "env://OPENCODE_MEM_WEB_PASSWORD", None),
                  ("webServerApiToken", "env://OPENCODE_MEM_WEB_TOKEN", None)):
    s = ensure(s, k, v, rep)
with open(p, "w") as f:
    f.write(s)
PY

# Garante permissões da HOME se alterou o UID
if [ "$TARGET_USER" != "root" ]; then
  chown -R $PUID:$PGID "$HOME" 2>/dev/null || true
fi

# 3) Verificando ferramentas essenciais (build + runtime)
echo ""
echo "[2/4] VERIFICANDO FERRAMENTAS INSTALADAS"

check_tool() {
  local name="$1"
  local cmd="$2"
  if command -v "${cmd:-$name}" >/dev/null 2>&1; then
    local ver=$(${cmd:-$name} --version 2>/dev/null | head -n 1)
    printf "      ✓ %-12s %s\n" "$name:" "${ver:-OK}"
    return 0
  else
    printf "      ✗ %-12s FALTANDO\n" "$name:"
    return 1
  fi
}

MISSING=0
check_tool "opencode" "opencode" || MISSING=$((MISSING+1))
check_tool "ripgrep" "rg" || MISSING=$((MISSING+1))
check_tool "fd" "fd" || MISSING=$((MISSING+1))
check_tool "unzip" "unzip" || MISSING=$((MISSING+1))
check_tool "wget" "wget" || MISSING=$((MISSING+1))
check_tool "python3" "python3" || MISSING=$((MISSING+1))
check_tool "git" "git" || MISSING=$((MISSING+1))

# 4) Validando Plugins Carregados
echo ""
echo "[3/4] VERIFICANDO STATUS DOS PLUGINS"
if command -v opencode >/dev/null 2>&1; then
  echo "      > Listando plugins ativos na CLI:"
  # Guarda contra OpenCode 1.x: sem o subcomando 'list', o comando abaixo
  # instalaria por engano um pacote npm chamado "list".
  if opencode plugin --help 2>&1 | grep -qE '^[[:space:]]+list[[:space:]]'; then
    LIST_OUT=$(HOME="$HOME" timeout 45 opencode plugin list 2>&1)
    LIST_RC=$?
    printf '%s\n' "$LIST_OUT" | sed 's/^/        /'
    if [ "$LIST_RC" -ne 0 ]; then
      echo "        ! 'opencode plugin list' retornou codigo $LIST_RC"
    fi
  else
    echo "        ! CLI sem subcomando 'plugin list' (OpenCode 1.x detectado)"
  fi
  echo "      > obs: plugins de servidor (ex.: opencode-mem) so aparecem no carregamento:"
  echo "        opencode run --standalone --print-logs --log-level debug"
fi

# 5) Limpeza de Resíduos e Travas de Sessão
echo ""
echo "[4/4] LIMPEZA E INTEGRIDADE"
find "$HOME/.cache/opencode" -maxdepth 1 -name '*.tmp' -delete 2>/dev/null || true
find "$HOME/.cache/opencode/pids" -maxdepth 1 -type f -delete 2>/dev/null || true
CACHE_SIZE=$(du -sh "$HOME/.cache/opencode" 2>/dev/null | awk '{print $1}')
echo "      • Espaço em cache: ${CACHE_SIZE:-0B}"

echo ""
echo "============================================================"
echo "  TUDO PRONTO! Conexão mapeada em: $LLAMA_BASE_URL"
echo "============================================================"
echo ""

# Transiciona a execução para o usuário final de forma universal usando su-exec
if [ "$TARGET_USER" != "root" ]; then
  exec gosu opencode bash -c 'cd /workspace && exec bash'
else
  exec bash -c 'cd /workspace && exec bash'
fi

