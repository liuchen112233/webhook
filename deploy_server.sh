#!/usr/bin/env bash

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_ENV="${DEPLOY_ENV:-test}"

case "$DEPLOY_ENV" in
  test)
    export DEPLOY_GIT_BRANCH="${SERVER_DEPLOY_BRANCH_TEST:-dev}"
    export DEPLOY_BUILD_SCRIPT="${SERVER_DEPLOY_BUILD_SCRIPT_TEST:-build:dev}"
    export DEPLOY_PROJECT_DIR="${SERVER_DEPLOY_PROJECT_DIR_TEST:-server-test}"
    export DEPLOY_PM2_APP_NAME="${SERVER_DEPLOY_PM2_APP_NAME_TEST:-server-test}"
    export DEPLOY_REMOTE_URL="${SERVER_DEPLOY_REMOTE_URL_TEST:-${DEPLOY_REMOTE_URL:-git@github.com:liuchen112233/yayaspeakingserver.git}}"
    export DEPLOY_LOG_PATH="${SERVER_DEPLOY_LOG_PATH_TEST:-$SCRIPT_DIR/deploy_server_test.log}"
    ;;
  prod)
    export DEPLOY_GIT_BRANCH="${SERVER_DEPLOY_BRANCH_PROD:-prod}"
    export DEPLOY_BUILD_SCRIPT="${SERVER_DEPLOY_BUILD_SCRIPT_PROD:-build}"
    export DEPLOY_PROJECT_DIR="${SERVER_DEPLOY_PROJECT_DIR_PROD:-server}"
    export DEPLOY_PM2_APP_NAME="${SERVER_DEPLOY_PM2_APP_NAME_PROD:-server}"
    export DEPLOY_REMOTE_URL="${SERVER_DEPLOY_REMOTE_URL_PROD:-${DEPLOY_REMOTE_URL:-git@github.com:liuchen112233/yayaspeakingserver.git}}"
    export DEPLOY_LOG_PATH="${SERVER_DEPLOY_LOG_PATH_PROD:-$SCRIPT_DIR/deploy_server_prod.log}"
    ;;
  *)
    echo "Unsupported DEPLOY_ENV: $DEPLOY_ENV"
    exit 1
    ;;
esac

exec bash "$SCRIPT_DIR/auto_deploy.sh"
