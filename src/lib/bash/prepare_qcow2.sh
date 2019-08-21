#!/bin/bash -e
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

function print_qcow2_json {
    local status="$1"
    local output_json="$2"

    if [[ $# != 2 ]] || [[ -z "$status" ]] || [[ -z "$output_json" ]]; then
        log_error "Usage: ${FUNCNAME[0]} <status> <output_json>"
        return 1
    fi

    if jq -M -n \
            --arg description "QCOW2 disk status" \
            --arg build_host "$HOSTNAME" \
            --arg build_source "$(basename "${BASH_SOURCE[0]}")" \
            --arg build_user "$USER" \
            --arg status "$status" \
            '{ description: $description,
            build_host: $build_host,
            build_source: $build_source,
            build_user: $build_user,
            status: $status }' \
            > "$output_json"
    then
        log_info "Wrote qcow2 generation output to '$output_json'."
    else
        log_error "Failed to write '$output_json'."
        return 1
    fi
}


function prepare_qcow2 {
    local raw_disk="$1"
    local bundle_name="$2"
    local artifacts_dir="$3"
    local output_json="$4"

    local success_token="success"
    local failure_token="failure"
    if [[ $# != 4 ]] || [[ -z "$raw_disk" ]] || [[ -z "$bundle_name" ]] || \
            [[ -z "$artifacts_dir" ]] || [[ -z "$output_json" ]]; then
        log_error "Usage: ${FUNCNAME[0]} <raw_disk> <bundle_name> <artifacts_dir> <output_json>"
        print_qcow2_json "$failure_token" "$output_json"
        return 1
    elif [[ ! -f "$artifacts_dir/$raw_disk" ]]; then
        log_error "Raw disk '$raw_disk' doesn't exist in '$artifacts_dir'."
        print_qcow2_json "$failure_token" "$output_json"
        return 1
    fi

    # Check if the current execution is a re-run of previously successful execution.
    if check_previous_run_status "$output_json" "$bundle_name" ; then
        log_info "Skipping qcow2 generation as the output virtual disk '$bundle_name'" \
                "was generated successfully earlier."
        return 0
    fi

    raw_disk="$(realpath "$artifacts_dir/$raw_disk")"
    artifacts_dir=$(realpath "$artifacts_dir")
    output_json="$(realpath "$output_json")"

    local temp_dir
    temp_dir=$(mktemp -d -p "$artifacts_dir")

    local qcow2_disk_file
    qcow2_disk_file="$temp_dir/$(basename "$bundle_name")"
    qcow2_disk_file="${qcow2_disk_file/%.zip}"

    # Convert the raw disk to qcow2.
    if ! "$(realpath "$( dirname "${BASH_SOURCE[0]}" )")/../../bin/convert" \
            "qcow2" "$raw_disk" "$qcow2_disk_file" "compat=0.10" ; then
        log_error "Conversion of $raw_disk to 'qcow2' failed."
        print_qcow2_json "$failure_token" "$output_json"
        remove_dir "$temp_dir"
        return 1
    fi

    log_info "Compressing QCOW2 -- starting."
    local start_task
    start_task=$(timer)
    local zip_file
    zip_file="$qcow2_disk_file.zip"

    # remove the old zip file
    if [[ -n "$zip_file" ]] && [[ -f "$zip_file" ]]; then
        rm -rf "$zip_file"
    fi

    # add the disk file to the zip file
    execute_cmd rm -f "$zip_file"
    if ! execute_cmd zip -1 -j "$zip_file" "$qcow2_disk_file" ; then
        log_error "Failed to compress '$qcow2_disk_file'."
        print_qcow2_json "$failure_token" "$output_json"
        remove_dir "$temp_dir"
        return 1
    fi

    # Generate md5 sum for the zips.
    if ! gen_md5 "$zip_file"; then
        log_error "MD5 generation for '$zip_file' failed."
        print_qcow2_json "$failure_token" "$output_json"
        remove_dir "$temp_dir"
        return 1
    fi
    log_info "Compressing QCOW2 -- elapsed time: $(timer "$start_task")"

    log_debug "Contents of zip file '$zip_file':"
    log_debug "--------------------------------------"
    log_cmd_output "$DEFAULT_LOG_LEVEL" unzip -l "$zip_file"


    local publish_dir
    publish_dir="$(realpath "$(dirname "$bundle_name")")"
    mkdir -p "$publish_dir"
    log_info "Copying virtual disk to $publish_dir"
    if ! cp -f "$zip_file" "$publish_dir"; then
        log_error "Failed to copy $zip_file to $publish_dir"
        print_qcow2_json "$failure_token" "$output_json"
        remove_dir "$temp_dir"
        return 1
    fi
    if ! cp -f "${zip_file}.md5" "$publish_dir"; then
        log_error "Failed to copy ${zip_file}.md5 to $publish_dir"
        print_qcow2_json "$failure_token" "$output_json"
        remove_dir "$temp_dir"
        return 1
    fi

    # cleanup and produce the stage output file
    remove_dir "$temp_dir"

    if jq -M -n \
            --arg description "Prepared QCOW2 package status" \
            --arg build_host "$HOSTNAME" \
            --arg build_source "$(basename "${BASH_SOURCE[0]}")" \
            --arg build_user "$USER" \
            --arg input "$raw_disk" \
            --arg output "$(basename "$bundle_name")" \
            --arg output_md5 "$(awk '{print $1;}' < "$bundle_name".md5)" \
            --arg status "$success_token" \
            '{ description: $description,
            build_host: $build_host,
            build_source: $build_source,
            build_user: $build_user,
            input: $input,
            output: $output,
            output_md5: $output_md5,
            status: $status }' \
            > "$output_json"
    then
        log_info "Wrote qcow2 generation status to '$output_json'."
    else
        log_error "Failed to write '$output_json'."
        return 1
    fi
}
