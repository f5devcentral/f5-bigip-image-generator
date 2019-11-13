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



# shellcheck source=src/lib/bash/util/config.sh
source "$(realpath "$(dirname "${BASH_SOURCE[0]}")")/util/config.sh"
# shellcheck source=src/lib/bash/util/logger.sh
source "$(realpath "$(dirname "${BASH_SOURCE[0]}")")/util/logger.sh"

#####################################################################
# If no arguments passed, print current time in seconds.
# Otherwise consider the first argument as the start time and print
# the elapsed time in <hours>:<minutes>:<seconds> format
# always return 0
#
function timer {
    if [[ "$#" -eq 0 ]]; then
        date '+%s'
        return 0
    fi

    local start_time="$1"
    local end_time
    end_time=$(date '+%s')

    local delta=$((end_time - start_time))
    local seconds=$((delta % 60))
    local minutes=$(((delta / 60) % 60))
    local hours=$((delta / 3600))
    printf '%d:%02d:%02d' "$hours" "$minutes" "$seconds"
}
#####################################################################


#####################################################################
# Checks if the current virtual disk format is for supported Cloud.
#
# PARAMETERS:
#   cloud_tag - the name of the disk format/cloud
#
# RETURN:
#       0 - the tag is supported cloud
#       1 - the tag is not supported cloud
#       2 - there was a problem determining the supported clouds
#
function is_supported_cloud {
    local cloud_tag="$1"
    local accepted
    if ! accepted="$(get_config_accepted "CLOUD")"; then
        return 2
    elif [[ "$cloud_tag" =~ $accepted ]]; then
        return 0
    else
        return 1
    fi
}
#####################################################################


#####################################################################
# Checks if the given platform is supported.
#
# PARAMETERS:
#   platform - given platform name
#
# RETURN:
#       0 - supported platform
#       1 - not supported platform
#       2 - there was a problem determining the supported platforms
#
function is_supported_platform {
    local platform="$1"
    local accepted
    if ! accepted="$(get_config_accepted "PLATFORM")"; then
        return 2
    elif [[ "$platform" =~ $accepted ]]; then
        return 0
    else
        return 1
    fi
}
#####################################################################


#####################################################################
# Checks if the given module is supported.
#
# PARAMETERS:
#   given module type
#
# RETURN:
#       0 - supported module
#       1 - not supported module
#       2 - there was a problem determining the supported modules
#
function is_supported_module {
    local module="$1"
    if ! accepted="$(get_config_accepted "MODULES")"; then
        return 2
    elif [[ "$module" =~ $accepted ]]; then
        return 0
    else
        return 1
    fi
}
#####################################################################


#####################################################################
# Checks if the given boot_location number is supported configuration.
#
# PARAMETERS:
#   boot_location count
#
# RETURN:
#       0 - supported platform
#       1 - not supported platform
#       2 - there was a problem determining the supported boot locations
#
function is_supported_boot_locations {
    local boot_locations="$1"
    if ! accepted="$(get_config_accepted "BOOT_LOCATIONS")"; then
        return 2
    elif [[ "$boot_locations" =~ $accepted ]]; then
        return 0
    else
        return 1
    fi
}
#####################################################################


