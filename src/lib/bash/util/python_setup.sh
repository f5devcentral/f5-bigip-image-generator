#!/bin/bash
# Copyright (C) 2019 F5 Networks, Inc
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.

PROJECT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")/../../../..")"
# shellcheck source=src/lib/bash/util/logger.sh
source "$PROJECT_DIR/src/lib/bash/util/logger.sh"

# Set PYTHONPATH variable to access python modules.
function set_python_path {
    local python_path
    if [[ ! -z "$1" ]]; then
        python_path="$1"
    else
        python_path="$PROJECT_DIR/src/lib/python"
    fi

    # Set python path
    if [[ -z "$PYTHONPATH" ]]; then
        export PYTHONPATH="$python_path"
    elif [[ $PYTHONPATH != *"$python_path"* ]]; then
        export PYTHONPATH="$PYTHONPATH:$python_path"
    fi
    log_debug "PYTHONPATH set to $PYTHONPATH"
}

# Activate a Python virtual environment.
function set_python_environment {
    local venv_dir venv_config_file venv_activation_script
    if [[ ! -z "$1" ]]; then
        venv_dir="$1"
    else
        venv_dir="$PROJECT_DIR/.venv"
    fi

    # Create the virtual environment if it isn't already configured.
    venv_config_file="$venv_dir/pyvenv.cfg"
    if [[ ! -f "$venv_config_file" ]]; then
        log_debug "Creating Python virtual environment at $venv_dir"
        python3 -m venv "$venv_dir"
    fi

    # Activate the virtual environment for this shell.  This will redirect the following to use
    # the virtual environment instead of the system environment:
    #     * Calls to the Python executable
    #     * Importing of Python modules within Python scripts
    #     * Installation of new Python modules via pip
    venv_activation_script="$venv_dir/bin/activate"
    log_debug "Activating Python virtual environment using $venv_activation_script"
    # shellcheck disable=SC1090
    source "$venv_activation_script"
}
