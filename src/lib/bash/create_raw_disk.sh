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


#####################################################################
# Checks if the given disk size for the given boot-location/module combination
# is within the expected range of size.
#
# PARAMETERS:
#       module:     Module type (ex. LTM, ALL)
#       boot_loc:   Boot location count (1 or 2)
#       disk_size:  Disk size for the given combination.
#
# RETURN:
#       0 - for success.
#       1 - If the disk size is out of bound.
#
function test_disk_size_correctness {
    local module="$1"
    local boot_loc=$2
    local disk_size=$3

    if [[ $# != 3 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <module> <boot_location> <disk_size>"
        return 1
    fi

    # <module+boot_loc> map containing minimum and maximum size range.
    declare -A module_size_range=( \
        ["ltm1"]="7 20"
        ["ltm2"]="32 42"
        ["all1"]="47 65"
        ["all2"]="70 90"
    )

    local size_key
    size_key="$module$boot_loc"

    if [[ -n "${module_size_range[$size_key]}" ]]; then
        local min max
        IFS=" " read -r min max <<< "${module_size_range[$size_key]}"

        if [[ $disk_size -ge $min ]] &&
            [[ $disk_size -le $max ]]; then
            return 0
        else
            log_error "Disk size <$disk_size>GB is not within the <$min - $max>GB" \
                    "range for $module-$boot_loc combination."
        fi
    fi
    return 1
}
#####################################################################


#####################################################################
# Reads various disk partition sizes from the given json file into an associative
# array and returns the array as a string.
# PARAMETERS:
#   json_file - ve.info.json file.
#
# RETURNS:
#   Returns the aossicative array in the following format as a string on stdout:
#       - "key1=value1 key2=value2"
#       - A non zero return value for the failing execution.
#
function init_tmos_ve_info() {
    local file="$1"

    if [[ ! -r "$file" ]]; then
        log_error "$file is not a file or can't be read to initialize TMOS VE info."
        return 1
    fi

    declare -A tmos_ve_info
    local key value
    # Extract the basic key value pairs
    while IFS="=" read -r key value
    do
        # Skip nested objects - processed later
        if [[ $value == \{* ]]; then
            continue
        fi
        tmos_ve_info[$key]="$value"

        # This loops through the tmos object skipping nested objects:
        #  "tmos": {
        #    // $tmos_ve_info[default_datastor_size_MiB]
        #    "default_datastor_size_MiB": 20000,
        #    "default_volume_size_MiB": {
        #        ...
        #    },
        #    "disk": {
        #       ...
        #    },
        #    // $tmos_ve_info[included_in_bigip_ve]
        #    "included_in_bigip_ve": "yes",
        #    // $tmos_ve_info[included_in_bigiq_ve]
        #    "included_in_bigiq_ve": "yes",
        #    "memory": {
        #       ...
        #    },
        #    // $tmos_ve_info[micro_datastor_size_MiB]
        #    "micro_datastor_size_MiB": 30,
        #    "micro_volume_size_MiB": {
        #       ...
        #    },
        #    // $tmos_ve_info[mos_size_MiB]
        #    "mos_size_MiB": 300,
        #    // $tmos_ve_info[mysql_space_MiB]
        #    "mysql_space_MiB": 12288,
        #    // $tmos_ve_info[uses_monpd_disk]
        #    "uses_monpd_disk": "no",
        #    // $tmos_ve_info[uses_mysql_disk]
        #    "uses_mysql_disk": "no"
        #  },
    done < <(jq -r ".tmos|to_entries|map(\"\(.key)=\(.value)\")|.[]" "$file")

    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]]; then
        log_error "Error processing $file for TMOS data"
        return 1
    fi

    # Extract default_volume_size_MiB values
    while IFS="=" read -r key value
    do
        local volume_key="default_volume_size_MiB_$key"
        tmos_ve_info[$volume_key]="$value"

        # This loops through the nested default_volume_size_MiB object in the
        # tmos object:
        #  "tmos": {
        #    ...
        #    "default_volume_size_MiB": {
        #        // $tmos_ve_info[default_volume_size_MiB_appdata]
        #        "appdata": 24238,
        #        // $tmos_ve_info[default_volume_size_MiB_boot]
        #        "boot": 200,
        #        // $tmos_ve_info[default_volume_size_MiB_config]
        #        "config": 3243,
        #        // $tmos_ve_info[default_volume_size_MiB_log]
        #        "log": 3000,
        #        // $tmos_ve_info[default_volume_size_MiB_root]
        #        "root": 440,
        #        // $tmos_ve_info[default_volume_size_MiB_shared]
        #        "shared": 20480,
        #        // $tmos_ve_info[default_volume_size_MiB_swap]
        #        "swap": 1000,
        #        // $tmos_ve_info[default_volume_size_MiB_usr]
        #        "usr": 4102,
        #        // $tmos_ve_info[default_volume_size_MiB_var]
        #        "var": 3072,
        #        // $tmos_ve_info[default_volume_size_MiB_waagent]
        #        "waagent": 1024
        #    },
        #    ...
        #  },
    done < <(jq -r ".tmos.default_volume_size_MiB|to_entries|map(\"\(.key)=\(.value)\")|.[]" "$file")

    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]]; then
        log_error "Error processing $file for default VE volume data"
        return 1
    fi
    # all_1slot_volume_size_MiB element was introduced from 14.1.0 onwards.
    if [[ -n "$BIGIP_VERSION_NUMBER" ]] && [[ "$BIGIP_VERSION_NUMBER" -ge 14010000 ]]; then
        # Extract all_1slot_volume_size_MiB values
        while IFS="=" read -r key value
        do
            local volume_key="all_1slot_volume_size_MiB_$key"
            tmos_ve_info[$volume_key]="$value"
        done < <(jq -r ".tmos.all_1slot_volume_size_MiB|to_entries|map(\"\(.key)=\(.value)\")|.[]" "$file")

        # shellcheck disable=SC2181
        if [[ $? -ne 0 ]]; then
            log_error "Error processing $file for ALL 1SLOT VE volume data"
            return 1
        fi
    fi

    # Extract micro_volume_size_MiB values
    while IFS="=" read -r key value
    do
        local volume_key="micro_volume_size_MiB_$key"
        tmos_ve_info[$volume_key]="$value"

        # This loops through the nested micro_volume_size_MiB object in the
        # tmos object:
        #  "tmos": {
        #    ...
        #    "micro_volume_size_MiB": {
        #        // $tmos_ve_info[micro_volume_size_MiB_appdata]
        #        "appdata": 30,
        #        // $tmos_ve_info[micro_volume_size_MiB_boot]
        #        "boot": 200,
        #        // $tmos_ve_info[micro_volume_size_MiB_config]
        #        "config": 489,
        #        // $tmos_ve_info[micro_volume_size_MiB_log]
        #        "log": 500,
        #        // $tmos_ve_info[micro_volume_size_MiB_root]
        #        "root": 440,
        #        // $tmos_ve_info[micro_volume_size_MiB_shared]
        #        "shared": 500,
        #        // $tmos_ve_info[micro_volume_size_MiB_swap]
        #        "swap": 1000,
        #        // $tmos_ve_info[micro_volume_size_MiB_usr]
        #        "usr": 4102,
        #        // $tmos_ve_info[micro_volume_size_MiB_var]
        #        "var": 950,
        #        // $tmos_ve_info[micro_volume_size_MiB_waagent]
        #        "waagent": 1024
        #    },
        #    ...
        #  },
    done < <(jq -r ".tmos.micro_volume_size_MiB|to_entries|map(\"\(.key)=\(.value)\")|.[]" "$file")

    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]]; then
        log_error "Error processing $file for micro VE volume data"
        return 1
    fi

    local output_string
    local entry
    for entry in "${!tmos_ve_info[@]}"
    do
	# Add a space if not the first time in the loop.
        if [[ -n "$output_string" ]]; then
            output_string+=" "
        fi
        output_string+="${entry}=${tmos_ve_info[$entry]}"
    done
    echo "$output_string"
}
#####################################################################


