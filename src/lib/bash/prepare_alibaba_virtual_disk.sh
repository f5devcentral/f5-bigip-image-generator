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
# shellcheck source=src/lib/bash/util/config.sh
source "$(realpath "$(dirname "${BASH_SOURCE[0]}")")/util/config.sh"
# shellcheck source=src/lib/bash/util/logger.sh
source "$(realpath "$(dirname "${BASH_SOURCE[0]}")")/util/logger.sh"

# Ensure that filepaths end with a slash unless they're empty
function alibaba_ensure_trailing_slash {
    local string="$1"
    if [[ -z "$string" ]]; then
        echo ""
    elif [[ "$string" != */ ]]; then
        echo "${string}/"
    else
        echo "$string"
    fi
}

# Package the provided raw disk file into a tar archive which can be used to create an image on alibaba.  raw_disk_name
# must equal ALIBABA_REQUIRED_DISK_NAME.  artifacts_dir must be an absolute path to the directory containing the raw disk.
# bundle_name must be the name of the tar archive to generate.  prepare_vdisk_json must be a path to the json file used
# to record the status of this step.
function alibaba_disk_package {
    local raw_disk_name="$1"
    local bundle_name="$2"
    local artifacts_dir="$3"
    local prepare_vdisk_json="$4"

    local success_token="success"
    local failure_token="failure"
    if [[ $# -ne 4 ]]; then
        log_error "Must call ${FUNCNAME[0]} with [raw_disk_name, artifacts_dir, bundle_name, prepare_vdisk_json]!"
        return 1
    elif [[ -z "$raw_disk_name" ]] || [[ -z "$bundle_name" ]] || [[ -z "$artifacts_dir" ]] \
         || [[ -z "$prepare_vdisk_json" ]]; then
        log_error "raw_disk_name, artifacts_dir, bundle_name and prepare_vdisk_json must not be empty!"
        return 1
    elif [[ ! -f "$artifacts_dir/$raw_disk_name" ]]; then
        log_error "Raw disk '$raw_disk_name' doesn't exist in '$artifacts_dir'."
        print_json "$failure_token" "$prepare_vdisk_json" "qcow2 generation failed: no input raw disk" \
                   "$(basename "${BASH_SOURCE[0]}")"
        return 1
    fi

    # Check if the current execution is a re-run of previously successful execution.
    if check_previous_run_status "$prepare_vdisk_json" "$bundle_name" ; then
        log_info "Skipping alibaba disk generation as the output virtual disk '$bundle_name'" \
                "was generated successfully earlier."
        return 0
    fi

    # Create a qcow2 from the provided raw disk.  Display the available disk space before and after the operation.
    artifacts_dir="$(alibaba_ensure_trailing_slash "$artifacts_dir")"
    local raw_disk_path="${artifacts_dir}${raw_disk_name}"
    local output_dir
    output_dir="$(realpath "$(dirname "$bundle_name")")"
    mkdir -p "$output_dir"

    # Derive the internal qcow2 disk name from the output bundle_name.
    local qcow2_name
    qcow2_name="$(basename "$bundle_name")"
    qcow2_name="${qcow2_name/%.tar.gz/.qcow2}"

    local temp_dir
    temp_dir=$(mktemp -d -p "$artifacts_dir")
    local qcow2_disk_path="$temp_dir/${qcow2_name}"

    log_info "Creating qcow2 [${qcow2_disk_path}] from raw disk at [${raw_disk_path}]"

    # Convert the raw disk to qcow2.
    if ! "$(realpath "$( dirname "${BASH_SOURCE[0]}" )")/../../bin/convert" \
            "qcow2" "$raw_disk_path" "$qcow2_disk_path" "" ; then
        log_error "Conversion of $raw_disk_name to qcow2 disk for alibaba failed."
        print_json "$failure_token" "$prepare_vdisk_json" "Alibaba disk generation failed: during qemu img conversion" \
                   "$(basename "${BASH_SOURCE[0]}")"
        remove_dir "$temp_dir"
        return 1
    fi

    # Compress the qcow2 into a tar archive.  Display the available disk space after the operation.
    log_info "Packaging Alibaba qcow2 [${qcow2_disk_path}] into archive [${bundle_name}]"
    pushd "$temp_dir" >/dev/null
    if ! execute_cmd tar -vczf "$bundle_name" "$qcow2_name" ; then
        log_error "Failed to compress - $qcow2_disk_path"
        print_json "$failure_token" "$prepare_vdisk_json"  "QCOW2 generation failed: could not zip" \
                   "$(basename "${BASH_SOURCE[0]}")"
        remove_dir "$temp_dir"

        return 1
    else
        log_info "SUCCESS - $response"
    fi
    popd >/dev/null

    # Save an md5sum alongside the packaged disk
    local md5_path="${bundle_name}.md5"
    log_info "Generating md5sum for [${bundle_name}] at [${md5_path}]"
    if md5sum "$bundle_name" > "$md5_path"; then
        log_info "SUCCESS - generated md5sum"
    else
        log_error "Unable to generate md5sum!"
        return 1
    fi

    # Now generate a signature based on user provided private key
    # and hashing algorithm
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

    remove_dir "$temp_dir"

    # Write required fields to JSON file which will be consumed by next step
    log_info "Writing required fields to [${prepare_vdisk_json}] for consumption by next step"
    response="$(jq -M -n \
            --arg description "Prepared Virtual disk status" \
            --arg build_host "$HOSTNAME" \
            --arg build_source "$(basename "${BASH_SOURCE[0]}")" \
            --arg build_user "$USER" \
            --arg platform "alibaba" \
            --arg input "$raw_disk_name" \
            --arg output "$(basename "$bundle_name")" \
            --arg sig_file "$(basename "$sig_file")" \
            --arg output_partial_md5 "$(calculate_partial_md5 "$bundle_name")" \
            --arg output_size "$(get_file_size "$bundle_name")" \
            --arg status "$success_token" \
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
            status: $status }' > "$prepare_vdisk_json")"
    if [[ -z "$response" ]]; then
        log_info "SUCCESS - wrote required fields to [${prepare_vdisk_json}]"
    else
        log_error "$response"
        return 1
    fi
}
