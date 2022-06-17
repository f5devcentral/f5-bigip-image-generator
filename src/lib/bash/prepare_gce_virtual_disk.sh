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
source "$(realpath "$(dirname "${BASH_SOURCE[0]}")")/common.sh"
# shellcheck source=src/lib/bash/util/config.sh
source "$(realpath "$(dirname "${BASH_SOURCE[0]}")")/util/config.sh"
# shellcheck source=src/lib/bash/util/logger.sh
source "$(realpath "$(dirname "${BASH_SOURCE[0]}")")/util/logger.sh"


# Initialize required variables.  This should be called automatically by functions which need them.  If the variables
# have already been initialized then this won't do anything.
function gce_init_vars {
    if [[ -n "$GCE_VARS_INITIALIZED" ]]; then
        return 0
    fi
    log_info "Initializing variables for GCE."
    GCE_VARS_INITIALIZED="true"
    log_info "SUCCESS - Finished initializing variables for GCE"
}

# Ensure that filepaths end with a slash unless they're empty
function gce_ensure_trailing_slash {
    local string="$1"
    if [[ -z "$string" ]]; then
        echo ""
    elif [[ "$string" != */ ]]; then
        echo "${string}/"
    else
        echo "$string"
    fi
}

# Package the provided raw disk file into a tar archive which can be used to create an image on gcloud.  raw_disk_name
# must equal "disk.raw".  artifacts_dir must be an absolute path to the directory containing the raw disk.
# bundle_name must be the name of the tar archive to generate.  prepare_vdisk_json must be a path to the json file used
# to record the status of this step.  log_file must be the name of the log_file used by the previous step.
function gce_disk_package {
    gce_init_vars
    local required_disk_name="disk.raw"
    if [[ $# -ne 5 ]]; then
        log_error "Must call ${FUNCNAME[0]} with [raw_disk_name, artifacts_dir, bundle_name, prepare_vdisk_json, \
log_file]!"
        return 1
    elif [[ -z "$1" ]] || [[ -z "$2" ]] || [[ -z "$3" ]] || [[ -z "$4" ]] || [[ -z "$5" ]]; then
        log_error "raw_disk_name, artifacts_dir, bundle_name, prepare_vdisk_json, and log_file must not be empty!"
        return 1
    elif [[ "$1" != "$required_disk_name" ]]; then
        log_error "raw_disk_name for GCE must be $required_disk_name!"
        return 1
    fi
    local raw_disk_name="$1"
    local artifacts_dir="$2"
    local bundle_name="$3"
    local prepare_vdisk_json="$4"
    local log_file="$5"

    # Check if the current execution is a re-run of previously successful execution.
    if check_previous_run_status "$prepare_vdisk_json" "$bundle_name" ; then
        log_info "Skipping gce disk generation as the output virtual disk '$bundle_name'" \
                "was generated successfully earlier."
        return 0
    fi

    # Compress the raw disk file into a tar archive.  Display the available disk space before and after the operation.
    artifacts_dir="$(gce_ensure_trailing_slash "$artifacts_dir")"
    local packaged_disk_dir
    packaged_disk_dir="$(realpath "$(dirname "$bundle_name")")"
    mkdir -p "$packaged_disk_dir"
    log_debug "Compressing raw GCE disk [${artifacts_dir}${raw_disk_name}] into archive [${bundle_name}]"
    if ! execute_cmd tar -C "$artifacts_dir" -vczf "$bundle_name" "$raw_disk_name" ; then
        log_error "$response"
        print_json "failure" "$prepare_vdisk_json" "GCE disk generation failed: during qemu img conversion" \
                   "$(basename "${BASH_SOURCE[0]}")"
        return 1
    fi

    # Save an md5sum alongside the packaged disk
    if ! gen_md5 "$bundle_name"; then
        return 1
    fi

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

    # Write required fields to JSON file which will be consumed by next step
    log_info "Writing required fields to [${prepare_vdisk_json}] for consumption by next step"
    response="$(jq -M -n \
            --arg description "Prepared Virtual disk status" \
            --arg build_host "$HOSTNAME" \
            --arg build_source "$(basename "${BASH_SOURCE[0]}")" \
            --arg build_user "$USER" \
            --arg platform "gce" \
            --arg input "$raw_disk_name" \
            --arg output "$(basename "$bundle_name")" \
            --arg sig_file "$(basename "$sig_file")" \
            --arg output_partial_md5 "$(calculate_partial_md5 "$bundle_name")" \
            --arg output_size "$(get_file_size "$bundle_name")" \
            --arg log_file "$log_file" \
            --arg status "success" \
            '{ description: $description,
            build_host: $build_host,
            build_source: $build_source,
            build_user: $build_user,
            platform: $platform,
            input: $input,
            output: $output,
            sig_file: $sig_file,
            output_partial_md5: $output_partial_md5,
	    output_size: $output_size,
            log_file: $log_file,
            status: $status }' > "$prepare_vdisk_json")"
    if [[ -z "$response" ]]; then
        log_info "SUCCESS - wrote required fields to [${prepare_vdisk_json}]"
    else
        log_error "$response"
        return 1
    fi
}
