#!/bin/bash
#
# ==============================================================================
# SCRIPT: entrypoint.sh
# DESCRIÇÃO: Ponto de entrada do container AppServer. Realiza validações de rede,
#            extração de recursos e inicialização do servidor Protheus.
# AUTOR: Julian de Almeida Santos
# DATA: 2025-10-12
# USO: ./entrypoint.sh
# ==============================================================================

# Ativa modo de depuração se a variável DEBUG_SCRIPT estiver como true/1/yes
if [[ "${DEBUG_SCRIPT:-}" =~ ^(true|1|yes|y)$ ]]; then
    set -x
fi

#---------------------------------------------------------------------

## 🚀 AGUARDANDO DISPONIBILIDADE DA INFRAESTRUTURA (NETWORK CHECK)

    echo ""
    echo "------------------------------------------------------"
    echo "⏳ AGUARDANDO DISPONIBILIDADE DA INFRAESTRUTURA"
    echo "------------------------------------------------------"

    # 1. Validando License Server
    RETRIES_LIC=0
    MAX_RETRIES_LIC="${LICENSE_WAIT_RETRIES:-30}"
    INTERVAL_LIC="${LICENSE_WAIT_INTERVAL:-2}"
    LICENSESERVER_CHECK="${LICENSESERVER_CHECK:-yes}"

    if [[ "${LICENSESERVER_CHECK:-}" =~ ^(true|1|yes|y)$ ]]; then

      echo "🔍 Verificando conectividade com License Server ($APPSERVER_LICENSE_SERVER:$APPSERVER_LICENSE_PORT)..."
      until timeout 1 bash -c "echo > /dev/tcp/$APPSERVER_LICENSE_SERVER/$APPSERVER_LICENSE_PORT" > /dev/null 2>&1; do
          RETRIES_LIC=$((RETRIES_LIC + 1))
          if [ $RETRIES_LIC -ge "$MAX_RETRIES_LIC" ]; then
              echo "❌ ERRO: O License Server em $APPSERVER_LICENSE_SERVER:$APPSERVER_LICENSE_PORT não ficou disponível após $MAX_RETRIES_LIC tentativas."
              exit 1
          fi
          echo "  - [$RETRIES_LIC/$MAX_RETRIES_LIC] License Server ainda não responde. Aguardando ${INTERVAL_LIC}s..."
          sleep "$INTERVAL_LIC"
      done
      echo "✅ Conexão TCP estabelecida com o License Server!"

    fi

    # 2. Validando DBAccess
    RETRIES_DBA=0
    MAX_RETRIES_DBA="${DBACCESS_WAIT_RETRIES:-30}"
    INTERVAL_DBA="${DBACCESS_WAIT_INTERVAL:-2}"
    DBACCESS_CHECK="${DBACCESS_CHECK:-yes}"

    if [[ "${DBACCESS_CHECK:-}" =~ ^(true|1|yes|y)$ ]]; then

      echo "🔍 Verificando conectividade com DBAccess ($APPSERVER_DBACCESS_SERVER:$APPSERVER_DBACCESS_PORT)..."
      until timeout 1 bash -c "echo > /dev/tcp/$APPSERVER_DBACCESS_SERVER/$APPSERVER_DBACCESS_PORT" > /dev/null 2>&1; do
          RETRIES_DBA=$((RETRIES_DBA + 1))
          if [ $RETRIES_DBA -ge "$MAX_RETRIES_DBA" ]; then
              echo "❌ ERRO: O DBAccess em $APPSERVER_DBACCESS_SERVER:$APPSERVER_DBACCESS_PORT não ficou disponível após $MAX_RETRIES_DBA tentativas."
              exit 1
          fi
          echo "  - [$RETRIES_DBA/$MAX_RETRIES_DBA] DBAccess ainda não responde. Aguardando ${INTERVAL_DBA}s..."
          sleep "$INTERVAL_DBA"
      done
      echo "✅ Conexão TCP estabelecida com o DBAccess!"
    fi
    
    echo "✅ Infraestrutura disponível!"

#---------------------------------------------------------------------

## 🚀 VARIÁVEIS DE CONFIGURAÇÃO

APPSERVER_MANAGER="/service.sh"
APPSERVER_MODE="${APPSERVER_MODE:-application}"
APPSERVER_CONSOLEFILE="${APPSERVER_CONSOLEFILE:-/totvs/protheus/bin/appserver/console.log}"

EXTRACT_RESOURCES="${EXTRACT_RESOURCES:-true}"
EXTRACT_RESOURCES="${EXTRACT_RESOURCES,,}"
TOTVS_DIR="/totvs"
PROTHEUS_FILE="${TOTVS_DIR}/protheus.tar.gz"
PROTHEUS_DATA_FILE="${TOTVS_DIR}/protheus_data.tar.gz"
RESOURCES_DIR="${TOTVS_DIR}/resources"

