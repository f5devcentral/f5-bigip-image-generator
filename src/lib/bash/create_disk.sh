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



# shellcheck source=src/lib/bash/common.sh
source "$(realpath "$(dirname "${BASH_SOURCE[0]}")")/common.sh"
# shellcheck source=src/lib/bash/util/logger.sh
source "$(realpath "$(dirname "${BASH_SOURCE[0]}")")/util/logger.sh"


function create_qemu_disk {
    if [[ "$#" -ne 3 ]]; then
        log_error "Received a wrong number ($#) of parameters: $*"
        return 1
    fi

    local format="$1"
    local size="$2"
    local disk="$3"

    log_info "Creating $size disk '$disk' in format '$format' -- start time: $(date +%T)"

    local start_task
    local elapsed_time
    start_task=$(timer)

    qemu-img create -f "$format" -o size="$size" "$disk"
    local result=$?

    elapsed_time=$(timer "$start_task")

    if [[ $result -eq 0 ]]; then
        log_info "Creating $size disk '$disk' in format '$format' -- elapsed time: $elapsed_time"
    else
        log_error "Creating $size disk '$disk' in format '$format' FAILED -- elapsed time: $elapsed_time"
    fi
    return $result
}

