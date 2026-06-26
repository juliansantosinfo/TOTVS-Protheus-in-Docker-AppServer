#!/bin/bash
#
# ==============================================================================
# SCRIPT: build.sh
# DESCRIÇÃO: Responsável por realizar o build da imagem Docker para o servidor de
#            aplicações TOTVS "appserver" e restaurar ou atualizar dependências da aplicação.
# AUTOR: Julian de Almeida Santos
# DATA: 2025-10-12
# USO: ./build.sh [OPTIONS]
#
# OPÇÕES:
#   --progress=<MODE>           Define o modo de progresso (auto|plain|tty) [padrão: auto]
#   --no-cache                  Desabilita o cache do Docker
#   --no-extract                Desabilita comprimir recursos no build e extrair no run [padrão: false]
#   --build-arg KEY=VALUE       Passa argumentos adicionais para o Docker build
#   --tag=<TAG>                 Define uma tag customizada para a imagem
#   -h, --help                  Exibe esta mensagem de ajuda
#
# EXEMPLOS:
#   ./build.sh
#   ./build.sh --progress=plain --no-cache
#   ./build.sh --no-extract --build-arg MY_VAR=value
#   DOCKER_BUILD_ARGS="--build-arg VAR1=val1 --build-arg VAR2=val2" ./build.sh
# ==============================================================================

# --- Configuração de Robustez (Boas Práticas Bash) ---
# -e: Sai imediatamente se um comando falhar.
# -u: Trata variáveis não definidas como erro.
# -o pipefail: Garante que um pipeline (ex: cat | tar) falhe se qualquer comando falhar.
set -euo pipefail

# ----------------------------------------------------
#   SEÇÃO 1: DEFINICAO DE FUNCOES AUXILIARES
# ----------------------------------------------------

    # --- Funções de Impressão ---
    print_success() {
        local message="$1"
        echo "✅ $message"
    }

    print_error() {
        local message="$1"
        echo "🚨 Erro: $message" >&2
    }

    print_warning() {
        local message="$1"
        echo "⚠️ Aviso: $message"
    }

    print_info() {
        local message="$1"
        echo "ℹ️ $message"
    }

    print_progress() {
        local message="$1"
        echo "🚀 $message"
    }

    print_verify() {
        local message="$1"
        echo "🔍 $message"
    }

    print_docker() {
        local message="$1"
        echo "🐳 $message"
    }

    show_help() {
        cat << EOF
USO: ./build.sh [OPTIONS]

OPÇÕES:
  --progress=<MODE>           Define o modo de progresso (auto|plain|tty) [padrão: auto]
  --no-cache                  Desabilita o cache do Docker
  --no-extract                Desabilita comprimir recursos no build e extrair no run [padrão: false]
  --build-arg KEY=VALUE       Passa argumentos adicionais para o Docker build
  --tag=<TAG>                 Define uma tag customizada para a imagem
  -h, --help                  Exibe esta mensagem de ajuda

EXEMPLOS:
  ./build.sh
  ./build.sh --progress=plain --no-cache
  ./build.sh --no-extract --build-arg MY_VAR=value
  DOCKER_BUILD_ARGS="--build-arg VAR1=val1 --build-arg VAR2=val2" ./build.sh

EOF
        exit 0
    }

    check_versions() {
        if [ -f "versions.env" ]; then
            # shellcheck source=versions.env
            source "versions.env"
            print_info "Versões carregadas do 'versions.env':"
        else
            print_error "Arquivo 'versions.env' não encontrado."
            exit 1
        fi
    }

    check_file() {
        local file_path=$1
        if [ ! -f "$file_path" ]; then
            print_error "Arquivo '$file_path' não encontrado."
            exit 1
        fi
    }


    check_dir() {
        local dir_path=$1
        if [ ! -d "$dir_path" ]; then
            print_error "Diretório '$dir_path' não encontrado."
            exit 1
        fi
    }

# ----------------------------------------------------
#   SEÇÃO 2: PARSE DE ARGUMENTOS
# ----------------------------------------------------

    DOCKER_PROGRESS="auto"
    DOCKER_NO_CACHE=""
    COMPRESS_RESOURCES="true"
    CUSTOM_TAG=""
    BUILD_ARGS=()

    while [[ $# -gt 0 ]]; do
        case $1 in
            --progress=*)
                DOCKER_PROGRESS="${1#*=}"
                shift
                ;;
            --no-cache)
                DOCKER_NO_CACHE="--no-cache"
                shift
                ;;
            --no-compress)
                COMPRESS_RESOURCES="false"
                shift
                ;;
            --build-arg)
                BUILD_ARGS+=("--build-arg" "$2")
                shift 2
                ;;
            --build-arg=*)
                BUILD_ARGS+=("--build-arg" "${1#*=}")
                shift
                ;;
            --tag=*)
                CUSTOM_TAG="${1#*=}"
                shift
                ;;
            -h|--help)
                show_help
                ;;
            *)
                print_error "Opção desconhecida: $1"
                show_help
                ;;
        esac
    done