#####################################################################
# Verifies if the given space separated "key=value" pairs contains all partitions
# that calculate_bigip_hdd_sizes() requires to successfully calculate the disk size.
#
# PARAMETERS:
#   string - Space separated "key=value" pairs.
#
# RETURNS:
#   0 - If all keys are present.
#   1 - In case of failure. 
#
function verify_tmos_ve_info {
    local tmos_str="$1"

    # List of values required by calculate_bigip_hdd_sizes for correct calculation of
    # image size.
    declare -a required_keys=( \
        "default_volume_size_MiB_appdata" \
        "default_volume_size_MiB_boot" \
        "default_volume_size_MiB_config" \
        "default_volume_size_MiB_log" \
        "default_volume_size_MiB_root" \
        "default_volume_size_MiB_shared" \
        "default_volume_size_MiB_swap" \
        "default_volume_size_MiB_usr" \
        "default_volume_size_MiB_var" \
        "default_volume_size_MiB_waagent" \
        "micro_volume_size_MiB_appdata" \
        "micro_volume_size_MiB_config" \
        "micro_volume_size_MiB_log" \
        "micro_volume_size_MiB_root" \
        "micro_volume_size_MiB_shared" \
        "micro_volume_size_MiB_usr" \
        "micro_volume_size_MiB_var" \
        "mos_size_MiB" \
    )

    # all_1slot_volume_size_MiB element was introduced from 14.1.0 onwards.
    if [[ -n "$BIGIP_VERSION_NUMBER" ]] && [[ "$BIGIP_VERSION_NUMBER" -ge 14010000 ]]; then
        required_keys=("${required_keys[@]}" "all_1slot_volume_size_MiB_appdata")
    fi

    # Check if all the required keys are present in the tmos_ve_info map.
    for my_key in "${required_keys[@]}"; do
        if [[ "$tmos_str" != *"$my_key="* ]]; then
            log_error "$my_key is missing from tmos_ve_info."
            return 1
        fi
    done
    return 0
}
#####################################################################


