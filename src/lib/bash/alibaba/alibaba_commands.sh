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
source "$(realpath "$(dirname "${BASH_SOURCE[0]}")")/../common.sh"
# shellcheck source=src/lib/bash/util/config.sh
source "$(realpath "$(dirname "${BASH_SOURCE[0]}")")/../util/config.sh"
# shellcheck source=src/lib/bash/util/logger.sh
source "$(realpath "$(dirname "${BASH_SOURCE[0]}")")/../util/logger.sh"

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
# to record the status of this step.  log_file must be the name of the log_file used by the previous step.
function alibaba_disk_package {
    if [[ $# -ne 5 ]]; then
        log_error "Must call ${FUNCNAME[0]} with [raw_disk_name, artifacts_dir, bundle_name, prepare_vdisk_json, \
log_file]!"
        return 1
    elif [[ -z "$1" ]] || [[ -z "$2" ]] || [[ -z "$3" ]] || [[ -z "$4" ]] || [[ -z "$5" ]]; then
        log_error "raw_disk_name, artifacts_dir, bundle_name, prepare_vdisk_json, and log_file must not be empty!"
        return 1
    fi
    local raw_disk_name="$1"
    local artifacts_dir="$2"
    local bundle_name="$3"
    local prepare_vdisk_json="$4"
    local log_file="$5"
    local script_dir
    script_dir="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"

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
    local qcow2_path="${artifacts_dir}${qcow2_name}"
    local free_disk_space
    free_disk_space="$(df -h . --output=avail | grep -Po '\d+.*$' 2>&1)"
    log_info "Free disk space before creating Alibaba qcow2: [${free_disk_space}]"
    log_info "Creating qcow2 [${qcow2_path}] from raw disk at [${raw_disk_path}]"
    local qcow2_options
    qcow2_options="$(get_config_value "ALIBABA_QCOW2_OPTIONS")"
    local response
    if response="$(qemu-img convert -p -O "qcow2" -o "$qcow2_options" "$raw_disk_path" "$qcow2_path")"; then
        log_info "SUCCESS"
    else
        log_error "$response"
        return 1
    fi
    free_disk_space="$(df -h . --output=avail | grep -Po '\d+.*$' 2>&1)"
    log_debug "Free disk space after creating Alibaba qcow2: [${free_disk_space}]"

    # Compress the qcow2 into a tar archive.  Display the available disk space after the operation.
    log_info "Packaging Alibaba qcow2 [${qcow2_path}] into archive [${bundle_name}]"
    if response="$(tar -C "$artifacts_dir" -vczf "$bundle_name" "$qcow2_name")"; then
        log_info "SUCCESS - $response"
    else
        log_error "$response"
        return 1
    fi
    free_disk_space="$(df -h . --output=avail | grep -Po '\d+.*$' 2>&1)"
    log_debug "Free disk space after packaging Alibaba disk: [${free_disk_space}]"

    # Save an md5sum alongside the packaged disk
    local md5_path="${bundle_name}.md5"
    log_info "Generating md5sum for [${bundle_name}] at [${md5_path}]"
    if md5sum "$bundle_name" > "$md5_path"; then
        log_info "SUCCESS - generated md5sum"
    else
        log_error "Unable to generate md5sum!"
        return 1
    fi

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
            --arg output_md5 "$(awk '{print $1;}' < "$md5_path")" \
            --arg log_file "$log_file" \
            --arg status "success" \
            '{ description: $description,
            build_host: $build_host,
            build_source: $build_source,
            build_user: $build_user,
            platform: $platform,
            input: $input,
            output: $output,
            output_md5: $output_md5,
            log_file: $log_file,
            status: $status }' > "$prepare_vdisk_json")"
    if [[ -z "$response" ]]; then
        log_info "SUCCESS - wrote required fields to [${prepare_vdisk_json}]"
    else
        log_error "$response"
        return 1
    fi
}