# ----------------------------------------------------
#   SEÇÃO 3: DEFINIÇÕES VARIAVEIS
# ----------------------------------------------------

    check_versions

    # Detecta se está usando imagem base customizada
    USING_CUSTOM_BASE="${USING_CUSTOM_BASE:-false}"
    if [[ "${GITHUB_ACTIONS:-false}" == "true" || "${USING_CUSTOM_BASE}" == "true" ]] && [[ -n "${IMAGE_BASE:-}" ]]; then
        USING_CUSTOM_BASE=true
        # COMPRESS_RESOURCES="false" # Se utiliza imagem custom não comprime os recursos.
        print_info "Imagem base customizada detectada: ${IMAGE_BASE}"
    fi

    TOTVS_DIR="./totvs"
    TOTVS_PROTHEUS_DIR="${TOTVS_DIR}/protheus"
    TOTVS_PROTHEUS_FILES=(
        "${TOTVS_PROTHEUS_DIR}/bin/appserver/appsrvlinux"
        "${TOTVS_PROTHEUS_DIR}/bin/appserver/webapp.so"
        "${TOTVS_PROTHEUS_DIR}/apo/tttm120.rpo"
    )
    TOTVS_PROTHEUS_DATA_DIR="${TOTVS_DIR}/protheus_data"
    TOTVS_SYSTEM_DIR="${TOTVS_PROTHEUS_DATA_DIR}/system"
    TOTVS_SYSTEM_FILES=(
        "${TOTVS_SYSTEM_DIR}/sigacom.xnu"
        "${TOTVS_SYSTEM_DIR}/sigaest.xnu"
        "${TOTVS_SYSTEM_DIR}/sigafat.xnu"
        "${TOTVS_SYSTEM_DIR}/sigafin.xnu"
        "${TOTVS_SYSTEM_DIR}/sigacfg.xnu"
    )
    TOTVS_SYSTEMLOAD_DIR="${TOTVS_PROTHEUS_DATA_DIR}/systemload"
    TOTVS_SYSTEMLOAD_FILES=(
        "${TOTVS_SYSTEMLOAD_DIR}/sx2.unq"
        "${TOTVS_SYSTEMLOAD_DIR}/hlppor.txt"
        "${TOTVS_SYSTEMLOAD_DIR}/hlpeng.txt"
        "${TOTVS_SYSTEMLOAD_DIR}/hlpspa.txt"
        "${TOTVS_SYSTEMLOAD_DIR}/sxsbra.txt"
    )

    # Define o diretório atual
    if ! cd "$(dirname -- "$0")" &> /dev/null; then
        print_error "Não foi possível acessar o diretório '$CURRENT_PATH'."
    fi

    # Define a tag final
    if [[ -n "$CUSTOM_TAG" ]]; then
        DOCKER_TAG="$CUSTOM_TAG"
    else
        DOCKER_TAG="${DOCKER_USER}/${APPSERVER_IMAGE_NAME}:${APPSERVER_VERSION}"
    fi

    # Adiciona build args de variável de ambiente se existir
    if [[ -n "${DOCKER_BUILD_ARGS:-}" ]]; then
        BUILD_ARGS+=($DOCKER_BUILD_ARGS)
    fi

