#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "${DEPLOY_PROJECT_DIR:-}" ]; then
  NOW="$(date '+%Y/%m/%d %H:%M:%S')"
  echo "[$NOW] ERROR DEPLOY_PROJECT_DIR NOT SET"
  echo "[$NOW] ERROR DEPLOY_PROJECT_DIR NOT SET" >>"$SCRIPT_DIR/deploy.log"
  exit 1
fi

PROJECT_PARENT="$(cd "$(dirname "$DEPLOY_PROJECT_DIR")" && pwd)"
PROJECT_NAME="$(basename "$DEPLOY_PROJECT_DIR")"
PROJECT_DIR="$PROJECT_PARENT/$PROJECT_NAME"
PROJECT_ROOT="$PROJECT_PARENT/"
GIT_BRANCH="${DEPLOY_GIT_BRANCH:-dev}"
PM2_APP_NAME="${DEPLOY_PM2_APP_NAME:-server}"
DEPLOY_LOG="${DEPLOY_LOG_PATH:-$SCRIPT_DIR/deploy.log}"
REMOTE_URL="${DEPLOY_REMOTE_URL:-git@github.com:liuchen112233/yayaspeakingserver.git}"
NPM_BUILD_SCRIPT="${DEPLOY_BUILD_SCRIPT:-build:dev}"

log() {
  local now
  now="$(date '+%Y/%m/%d %H:%M:%S')"
  echo "[$now] $1"
  echo "[$now] $1" >>"$DEPLOY_LOG"
}

npm_install_with_retry() {
  local max_retry=3
  local try_count=0
  while [ "$try_count" -lt "$max_retry" ]; do
    try_count=$((try_count + 1))
    log "STEP2 NPM INSTALL TRY $try_count"
    if npm install --no-fund --no-audit 2>&1 | tee -a "$DEPLOY_LOG"; then
      log "OK NPM INSTALL SUCCESS"
      return 0
    fi
    if [ "$try_count" -lt "$max_retry" ]; then
      log "WARN NPM INSTALL FAILED RETRY $try_count"
      sleep 5
    fi
  done
  log "ERROR NPM INSTALL FAILED"
  return 1
}

npm_build_with_retry() {
  local max_retry=2
  local try_count=0
  while [ "$try_count" -lt "$max_retry" ]; do
    try_count=$((try_count + 1))
    log "STEP3 NPM RUN BUILD $NPM_BUILD_SCRIPT TRY $try_count"
    if npm run "$NPM_BUILD_SCRIPT" 2>&1 | tee -a "$DEPLOY_LOG"; then
      log "OK NPM RUN BUILD SUCCESS"
      return 0
    fi
    if [ "$try_count" -lt "$max_retry" ]; then
      log "WARN NPM RUN BUILD FAILED RETRY $try_count"
      sleep 5
    fi
  done
  log "ERROR NPM RUN BUILD FAILED"
  return 1
}

log "START DEPLOY"

if [ "${DEPLOY_SKIP_PM2:-}" != "1" ]; then
  log "STEP0 PM2 STOP $PM2_APP_NAME"
  pm2 stop "$PM2_APP_NAME" >>"$DEPLOY_LOG" 2>&1 || true
fi

if [ "$PROJECT_NAME" = "server" ] && [ -d "$PROJECT_DIR/public" ]; then
  log "STEP0 BACKUP PUBLIC FROM $PROJECT_DIR/public TO ${PROJECT_ROOT}public"
  rm -rf "${PROJECT_ROOT}public"
  cp -a "$PROJECT_DIR/public" "${PROJECT_ROOT}public" >>"$DEPLOY_LOG" 2>&1
fi

if [ -d "$PROJECT_DIR" ]; then
  log "STEP0 CLEAN PROJECT_DIR"
  chmod -R u+rwX "$PROJECT_DIR" >>"$DEPLOY_LOG" 2>&1 || true
  rm -rf "$PROJECT_DIR"
  if [ -e "$PROJECT_DIR" ]; then
    log "ERROR CLEAN PROJECT_DIR FAILED $PROJECT_DIR"
    exit 1
  fi
fi

mkdir -p "$HOME/.ssh"
ssh-keyscan -t rsa,ecdsa,ed25519 github.com >>"$HOME/.ssh/known_hosts" 2>>"$DEPLOY_LOG" || true

if ! command -v git >/dev/null 2>&1; then
  log "ERROR GIT NOT FOUND"
  exit 1
fi

log "STEP1 GIT CLONE $GIT_BRANCH"
cd "$PROJECT_ROOT" || exit 1
if ! git clone "$REMOTE_URL" "$PROJECT_DIR" >>"$DEPLOY_LOG" 2>&1; then
  log "ERROR GIT CLONE FAILED"
  exit 1
fi

cd "$PROJECT_DIR" || exit 1
if ! git checkout "$GIT_BRANCH" >>"$DEPLOY_LOG" 2>&1; then
  log "ERROR GIT CHECKOUT FAILED"
  exit 1
fi

log "OK GIT PREPARE SUCCESS"

if [ "$PROJECT_NAME" = "server" ] && [ -d "${PROJECT_ROOT}public" ]; then
  log "STEP1 RESTORE PUBLIC TO $PROJECT_DIR/public"
  rm -rf "$PROJECT_DIR/public"
  cp -a "${PROJECT_ROOT}public" "$PROJECT_DIR/public" >>"$DEPLOY_LOG" 2>&1
fi

log "STEP2 NPM INSTALL"
if [ -f "$PROJECT_DIR/package.json" ]; then
  npm_install_with_retry || exit 1
else
  log "INFO NO PACKAGE.JSON SKIP NPM INSTALL"
fi

log "STEP3 NPM RUN BUILD"
HAS_BUILD=0
if [ -f "$PROJECT_DIR/package.json" ]; then
  cd "$PROJECT_DIR" || exit 1
  if node -e "try{const p=require('./package.json');const s=p.scripts&&p.scripts.build;process.exit(s?0:1);}catch(e){process.exit(1)}"; then
    HAS_BUILD=1
    npm_build_with_retry || exit 1
  else
    log "INFO NO BUILD SCRIPT SKIP BUILD"
  fi
fi

if [ "$HAS_BUILD" = "1" ]; then
  log "STEP4 SKIP PM2 START BECAUSE BUILD SCRIPT EXISTS"
else
  log "STEP4 PM2 START $PM2_APP_NAME"
  if ! pm2 start "$PROJECT_DIR/app.js" --name "$PM2_APP_NAME" --update-env >>"$DEPLOY_LOG" 2>&1; then
    log "ERROR PM2 START FAILED"
    exit 1
  fi
fi

log "OK DEPLOY FINISHED"
exit 0