#####################################################################
# Calculate the bare bone disk size for BIG-IP VE.
#
function calculate_bigip_hdd_sizes() {
    # Number of supported installation slots (1 or 2).
    local ve_info_json=$1
    local n=$2
    local ve_sizing_type=$3
    local ve_disk_format=$4

    if [[ $# -ne 4 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <ve.info.json path> <Number of Slots>" \
                "<Sizing Type> <Disk Format>"
        return 1
    fi

    local tmos_sizes_str
    if ! tmos_sizes_str="$(init_tmos_ve_info "$ve_info_json")"; then
        log_error "init_tmos_ve_info failed to load $ve_info_json."
        return 1
    fi

    # Verify if the required tmos_ve_info is correctly initialized.
    if ! verify_tmos_ve_info "$tmos_sizes_str"; then
        log_error "verify_tmos_ve_info failed for tmos_sizes_str = '$tmos_sizes_str'."
        return 1
    fi

    declare -A tmos_ve_info
    local tmos_key
    local tmos_value
    # Parse the string and convert it into a map.
    while read -r tmos_key tmos_value; do
        # The loop runs one extra time when it reaches the end of the string and
        # returns empty tmos_key and tmos_value. Account for that here.
        if [[ -n "$tmos_key" ]] && [[ -n "$tmos_value" ]]; then
            tmos_ve_info["$tmos_key"]="$tmos_value"
        fi
    done < <(<<<"$tmos_sizes_str" awk -F'=' '{print $1,$2}' RS=' ')


    # Various volume sizes are as follows:
    #   - A boot partition (TMI_VOLUME_FIX_BOOT_MIB) of 200 MB.
    #   - A swap LVM volume (TMI_VOLUME_FIX_SWAPVOL_MIB) with size:
    #       - 1000 MB - default for appliance (note that it can potentially be
    #                   extended later)
    #   - Each installation slot size (tmos_mib) is around 4250 MB. (As per
    #     fsinfo.xml for tiny plan).
    #   - Each installation needs a shared log space (TMI_VOLUME_FIX_LOG_MIB) of
    #     500 MB. It's used for log files shared between 2 install slots.
    #
    # According to fsinfo.xml, we need below disk space for tiny plan:
    #   - "/config" directory (volume_config_mib)  - it's used for LTM config files.
    #   - "/var" directory (volume_var_mib) - it's used for log files.
    #   - "/shared" directory (TMI_VOLUME_FIX_SHARE_MIB) must accomodate these:
    #       - (n-1) full ISO images + (n-1) hotfix ISO images +
    #         1 full core file + n compressed core files + temp files
    #
    # Also need space for n full core files because TMM in each slot can generate
    # a core file and it can have n different copies from each installation slot.
    # The reason to account for just 1 full core is because it gets compressed after
    # initial creation.
    #
    # Also, Maintanence OS (MOS) is installed in order to manage BIGIP in offline
    # mode. It's a small Linux distro with size (maint_mib) of 300 MB.
    #
    TMI_VOLUME_FIX_BOOT_MIB=${tmos_ve_info[default_volume_size_MiB_boot]}
    # Swap in a partition is not used by VE. VE uses swap in a logical volume.
    # The installer currently has no facility for just skipping creation of a
    # swap partition, but we can make it very small to save space.
    TMI_VOLUME_FIX_SWAP_MIB=10
    # For sizing type all use the default volume sizes
    # The real size for "swap" volume, which will be created in LVM VG:
    TMI_VOLUME_FIX_SWAPVOL_MIB=${tmos_ve_info[default_volume_size_MiB_swap]}
    TMI_VOLUME_FIX_APPDATA_MIB=${tmos_ve_info[default_volume_size_MiB_appdata]}
    TMI_VOLUME_FIX_LOG_MIB=${tmos_ve_info[default_volume_size_MiB_log]}

    local volume_root_mib
    local volume_usr_mib
    local volume_var_mib
    local volume_config_mib
    # Log space is accounted separately:
    if [[ "$ve_sizing_type" == "ltm" ]]; then
        volume_root_mib=${tmos_ve_info[micro_volume_size_MiB_root]}
        volume_usr_mib=${tmos_ve_info[micro_volume_size_MiB_usr]}
        volume_config_mib=${tmos_ve_info[micro_volume_size_MiB_config]}
        volume_var_mib=${tmos_ve_info[micro_volume_size_MiB_var]}
        if [[ $n == 1 ]]; then
            # For ltm 1 boot location:
            TMI_VOLUME_FIX_LOG_MIB=${tmos_ve_info[micro_volume_size_MiB_log]}
            # Set a micro appdata volume, which can be grown
            TMI_VOLUME_FIX_APPDATA_MIB=${tmos_ve_info[micro_volume_size_MiB_appdata]}
        else
            # 1000M for 2 Slot image.
            TMI_VOLUME_FIX_LOG_MIB=1000
            # Set a micro appdata volume, which can be grown
            TMI_VOLUME_FIX_APPDATA_MIB=${tmos_ve_info[micro_volume_size_MiB_appdata]}
        fi
    else
        volume_root_mib=${tmos_ve_info[default_volume_size_MiB_root]}
        volume_usr_mib=${tmos_ve_info[default_volume_size_MiB_usr]}
        volume_config_mib=${tmos_ve_info[default_volume_size_MiB_config]}
        volume_var_mib=${tmos_ve_info[default_volume_size_MiB_var]}
        if [[ $n == 1 ]]; then
            # all_1slot_volume_size_MiB element was introduced from 14.1.0 onwards.
            if [[ -n "$BIGIP_VERSION_NUMBER" ]] && [[ "$BIGIP_VERSION_NUMBER" -ge 14010000 ]]; then
                TMI_VOLUME_FIX_APPDATA_MIB=${tmos_ve_info[all_1slot_volume_size_MiB_appdata]}
            fi
        fi
    fi
    local tmos_mib=$(( volume_root_mib + volume_usr_mib + volume_config_mib + volume_var_mib ))
    # Space for modules that are common across all slots (i.e. not accounted per slot)
    local maint_mib=${tmos_ve_info[mos_size_MiB]}
    # waagent - special-case - it's needed only on Azure deployments as
    # we need extra volume per each installation slot.
    if [[ "$ve_disk_format" == "azure" ]]; then
        local waagent_volume_mib=${tmos_ve_info[default_volume_size_MiB_waagent]}
        local tmos_mib_old=$tmos_mib
        tmos_mib=$(( tmos_mib + waagent_volume_mib ))
        log_info "Increase tmos_mib from $tmos_mib_old to $tmos_mib" \
                "due to waagent_volume_mib=$waagent_volume_mib for Azure."
    fi

    TMI_VOLUME_FIX_SHARE_MIB=${tmos_ve_info[default_volume_size_MiB_shared]}

    if [[ "$ve_sizing_type" == "ltm" ]] && [[ $n == 1 ]]; then
        TMI_VOLUME_FIX_SHARE_MIB=${tmos_ve_info[micro_volume_size_MiB_shared]}
    fi

    # Thus, the bare minimum of HDD space:
    BIGIP_HDD_GB=$(( TMI_VOLUME_FIX_BOOT_MIB + TMI_VOLUME_FIX_SWAP_MIB \
        + TMI_VOLUME_FIX_SWAPVOL_MIB + maint_mib + n*tmos_mib \
        + TMI_VOLUME_FIX_APPDATA_MIB + TMI_VOLUME_FIX_SHARE_MIB \
        + TMI_VOLUME_FIX_LOG_MIB ))

    if [[ $n != 1 ]]; then
        # Add a reserve of 15% for all but 1 slot instance:
        BIGIP_HDD_GB=$(( (BIGIP_HDD_GB * 115 / 100) ))
    fi

    # Convert it to GB, because vhdcreate works only with GB:
    BIGIP_HDD_GB=$(( (BIGIP_HDD_GB + 1023) / 1024 ))
    # Cap the size to 127GB as this is the limit for VHD/Azure.
    if [[ $BIGIP_HDD_GB -gt 127 ]]; then
        if [[ "$ve_disk_format" == "vhd" ]] || \
                [[ "$ve_disk_format" == "azure" ]]; then
            log_info "Reduce the size from $BIGIP_HDD_GB to 127GB as this is the limit for VHD/Azure."
            BIGIP_HDD_GB=127
        fi
    fi

    # Alibaba does not allow creation of instances smaller than 20 GiB
    # Creation of a smaller image would lead to partitions resize and reboot
    local alibaba_min_disk_size=20
    if [[ $BIGIP_HDD_GB -lt $alibaba_min_disk_size ]] \
            && [[ "$ve_disk_format" == "alibaba" ]]; then
        log_info "Increase disk size from $BIGIP_HDD_GB to $alibaba_min_disk_size."
        BIGIP_HDD_GB=$alibaba_min_disk_size
    fi

    log_info "BIG-IP Disk Size =$BIGIP_HDD_GB"
}
#####################################################################


#####################################################################
function create_raw_disk {
    local ve_info_json=$1
    local boot_locations=$2
    local module_type=$3
    local platform=$4
    local raw_disk=$5
    local output_json=$6
    local result

    if [[ $# != 6 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <ve_info_json> <boot_locations>" \
                "<volume_configuration> <platform> <raw_disk> <output_json>"
        return 1
    elif [[ ! -f "$ve_info_json" ]]; then
        log_error "'$ve_info_json' doesn't exist."
        return 1
    elif ! is_supported_boot_locations "$boot_locations"; then
        log_error "'$boot_locations' isn't supported."
        return 1
    elif ! is_supported_module "$module_type"; then
        log_error "'$module_type' isn't supported."
        return 1
    elif ! is_supported_platform "$platform"; then
        log_error "'$platform' isn't supported."
        return 1
    fi

    calculate_bigip_hdd_sizes "$ve_info_json" "$boot_locations" "$module_type" \
            "$platform"
    result=$?
    is_supported_cloud "$platform" && is_cloud=1 || is_cloud=0

    if [[ $result == 0 ]]; then
        # Is the disk size in expected range?
        test_disk_size_correctness "$module_type" "$boot_locations" "$BIGIP_HDD_GB"
        result=$?
        if [[ $result == 0 ]]; then
            "$( dirname "${BASH_SOURCE[0]}" )"/../../bin/create_disk "raw" \
                    "${BIGIP_HDD_GB}G" "$raw_disk"
            result=$?
            print_qemu_disk_info "$raw_disk" "raw"
        fi
    fi

    local status
    # so far so good ?
    [[ $result == 0 ]] && status="success" || status="failure"

    # Create the output disk json. This json file will be used by prepare_raw_disk
    # as an input. As the empty raw disk that this script creates, doesn't remain
    # in that state (as prepare_raw_disk install ISO on it), this utility never
    # checks for check_previous_run_status() and always runs by default, as there
    # is no clean-way to verify it's previous run status.
    if jq -M -n \
            --arg description "RAW Disk Size" \
            --arg build_host "$HOSTNAME" \
            --arg build_source "$(basename "${BASH_SOURCE[1]}")" \
            --arg build_user "$USER" \
            --arg platform "$platform" \
            --arg is_cloud "$is_cloud" \
            --arg modules "$module_type" \
            --arg boot_locations "$boot_locations" \
            --arg input "$ve_info_json" \
            --arg disk_name "$(basename "$raw_disk")" \
            --arg status "$status" \
            --arg image_size "$BIGIP_HDD_GB" \
            --arg fix_boot_mib "$TMI_VOLUME_FIX_BOOT_MIB" \
            --arg fix_swap_mib "$TMI_VOLUME_FIX_SWAP_MIB" \
            --arg fix_swapvol_mib "$TMI_VOLUME_FIX_SWAPVOL_MIB" \
            --arg fix_share_mib "$TMI_VOLUME_FIX_SHARE_MIB" \
            --arg fix_appdata_mib "$TMI_VOLUME_FIX_APPDATA_MIB" \
            --arg fix_log_mib "$TMI_VOLUME_FIX_LOG_MIB" \
            '{ description: $description,
            build_source: $build_source,
            build_host: $build_host,
            build_user: $build_user,
            platform: $platform,
            is_cloud: $is_cloud,
            modules: $modules,
            boot_locations: $boot_locations,
            input: $input,
            output: $disk_name,
            status: $status,
            image_size: $image_size,
            attributes: {
                fix_boot_mib: $fix_boot_mib,
                fix_swap_mib: $fix_swap_mib,
                fix_swapvol_mib: $fix_swapvol_mib,
                fix_share_mib: $fix_share_mib,
                fix_appdata_mib: $fix_appdata_mib,
                fix_log_mib: $fix_log_mib } }' \
            > "$output_json"
    then
        log_info "Wrote create_raw_disk status to '$output_json'."
    else
        log_error "Failed to write '$output_json'."
    fi
    return $result
}
#####################################################################


