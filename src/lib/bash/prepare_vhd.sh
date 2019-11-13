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
source "$( dirname "${BASH_SOURCE[0]}" )/common.sh"
# shellcheck source=src/lib/bash/util/logger.sh
source "$(realpath "$(dirname "${BASH_SOURCE[0]}")")/util/logger.sh"

#####################################################################
function prepare_vhd { 
    local platform="$1"
    local raw_disk="$2"
    local artifacts_dir="$3"
    local general_bundle_name="$4"
    local bundle_name="$5"
    local output_json="$6"
    local log_file="$7"

    if [[ $# != 7 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <platform> <raw_disk> <artifacts_dir>" \
                 "<bundle_name> <output_json> <log_file>"
        return 1
    elif [[ -z "$1" ]] || [[ -z "$2" ]] || [[ -z "$3" ]] || [[ -z "$4" ]] || \
            [[ -z "$5" ]] || [[ -z "$6" ]] || [[ -z "$7" ]]; then
        log_error "platform, raw_disk, artifacts_dir, general_bundle_name, bundle_name," \
                "output_json, and log_file must not be empty!"
        return 1
    fi

    # Check if the current execution is a re-run of previously successful execution.
    if check_previous_run_status "$output_json" "$bundle_name" ; then
        log_info "Skipping ${FUNCNAME[0]} as the virtual disk '$bundle_name' was already generated successfully."
        return 0
    fi

    local temp_dir=""
    temp_dir=$(mktemp -d -p "$artifacts_dir")

    local virtual_disk_name="$temp_dir/$general_bundle_name.vhd"
 
    if [[ "$platform" == "azure" ]]; then
        # Azure requires FIXED/STATIC VHDs:
        local vhd_options="subformat=fixed,force_size"
    fi

    # Convert raw disk to vhd format
    "$( dirname "${BASH_SOURCE[0]}" )"/../../bin/convert vpc "$artifacts_dir/$raw_disk" \
            "$virtual_disk_name" "$vhd_options"

    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]] ; then
        log_error "Raw disk conversion from raw to vhd failed."
        remove_dir "$temp_dir"
        return 1
    fi

    print_disk_free_space
    log_debug "VHD Size: $(du -sh "$virtual_disk_name")"

    log_info "Compressing $virtual_disk_name -- start time: $(date +%T)"
    start_task=$(timer)
    if [[ "$platform" != "azure" ]]; then
        execute_cmd rm -f "$bundle_name"
        execute_cmd zip -1 -j "$bundle_name" "$virtual_disk_name"
    else
        execute_cmd tar -Sczvf "$bundle_name" -C "$temp_dir" "$(basename "$virtual_disk_name")"
    fi
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]] ; then
        log_error "Archive creation failed."
	    remove_dir "temp_dir"
        return 1
    fi

    log_info "Compressing $virtual_disk_name -- elapsed time: $(timer "$start_task")"

    # Generate md5
    gen_md5 "$bundle_name"

    sig_ext="$(get_sig_file_extension "$(get_config_value "IMAGE_SIG_ENCRYPTION_TYPE")")"
    sig_file="${bundle_name}${sig_ext}"

    sign_file "$bundle_name" "$sig_file"
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]]; then
        log_error "Error occured during signing the ${bundle_name}"
        return 1
    fi

    # Check if signature file was generated, if not, then mark sig_file_path to
    # be empty indicating it was not generated
    if [[ ! -f "$sig_file" ]]; then
        sig_file=""
    fi

    print_disk_free_space

    log_debug "Content of $bundle_name:"
    if [[ "$platform" != "azure" ]]; then
        unzip -l "$bundle_name"
    else
        tar -tzvf "$bundle_name"
    fi

    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]] ; then
        log_error "Listing $bundle_name contents failed."
    	remove_dir "$temp_dir"
        return 1
    fi

    local status="success"
    # Generate the output_json.
    if jq -M -n \
            --arg description "Prepared VHD package status" \
            --arg build_host "$HOSTNAME" \
            --arg build_source "$(basename "${BASH_SOURCE[0]}")" \
            --arg build_user "$USER" \
            --arg platform "$platform" \
            --arg input "$raw_disk" \
            --arg virtual_disk_name "$(basename "$virtual_disk_name")" \
            --arg output "$(basename "$bundle_name")" \
            --arg sig_file "$(basename "$sig_file")" \
            --arg output_partial_md5 "$(calculate_partial_md5 "$bundle_name")" \
            --arg output_size "$(get_file_size "$bundle_name")" \
            --arg log_file "$log_file" \
            --arg status "$status" \
            '{ description: $description,
            build_host: $build_host,
            build_source: $build_source,
            build_user: $build_user,
            platform: $platform,
            input: $input,
            virtual_disk_name: $virtual_disk_name,
            output: $output,
            sig_file: $sig_file,
            output_partial_md5: $output_partial_md5,
            output_size: $output_size,
            log_file: $log_file,
            status: $status }' \
            > "$output_json"
    then
        log_info "Wrote vhd generation status to '$output_json'."
    else
        log_error "Failed to write '$output_json'."
    fi

    remove_dir "$temp_dir"
}
#####################################################################

# Main program starts here.
#
prepare_vhd "$@"