# ----------------------------------------------------
#   SEÇÃO 4: PREPARAÇÃO DOS RECURSOS
# ----------------------------------------------------

    print_verify "Verificando se o Docker está instalado e funcionando..."

        if ! command -v docker &> /dev/null; then
            print_error "Docker não está instalado ou não está no PATH."
            exit 1
        fi

        if ! docker info &> /dev/null; then
            print_error "Docker não está rodando ou não há permissões para acessá-lo."
            exit 1
        fi

        print_success " * Docker está instalado e funcionando corretamente."

    # ----------------------------------------------------------------------

    print_verify "Verificando se o arquivo Dockerfile existe..."

        check_file "Dockerfile"

        print_success " * Arquivo 'Dockerfile' encontrado."

    # Pula validação de recursos se estiver usando imagem base customizada
    if [[ "$USING_CUSTOM_BASE" == "true" ]]; then
        print_info "Usando imagem base customizada - pulando validação de recursos locais"
    else

        for dir in "${TOTVS_DIR}" "${TOTVS_PROTHEUS_DIR}" "${TOTVS_PROTHEUS_DATA_DIR}"; do
            print_verify "Verificando o diretório '${dir}'..."
            
            check_dir "${dir}"
            
            print_success " * Diretório '${dir}' encontrado."
        done

        # ----------------------------------------------------------------------

        print_verify "Verificando o arquivo em protheus/..."

        rpo_found=false
        for rpo_file in "tttm120.rpo" "tttp120.rpo" "ttte120.rpo" "ttts120.rpo"; do
            rpo_path="${TOTVS_PROTHEUS_DIR}/apo/${rpo_file}"
            if [ -f "$rpo_path" ]; then
                TOTVS_RPO_FILE="$rpo_path"
                rpo_found=true
                break
            fi
        done

        if [ "$rpo_found" = false ]; then
            if [[ -f "unpack.sh" ]] && [[ -d "packages" ]]; then
                print_info "RPO não encontrado. Tentando extrair..."
                ./unpack.sh rpo
                # Verifica novamente
                for rpo_file in "tttm120.rpo" "tttp120.rpo" "ttte120.rpo" "ttts120.rpo"; do
                    rpo_path="${TOTVS_PROTHEUS_DIR}/apo/${rpo_file}"
                    if [ -f "$rpo_path" ]; then
                        TOTVS_RPO_FILE="$rpo_path"
                        rpo_found=true
                        break
                    fi
                done
            fi
            
            if [ "$rpo_found" = false ]; then
                print_error "Nenhum arquivo RPO encontrado em '${TOTVS_PROTHEUS_DIR}/apo/'."
                exit 1
            fi
        fi

        for file in "${TOTVS_PROTHEUS_FILES[@]}"; do
            if [ ! -f "$file" ]; then
                if [[ -f "unpack.sh" ]] && [[ -d "packages" ]]; then
                    if [[ "$file" == *"appsrvlinux"* ]]; then
                        print_info "AppServer binário não encontrado. Tentando extrair..."
                        ./unpack.sh appserver
                    elif [[ "$file" == *"webapp.so"* ]]; then
                        print_info "WebApp não encontrado. Tentando extrair..."
                        ./unpack.sh webapp
                    fi
                fi
            fi
            
            check_file "${file}"
            print_success " * Arquivo '${file}' encontrado."
        done

        # ----------------------------------------------------------------------

        print_verify "Verificando o diretório system..."

        check_dir "${TOTVS_SYSTEM_DIR}"

        print_success " * Diretório '${TOTVS_SYSTEM_DIR}' encontrado."

        print_verify "Verificando o arquivo em protheus_data/system/..."
        for file in "${TOTVS_SYSTEM_FILES[@]}"; do
            if [ ! -f "$file" ]; then
                if [[ -f "unpack.sh" ]] && [[ -d "packages" ]]; then
                    print_info "Arquivos de menu não encontrados. Tentando extrair..."
                    ./unpack.sh menus
                    break
                fi
            fi
        done
        
        for file in "${TOTVS_SYSTEM_FILES[@]}"; do
            check_file "${file}"
            print_success " * Arquivo '${file}' encontrado."
        done 

        # ----------------------------------------------------------------------

        print_verify "Verificando o diretório systemload..."

        check_dir "${TOTVS_SYSTEMLOAD_DIR}"

        print_success " * Diretório '${TOTVS_SYSTEMLOAD_DIR}' encontrado."

        print_verify "Verificando o arquivo em protheus_data/systemload/..."
        for file in "${TOTVS_SYSTEMLOAD_FILES[@]}"; do
            if [ ! -f "$file" ]; then
                if [[ -f "unpack.sh" ]] && [[ -d "packages" ]]; then
                    if [[ "$file" == *"hlp"* ]]; then
                        print_info "Arquivos de help não encontrados. Tentando extrair..."
                        ./unpack.sh helps
                    elif [[ "$file" == *"sx"* ]]; then
                        print_info "Arquivos de dicionário não encontrados. Tentando extrair..."
                        ./unpack.sh dictionaries
                    fi
                    break
                fi
            fi
        done
        
        for file in "${TOTVS_SYSTEMLOAD_FILES[@]}"; do
            check_file "${file}"
            print_success " * Arquivo '${file}' encontrado."
        done

    fi 

# ----------------------------------------------------
#   SEÇÃO 5: EXECUÇÃO DO DOCKER BUILD
# ----------------------------------------------------

    print_docker "Iniciando Docker build..."
    print_info "Tag: $DOCKER_TAG"
    print_info "Progress: $DOCKER_PROGRESS"
    print_info "Cache: $([ -n "$DOCKER_NO_CACHE" ] && echo "Desabilitado" || echo "Habilitado")"
    print_info "Compress Resources: $([ "$COMPRESS_RESOURCES" = "true" ] && echo "Habilitado" || echo "Desabilitado")"
    [[ ${#BUILD_ARGS[@]} -gt 0 ]] && print_info "Build Args: ${BUILD_ARGS[*]}"

    # Detecta se está rodando no GitHub Actions e adiciona IMAGE_BASE
    if [[ "$USING_CUSTOM_BASE" == "true" ]]; then
        BUILD_ARGS+=("--build-arg" "IMAGE_BASE=${IMAGE_BASE}")
        print_info "Usando IMAGE_BASE: ${IMAGE_BASE}"
    fi

    docker build \
        --build-arg COMPRESS_RESOURCES="$COMPRESS_RESOURCES" \
        ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"} \
        $DOCKER_NO_CACHE \
        --progress="$DOCKER_PROGRESS" \
        -t "$DOCKER_TAG" . || {
            print_error "Falha no Docker build. Verifique os logs acima."
            exit 1
        }

    print_success "Docker build finalizado com sucesso!"
    print_success "Imagem: $DOCKER_TAG"