#####################################################################
# Utility function that reads the given json file to check if the given "object"
# was successfully built in previous runs. Based on the result value, the caller
# decides if it can skip the re-execution (as it was built in past with identical
# output).
# For example, prepare_raw_disk can call this function with the prepare_raw_disk.json
# and the output disk to check if the given object was successfully built.
#
# The function re-calculates partial md5sum of the given "disk" and checks it against
# the output_partial_md5 (partial md5sum of "output") value, if one exists. In case of match, it
# returns success.
# For example, consider this json file:
# {
#  "description": "Prepared Virtual disk status",
#  "build_source": "prepare_ova.sh",
#  "platform": "aws",
#  "output": "BIGIP-15.0.0.LTM_1SLOT-aws.zip",
#  "output_partial_md5": "d41d2cd98f00b204e9700998ecf8427f",
#  "output_size": "2192284",
#  "status": "success"
#}
#
# PARAMETERS:
#   <json> <object_name>
#   where,
#       json:        Resultant JSON file.
#       object_name: Object whose status is being checked. (object_name in
#                    above example)
#
# RETURN:
#       0 for success, 1 otherwise.
#
function check_previous_run_status {
    local json="$1"
    local object_name="$2"

    if [[ $# != 2 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <json> <object_name>"
        return 1
    fi

    if [[ ! -f "$json" ]]; then
        log_info "Skipping checksum verification for earlier runs as json '$json' doesn't exist."
        return 1
    elif [[ ! -f "$object_name" ]]; then
        log_info "Skipping checksum verification for earlier runs as file '$object_name' doesn't exist."
        return 1
    fi

    declare -A info
    # Extract "status" object values from the json file.
    while IFS="=" read -r key value
    do
        # Skip nested objects.
        if [[ $value == \{* ]]; then
            continue
        fi
        info[$key]="$value"
    done < <(jq -r "to_entries|map(\"\(.key)=\(.value)\")|.[]" "$json")

    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]]; then
        log_info "Malformed json file '$json'."
        return 1
    fi

    # Check if the "object_name" in the json is same as the passed in object_name
    # and the "status" matches the passed-in status.
    if [[ "${info[output]}" == "$(basename "$object_name")" ]]; then
        if [[ "${info[status]}" == "success" ]] && [[ -n "${info[output_partial_md5]}" ]] && \
                [[ -n "${info[output_size]}" ]]; then
            local object_md5
            object_md5="$(calculate_partial_md5 "$object_name")"
            if [[ "${info[output_partial_md5]}" == "$object_md5" ]]; then
                local object_size
                object_size="$(get_file_size "$object_name")"
                if [[ "${info[output_size]}" == "$object_size" ]]; then
                    return 0
                else
                    log_info "Size of '$object_name' is not equal to the 'object_size' value from '$json': '$object_size' != '${info[output_size]}'."
                fi
            else
                log_info "Partial md5sum of '$object_name' does not match the 'output_partial_md5' value from '$json': '$object_md5' != '${info[output_partial_md5]}'."
            fi
        fi
    fi
    return 1
}

#####################################################################
# Utility function that returns the value of a provided key.
# Currently, this function works only for objects that are at top level
#
# PARAMETERS:
#   <json> <object_name>
#   where,
#       json:        Resultant JSON file.
#       object_name: Object whose value is being returned. (object_name in
#                    above example)
#
# RETURN:
#      The value of the key, empty string if the key is not found
#
function get_json_key_value {

    local json="$1"
    local object_name="$2"

    if [[ $# != 2 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <json> <object_name>"
        return 1
    fi

    if [[ ! -f "$json" ]]; then
        log_info "The json '$json' doesn't exist."
        return 1
    fi

    if [[ -z "$object_name" ]]; then
        log_info "No key was provided"
        return 0
    fi

    declare -A info
    # Extract "status" object values from the json file.
    while IFS="=" read -r key value
    do
        # Skip nested objects.
        if [[ $value == \{* ]]; then
            continue
        fi
        info[$key]="$value"
    done < <(jq -r "to_entries|map(\"\(.key)=\(.value)\")|.[]" "$json")

    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]]; then
        log_info "Malformed json file '$json'."
        return 1
    fi

    # Check if the "object_name" in the json is same as the passed in object_name
    if [[ -n "${info["$object_name"]}" ]]; then
       echo "${info["$object_name"]}"
    fi
    return 0
}


#####################################################################
# Prints the disk info for the given qemu img. qemu-img doesn't need the -f
# option to be passed but it incorrectly reports any given file as a "raw"
# disk if it can't understand the format of the file.
#
function print_qemu_disk_info {
    local image_file="$1"
    local format="$2"

    if [[ $# != 2 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <disk> <format>"
        return 1
    fi

    if [[ ! -f "$image_file" ]]; then
        log_error "<$image_file> doesn't exist."
        return 1
    fi

    log_debug "Image info for '$image_file':"
    log_debug "============================"

    log_cmd_output "$DEFAULT_LOG_LEVEL" qemu-img info -f "$format" "$image_file"
    return $?
}
#####################################################################


#####################################################################
# Check if input is number or not.
#
# RETURN:
#         err code 0 - input is a number
#         err code 1 - input IS NOT a number
#
function is_number {
    test "$1" && printf '%f' "$1" >/dev/null 2>/dev/null;
}
#####################################################################


#####################################################################
#
function vadc_hypervisor_name {
    local platform="$1"
    if [[ -z "$platform" ]]; then
        log_error "Usage: ${FUNCNAME[0]} <platform>"
        return 1
    fi

    # By default, there is no Cloud-specific actions:
    local cmi_type=0

    case $platform in
        alibaba)
            cmi_type=ALIBABA
            ;;

        aws)
            cmi_type=AWS
            ;;

        azure)
            cmi_type=Azure
            ;;

        gce)
            cmi_type=GCE
            ;;

        qcow2 | vhd | vhdx | vmware)
            # Nothing to do.
            ;;

        *)
            log_error "Invalid platform=$platform"
            return 1
    esac

    if [[ -n "$cmi_type" ]]; then
        cmi_type=$(echo "$cmi_type" | tr '[:upper:]' '[:lower:]')
    fi

    echo "$cmi_type"
}
#####################################################################


