#!/bin/bash
set -e

IMAGE="<usuario>/<projeto>:latest"

echo "=== OpenCode Sandbox - Build ==="
echo ""

if ! docker info >/dev/null 2>&1; then
    echo "ERRO: Docker daemon nao esta rodando."
    echo "  macOS: abra o Docker Desktop (open -a Docker) e aguarde ficar pronto"
    echo "  Linux: sudo systemctl start docker"
    exit 1
fi

echo "Docker: $(docker version --format '{{.Server.Version}}')"
echo ""

# Multi-plataforma por padrao: cobre Linux/Windows x64 e Apple Silicon.
# Use PLATFORM=linux/amd64 para build local rapido (somente x64).
PLATFORM="${PLATFORM:-linux/amd64,linux/arm64}"

echo "=== Construindo imagem ==="
echo "Plataformas: ${PLATFORM}"

if [ "${PLATFORM}" = "linux/amd64" ]; then
    # Build simples, sem emulacao, mais rapido
    docker compose build
else
    # buildx com emulacao para gerar as duas arquiteturas
    docker buildx build \
        --platform "${PLATFORM}" \
        -t "${IMAGE}" \
        --push \
        .
fi

echo ""
echo "=== Resultado ==="
docker images "${IMAGE}" --format "Tamanho: {{.Size}}" 2>/dev/null || true

echo ""
echo "=== Build concluido ==="
echo ""
echo "Subir o container:"
echo "  docker compose up -d"
echo ""
echo "Abrir no VSCode (Dev Containers):"
echo "  code .devcontainer/devcontainer.json"
echo ""
echo "Publicar no Docker Hub (se ja buildou local):"
echo "  docker login"
echo "  docker push ${IMAGE}"