# ---------------------------------------------------------------------

## 🚀 FUNÇÕES DE CONTROLE DO APPSERVER

  start_appserver() {
    echo "🚀 Iniciando serviço TOTVS AppServer..."
    "${APPSERVER_MANAGER}" start
  }

  stop_appserver() {
    echo "🛑 Finalizando serviço TOTVS AppServer..."
    "${APPSERVER_MANAGER}" stop
  }

# ---------------------------------------------------------------------

## 🚀 FUNÇÃO PRINCIPAL DE EXECUÇÃO

  main() {
    echo ""
    echo "------------------------------------------------------"
    echo "🚀 INÍCIO DA EXECUÇÃO PRINCIPAL"
    echo "------------------------------------------------------"
      
    start_appserver

    echo
    echo "📜 Monitorando logs em tempo real:"
    echo "-----------------------------------"
    # Cria o arquivo de log se ele não existir
    touch "${APPSERVER_CONSOLEFILE}"
    # Monitora o log, mantendo o PID 1 vivo (necessário para o Docker)
    tail -n 200 -f "${APPSERVER_CONSOLEFILE}"
  }

# ---------------------------------------------------------------------

## 🚀 EXTRAÇÃO DE RECURSOS

if [[ "$EXTRACT_RESOURCES" =~ ^(true|1|yes|y)$ ]]; then

  echo ""
  echo "------------------------------------------------------"
  echo "🧩 EXTRAÇÃO DE RECURSOS"
  echo "------------------------------------------------------"
  echo "🧩 Iniciando extração de recursos para a aplicação..."

  cd "$TOTVS_DIR"

  # --- Protheus (protheus.tar.gz) ---
  if [[ -f "$PROTHEUS_FILE" ]]; then
    echo "📦 Extraindo **protheus.tar.gz**..."
    tar --keep-old-files -xzf "$PROTHEUS_FILE" -C "$TOTVS_DIR"
    rm -f "$PROTHEUS_FILE"
  else
        echo "⚠️  Arquivo **protheus.tar.gz** não encontrado. Pulando extração."
  fi

  # --- Protheus_data (protheus_data.tar.gz) ---
  if [[ -f "$PROTHEUS_DATA_FILE" ]]; then
    echo "📦 Extraindo **protheus_data.tar.gz**..."
    tar --keep-old-files -xzf "$PROTHEUS_DATA_FILE" -C "$TOTVS_DIR"
    rm -f "$PROTHEUS_DATA_FILE"
  else
    echo "⚠️  Arquivo **protheus_data.tar.gz** não encontrado. Pulando extração."
  fi

  # --- appserver.ini ---
  local_ini="/totvs/protheus/bin/appserver/appserver.ini"
  if [[ ! -s "$local_ini" ]]; then
    echo "📝 Verificando e copiando **appserver.ini** padrão..."
    mkdir -p "$(dirname "$local_ini")"
    case "$APPSERVER_MODE" in
      application)
        echo "⚙️  Modo: **'$APPSERVER_MODE'** — Aplicando configuração padrão: appserver.ini"
        cp -f "$RESOURCES_DIR/appserver.ini" "$local_ini"
        ;;
      rest)
        echo "⚙️  Modo: **'$APPSERVER_MODE'** — Aplicando configuração padrão: appserver_rest.ini"
        cp -f "$RESOURCES_DIR/appserver_rest.ini" "$local_ini"
        ;;
      sqlite)
        echo "⚙️  Modo: **'$APPSERVER_MODE'** — Aplicando configuração padrão: appserver_sqlite.ini"
        cp -f "$RESOURCES_DIR/appserver_sqlite.ini" "$local_ini"
        ;;
      *)
        echo "❗  Modo desconhecido: **'$APPSERVER_MODE'**. Aplicando configuração padrão genérica."
        cp -f "$RESOURCES_DIR/appserver.ini" "$local_ini"
        ;;
    esac
  else
    echo "⚙️  Modo: **'$APPSERVER_MODE'**"
    echo "📝 Utilizando **appserver.ini** pré-existente (volume-mounted)."
  fi

  echo "✅ Recursos extraídos com sucesso!"
else
  echo "⏭️ Extração de recursos desabilitada."
  echo
fi

# ---------------------------------------------------------------------

## 🚀 EXECUÇÃO FINAL

# Este bloco garante que a função 'main' seja executada apenas se o script for 
# executado diretamente, e não se for 'sourced'.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi