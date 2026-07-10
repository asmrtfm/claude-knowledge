#!/usr/bin/env bash
# Bootstrap env vars for skills and hooks. Tries settings json first,
# falls back to filesystem resolution for anything still unset.
# Source this script (`. load-env.sh`) to export vars into the current shell.

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
. "$SCRIPT_DIR/../../hooks/knowledge/lib/resolve-env.sh"

_load_settings_env
_set_repo_root
_set_org_dir

[[ -z $REPO_NAME ]]    || echo "REPO_NAME=$REPO_NAME"
[[ -z $REPO_ROOT ]]    || echo "REPO_ROOT=$REPO_ROOT"
[[ -z $PROJECT_NAME ]] || echo "PROJECT_NAME=$PROJECT_NAME"
[[ -z $PROJECT_ROOT ]] || echo "PROJECT_ROOT=$PROJECT_ROOT"
[[ -z $ORG_NAME ]]     || echo "ORG_NAME=$ORG_NAME"
[[ -z $ORG_DIR ]]      || echo "ORG_DIR=$ORG_DIR"
