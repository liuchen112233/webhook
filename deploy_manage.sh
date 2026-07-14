#!/usr/bin/env bash

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_ENV="${DEPLOY_ENV:-test}"

case "$DEPLOY_ENV" in
  test)
    export DEPLOY_GIT_BRANCH="${MANAGE_DEPLOY_BRANCH_TEST:-dev}"
    export DEPLOY_BUILD_SCRIPT="${MANAGE_DEPLOY_BUILD_SCRIPT_TEST:-build:dev}"
    export DEPLOY_PROJECT_DIR="${MANAGE_DEPLOY_PROJECT_DIR_TEST:-client-test}"
    export DEPLOY_PM2_APP_NAME="${MANAGE_DEPLOY_PM2_APP_NAME_TEST:-client-test}"
    export DEPLOY_REMOTE_URL="${MANAGE_DEPLOY_REMOTE_URL_TEST:-${FRONT_DEPLOY_REMOTE_URL:-git@github.com:liuchen112233/lanya.git}}"
    export DEPLOY_LOG_PATH="${MANAGE_DEPLOY_LOG_PATH_TEST:-$SCRIPT_DIR/deploy_manage_test.log}"
    ;;
  prod)
    export DEPLOY_GIT_BRANCH="${MANAGE_DEPLOY_BRANCH_PROD:-prod}"
    export DEPLOY_BUILD_SCRIPT="${MANAGE_DEPLOY_BUILD_SCRIPT_PROD:-build}"
    export DEPLOY_PROJECT_DIR="${MANAGE_DEPLOY_PROJECT_DIR_PROD:-client}"
    export DEPLOY_PM2_APP_NAME="${MANAGE_DEPLOY_PM2_APP_NAME_PROD:-client}"
    export DEPLOY_REMOTE_URL="${MANAGE_DEPLOY_REMOTE_URL_PROD:-${FRONT_DEPLOY_REMOTE_URL:-git@github.com:liuchen112233/lanya.git}}"
    export DEPLOY_LOG_PATH="${MANAGE_DEPLOY_LOG_PATH_PROD:-$SCRIPT_DIR/deploy_manage_prod.log}"
    ;;
  *)
    echo "Unsupported DEPLOY_ENV: $DEPLOY_ENV"
    exit 1
    ;;
esac

exec bash "$SCRIPT_DIR/auto_deploy.sh"
