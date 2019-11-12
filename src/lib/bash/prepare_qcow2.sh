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
        return 1
    elif [[ ! -f "$artifacts_dir/$raw_disk" ]]; then
        log_error "Raw disk '$raw_disk' doesn't exist in '$artifacts_dir'."
        print_json "$failure_token" "$output_json" "qcow2 generation failed: no input raw disk" \
                   "$(basename "${BASH_SOURCE[0]}")"
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
        print_json "$failure_token" "$output_json" "qemu image conversion failed" \
                   "$(basename "${BASH_SOURCE[0]}")"
        remove_dir "$temp_dir"
        return 1
    fi

    log_info "Compressing QCOW2 -- starting."
    local start_task
    start_task=$(timer)

    # remove the old zip file
    if [[ -n "$bundle_name" ]] && [[ -f "$bundle_name" ]]; then
        rm -rf "$bundle_name"
    fi

    if ! execute_cmd zip -1 -j "$bundle_name" "$qcow2_disk_file" ; then
        log_error "Failed to compress '$qcow2_disk_file'."
        print_json "$failure_token" "$output_json"  "QCOW2 generation failed: could not zip" \
                   "$(basename "${BASH_SOURCE[0]}")"
        remove_dir "$temp_dir"
        return 1
    fi

    # Generate md5 sum for the zips.
    if ! gen_md5 "$bundle_name"; then
        log_error "MD5 generation for '$bundle_name' failed."
        print_json "$failure_token" "$output_json" "QCOW2 generation failed: cound not generate MD5" \
                   "$(basename "${BASH_SOURCE[0]}")"
        remove_dir "$temp_dir"
        return 1
    fi
    log_info "Compressing QCOW2 -- elapsed time: $(timer "$start_task")"

    sig_ext="$(get_sig_file_extension "$(get_config_value "IMAGE_SIG_ENCRYPTION_TYPE")")"
    sig_file="${bundle_name}${sig_ext}"

    sign_file "$bundle_name" "$sig_file"
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]]; then
        log_error "Error occured during signing the ${bundle_name}"
        remove_dir "$temp_dir"
        return 1
    fi

    # Check if signature file was generated, if not, then mark sig_file_path to
    # be empty indicating it was not generated
    if [[ ! -f "$sig_file" ]]; then
        sig_file=""
    fi

    log_debug "Contents of zip file '$bundle_name':"
    log_debug "--------------------------------------"
    log_cmd_output "$DEFAULT_LOG_LEVEL" unzip -l "$bundle_name"

    # cleanup and produce the stage output file
    remove_dir "$temp_dir"

    if jq -M -n \
            --arg description "Prepared QCOW2 package status" \
            --arg build_host "$HOSTNAME" \
            --arg build_source "$(basename "${BASH_SOURCE[0]}")" \
            --arg build_user "$USER" \
            --arg input "$raw_disk" \
            --arg output "$(basename "$bundle_name")" \
            --arg sig_file "$(basename "$sig_file")" \
            --arg output_partial_md5 "$(calculate_partial_md5 "$bundle_name")" \
            --arg output_size "$(get_file_size "$bundle_name")" \
            --arg status "$success_token" \
            '{ description: $description,
            build_host: $build_host,
            build_source: $build_source,
            build_user: $build_user,
            input: $input,
            output: $output,
            sig_file: $sig_file,
            output_partial_md5: $output_partial_md5,
            output_size: $output_size,
            status: $status }' \
            > "$output_json"
    then
        log_info "Wrote qcow2 generation status to '$output_json'."
    else
        log_error "Failed to write '$output_json'."
        return 1
    fi
}