#####################################################################
# Generate MD5 sum for a given filepath in the same directory with the
# name file.md5
#
function gen_md5 {
    local file_name
    local file_path
    local out_dir
    file_path=$1

    if [[ $# != 1 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <file path>"
        return 1
    fi

    if [[ ! -f "$file_path" ]]; then
        log_error "$file_path is not a file."
        return 1
    fi

    # Extract directory and file name from file path
    out_dir="$(dirname "$file_path")"
    file_name="$(basename "$file_path")"

    if [[ -z "$out_dir" ]]; then
        log_error "Missing or empty argument 'out_dir' provided."
        return 1
    fi

    if [[ -z "$file_name" ]]; then
        log_error "No file provided."
        return 1
    fi

    if [[ ! -d "$out_dir" ]]; then
        log_error "'$out_dir' is not a directory"
        return 1
    fi

    log_info "Generating ${file_path}.md5"

    # Temporary change to the output directory and generate MD5 there:
    pushd "$out_dir" >/dev/null
    md5sum "$file_name" > "${file_name}".md5
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]]; then
        log_error "Generating MD5 for $file_path failed."
        popd >/dev/null
        return 1
    fi
    popd >/dev/null
}
#####################################################################


#####################################################################
# Calculate and return MD5 sum for a fixed (small) portion of the file.
# This is faster than checking the whole file and
# should be enough for internal verifications.
#
function calculate_partial_md5 {
    local file_path
    file_path=$1

    if [[ $# != 1 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <file path>"
        return 1
    fi

    if [[ ! -f "$file_path" ]]; then
        log_error "$file_path is not a file."
        return 1
    fi

    dd count=1024 if="$file_path" 2>/dev/null | md5sum | awk '{print $1;}'
}
#####################################################################


#####################################################################
# Get file size (in bytes)
#
function get_file_size {
    local file_path
    file_path=$1

    if [[ $# != 1 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <file path>"
        return 1
    fi

    if [[ ! -f "$file_path" ]]; then
        log_error "$file_path is not a file."
        return 1
    fi

    du "$file_path" | awk '{print $1;}'
}
#####################################################################


#####################################################################
# Print how much free disk space we have on build server.
#
function print_disk_free_space() {
    log_debug "Free disk space:"
    log_cmd_output "$DEFAULT_LOG_LEVEL" df -h .
}
#####################################################################


#####################################################################
# Remove a directory if it exists
function remove_dir {
    local rm_dir="$1"

    if [[ -n "$rm_dir" ]] && [[ -d "$rm_dir" ]]; then
        rm -fr "$rm_dir"
    fi
}
#####################################################################


#####################################################################
# Shows a progress-bar "..." on the console while waiting for the underlying command
# execution (that forked this process) to complete. The function execution completes
# in one of two ways:
#   1) The marker_file that the process waits-on is removed by the caller process
#      thus signaling this process to gracefully exit.
#   2) Killed by the shell when the parent process dies unexpectedly.
#
function waiter {
    local marker_file="$1"

    if [[ -z "$marker_file" ]]; then
        log_error "Usage: ${FUNCNAME[0]} <marker_file>"
        return 1
    fi

    local duration
    duration="$(get_config_value "CONSOLE_PROGRESS_BAR_UPDATE_DELAY")"

    if [[ -z "$duration" ]] ; then
        log_error "Undefined CONSOLE_PROGRESS_BAR_UPDATE_DELAY."
        return 1
    elif ! is_number "$duration" ; then
        log_error "Unexpected sleep duration value '$duration'."
        return 1
    fi

    while [[ -f "$marker_file" ]]; do
        echo -n "."
        sleep "$duration"
    done
    log_trace "Exiting waiter process."
}
#####################################################################


#####################################################################
# Executes the given command (as argument) and prints its output to the LOG_FILE_NAME if
# one is set and the LOG_LEVEL <= $DEFAULT_LOG_LEVEL. It also forks a child process that shows a
# simple progress bar on the console to ensure the console doesn't look frozen.
# When the underlying command has completed its execution, it signals the child process
# by removing the marker file that the child process loops on.
# 
# Returns the return-value of the executed command.
#
function execute_cmd {
    local ret_val
    local log_file
    local marker_file
    local waiter_pid

    if is_msg_level_high "$DEFAULT_LOG_LEVEL" && [[ -n "$LOG_FILE_NAME" ]]; then
        log_file="$LOG_FILE_NAME"
    else
        log_file="/dev/null"
    fi

    marker_file="$(mktemp -p "$(get_config_value "ARTIFACTS_DIR")" tmp.XXXXXX)"

    log_info "Executing:" "$@"
    waiter "$marker_file" &
    waiter_pid="$!"
    log_trace "Created child waiter process:$waiter_pid"

    "$@" >> "$log_file"
    ret_val=$?

    rm -f "$marker_file"
    # Wait for the child process to exit. It should happen within 5 seconds as the
    # signaling marker file has been already removed.
    wait $waiter_pid

    # Add a new-line to pretty up the progress-bar.
    echo ""
    return $ret_val 
}
#####################################################################


#####################################################################
# write a status into a json file
#
function print_json {
    local status="$1"
    local output_json="$2"
    local desc="$3"
    local source_file="$4"

    if [[ $# != 4 ]] || [[ -z "$status" ]] || [[ -z "$output_json" ]] || [[ -z "$desc" ]] \
       || [[ -z "$source_file" ]]; then
        log_error "Usage: ${FUNCNAME[0]} <status> <output_json> <desc> <source_file>"
        return 1
    fi

    if jq -M -n \
            --arg description "$desc" \
            --arg build_host "$HOSTNAME" \
            --arg build_source "$(basename "$source_file")" \
            --arg build_user "$USER" \
            --arg status "$status" \
            '{ description: $description,
            build_host: $build_host,
            build_source: $build_source,
            build_user: $build_user,
            status: $status }' \
            > "$output_json"
    then
        log_info "Wrote output to '$output_json'."
    else
        log_error "Failed to write '$output_json'."
        return 1
    fi
}

#####################################################################
# Sign a virtual disk file using openssl with -sha384 encryption type
#
function sign_file {
    local src_disk="$1"
    local out_sig_file="$2"

    if [[ $# != 2 ]] || [[ -z "$src_disk" ]] || [[ -z "$out_sig_file" ]]; then
        log_error "Usage: ${FUNCNAME[0]} <src_disk> <out_sig_file>"
        return 1
    fi

    local private_key
    private_key="$(get_config_value "IMAGE_SIG_PRIVATE_KEY")"
    local encryption_type
    encryption_type="$(get_config_value "IMAGE_SIG_ENCRYPTION_TYPE")"

    # Remove previously generated sig_file
    if [[ -f "$out_sig_file" ]]; then
        rm -f "$out_sig_file"
    fi

    if [[ ! -z "$private_key" ]] && [[ ! -f "$private_key" ]]; then
       log_error "The provided private key file path does not exist"
       return 1
    fi

    if [[ -z "$encryption_type" ]]; then
       log_error "No hashing scheme was provided"
       return 1
    fi

    if [[ ! -z "$private_key" ]]; then
        log_info "Signing ${src_disk} using encryption type ${encryption_type} with private key ${private_key}"
        if openssl dgst -"$encryption_type" -sign "$private_key" "$src_disk" > "$out_sig_file"; then
            log_info "$out_sig_file was generated"
        else
            log_error "Unable to sign ${src_disk} using private key ${private_key}!"
            rm "$out_sig_file"
        fi
    else
        log_warning "No signing keys were provided.  Skipping Virtual Disk signing process!"
        log_warning "Please provide IMAGE_SIG_PRIVATE_KEY and IMAGE_SIG_PUBLIC_KEY if " \
                    "you wish to sign the virtual disk files!"
    fi
}

#####################################################################
# Get the signature file extension. It is generated by extracting
# the numeric part from the hashing algorithm (i.e. sha384 or sha3-512)
# i.e. input = "sha3-512" output = .3512.sig
function get_sig_file_extension {
    local hashing_type="$1"
    local file_ext=""
    if [[ -z "$hashing_type" ]]; then
        file_ext="$(get_config_value "DEFAULT_SIG_FILE_EXTENSION")"
    else
        file_ext=."${hashing_type//[!0-9]/}"".sig"
    fi
    echo "$file_ext"
}
