#!/usr/bin/env bash
# Bootstrap env vars for skills and hooks. Tries settings json first,
# falls back to filesystem resolution for anything still unset.
# Source this script (`. load-env.sh`) to export vars into the current shell.

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
. "$SCRIPT_DIR/../../hooks/knowledge/lib/resolve-env.sh"

_load_settings_env
_set_repo_root
_set_org_dir

# Export resolved vars so downstream scripts and hooks inherit them
[[ -z $REPO_NAME ]]    || export REPO_NAME
[[ -z $REPO_ROOT ]]    || export REPO_ROOT
[[ -z $PROJECT_NAME ]] || export PROJECT_NAME
[[ -z $PROJECT_ROOT ]] || export PROJECT_ROOT
[[ -z $ORG_NAME ]]     || export ORG_NAME
[[ -z $ORG_DIR ]]      || export ORG_DIR
