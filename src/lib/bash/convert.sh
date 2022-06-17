#!/bin/bash
# Copyright (C) 2019-2022 F5 Inc
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
source "$(realpath "$(dirname "${BASH_SOURCE[0]}")")/../bash/common.sh"
# shellcheck source=src/lib/bash/util/logger.sh
source "$(realpath "$(dirname "${BASH_SOURCE[0]}")")/../bash/util/logger.sh"

# Convert the src_disk into the given format using "qemu-img convert"
# Usage: <dest_format> <src_disk> <dest_disk> [options]
# where
#   dest_format: disk format to which the src_disk needs to be converted to
#   src_disk: source disk to be converted
#   dest_disk: new disk
#   options: optional argument specifying the comma separated key=value pairs
#       as supported by qemu-img
# return 0 if passed; otherwise return 1
function convert_qemu_img() {
    if [[ "$#" -lt 3 ]]; then
        log_info "Received a wrong number ($#) of parameters: $*"
        return 1
    fi

    local dest_format="$1"
    local src_disk="$2"
    local dest_disk="$3"
    local disk_options="$4"
    if [[ -n "$disk_options" ]]; then
        # Append qemu-img cmdline option '-o' to the comma-separated key=value
        # options pairs.
        disk_options="-o $disk_options"
    fi

    log_info "Conversion to $dest_format -- start time: $(date +%T)"
    local start_task
    start_task=$(timer)

    local result
    # qemu_img might want receive argument separately, hence shellcheck exception
    # shellcheck disable=SC2086
    execute_cmd qemu-img convert -p -O "$dest_format" $disk_options "$src_disk" "$dest_disk"
    result=$?

    local elapsed_time
    elapsed_time=$(timer "$start_task")
    if [[ "$result" -eq 0 ]]; then
        log_info "Conversion to $dest_format -- elapsed time: $elapsed_time"
        return 0
    else
        log_error "Conversion to $dest_format failed -- elapsed time: $elapsed_time"
        return 1
    fi
}

