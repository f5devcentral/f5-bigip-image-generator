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
# shellcheck source=src/lib/bash/util/logger.sh
source "$(realpath "$(dirname "${BASH_SOURCE[0]}")")/util/logger.sh"

####################################################################
# Reads the given isolinux.cfg file to extract the "append" section from it.
# The output is used as the kerne_args for the custom qemu instance to install
# BIG-IP ISOs.
#
# Return value:
#   0 for success, and 1 otherwise.
#   Also prints the output in stdout.
#
function get_kernel_args {
    local boot_conf="$1"
    if [[ -z "$boot_conf" ]]; then
        log_error "Usage:  ${FUNCNAME[0]} <iso>"
        return 1
    elif [[ ! -s "$boot_conf" ]]; then
        log_error "$boot_conf is empty."
        return 1
    fi

    local found_append=0
    local kernel_args first rest
    # Read the given file and look for the lines starting with "append".
    while read -r first rest; do
        if [ "$first" == "append" ]; then
            kernel_args="$rest"
            found_append=$(( found_append + 1 ))
        fi
    done < "$boot_conf"

    # No append section found ?
    if [[ $found_append == 0 ]]; then
        log_error "Missing append directive in $boot_conf."
        return 1
    elif [[ $found_append -gt 1 ]]; then
        log_error "Multiple append directive in $boot_conf."
        return 1
    fi

    # Append VE Platform ID to the kernel args.
    kernel_args="$kernel_args mkvm_pid=Z100 mkvm_log_level=0"
    echo "$kernel_args"
}
#####################################################################


#####################################################################
# Create two markers to know whether the image is 1 slot or allows all modules
# The markers will be propagated to BIG-IP by post-install.
#
# Return value:
#   0 in case of success, 1 otherwise.
#
function add_one_boot_location_markers {
    local json_file="$1"
    local out_dir="$2"
    if [[ $# != 2 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <json> <output dir>"
        return 1
    elif [[ ! -s "$json_file" ]]; then
        log_error "$json_file is empty."
        return 1
    elif [[ ! -d "$out_dir" ]]; then
        log_error "$out_dir is missing."
        return 1
    fi

    local module
    module=$(jq -r '.modules' "$json_file" )
    if [[ -z "$module" ]]; then
        log_error "Failed to read .modules from '$json_file'"
        return 1
    elif ! is_supported_module "$module"; then
        log_error "Unsupported module '$module'."
        return 1
    fi
    local boot_loc
    boot_loc=$(jq -r '.boot_locations' "$json_file" )
    if [[ -z "$module" ]]; then
        log_error "Failed to read .boot_locations from '$json_file'"
        return 1
    elif ! is_supported_boot_locations "$boot_loc"; then
        log_error "Unsupported boot_locations '$boot_loc'."
        return 1
    fi

    local one_slot_marker=".one_slot_marker"
    if [[ $boot_loc == 1 ]]; then
        log_info "Add one slot marker $one_slot_marker"
        touch "$out_dir"/$one_slot_marker
    fi

    local all_modules_marker=".all_modules_marker"
    if [[ "$module" == "all" ]]; then
        log_info "Add all modules marker $all_modules_marker"
        touch "$out_dir"/$all_modules_marker
    fi
}
#####################################################################


#####################################################################
# Generates vm.install.sh that provides the partition sizes to the installer
# for the given image installation.
#
function generate_vm_install_script {
    local vm_install_script="$1"
    local disk_json="$2"

    if [[ $# != 2 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <vm.install.sh path> <raw_disk json path>"
        return 1
    elif [[ ! -s "$disk_json" ]]; then
        log_error "$disk_json is missing or empty."
        return 1
    fi

    # Clean-up previous leftover, if any.
    rm -f "$vm_install_script"

    # Associative array for vm.install.sh field and corresponding disk_json entries.
    declare -A tmi_volume_attributes=( \
        ["TMI_VOLUME_FIX_CONFIG_MIB"]=".attributes.fix_config_mib"
        ["TMI_VOLUME_FIX_ROOT_MIB"]=".attributes.fix_root_mib"
        ["TMI_VOLUME_FIX_USR_MIB"]=".attributes.fix_usr_mib"
        ["TMI_VOLUME_FIX_VAR_MIB"]=".attributes.fix_var_mib"
        ["TMI_VOLUME_FIX_BOOT_MIB"]=".attributes.fix_boot_mib"
        ["TMI_VOLUME_FIX_SWAP_MIB"]=".attributes.fix_swap_mib"
        ["TMI_VOLUME_FIX_SWAPVOL_MIB"]=".attributes.fix_swapvol_mib"
        ["TMI_VOLUME_FIX_SHARE_MIB"]=".attributes.fix_share_mib"
        ["TMI_VOLUME_FIX_APPDATA_MIB"]=".attributes.fix_appdata_mib"
        ["TMI_VOLUME_FIX_LOG_MIB"]=".attributes.fix_log_mib"
    )

    # Write the partition values to vm_install_script.
    echo "#!/bin/bash" >> "$vm_install_script"
    echo "export TMI_VOLUME_SET_COUNT=1" >> "$vm_install_script"

    local entry value
    for entry in "${!tmi_volume_attributes[@]}"; do
        if ! value="$(jq -r "${tmi_volume_attributes[$entry]}" "$disk_json" )" || \
                [[ -z "$value" ]]; then
            log_error "Missing or Failed to read '${tmi_volume_attributes[$entry]}' from '$disk_json'."
            return 1
        fi
        # Write the entry=value pair.
        echo "export $entry=$value" >> "$vm_install_script"
    done

    # Is this a cloud platform? If so, write TMI_VADC_HYPERVISOR value.
    if value="$(jq -r ".is_cloud" "$disk_json")"; then
        if [[ $value == 1 ]]; then
            if ! value="$(jq -r ".platform" "$disk_json")" ||
                    [[ -z "$value" ]]; then
                log_error "Missing or Failed to read '.platform' from '$disk_json'."
                return 1
            fi
            echo "export TMI_VADC_HYPERVISOR=$value" >> "$vm_install_script"
        fi
    else
        log_error "Failed to read '.is_cloud' from '$disk_json'."
        return 1
    fi
    chmod 755 "$vm_install_script"
}
#####################################################################


#####################################################################
# Prepares the environment for the BIG-IP and EHF ISO installations as well as
# for the SELinux labeling boot before executing exec_qemu_system() to actually
# perform the aforementioned operations.
# Usage:
#   install_iso_on_disk() raw_disk disk_json bigip_iso [hotfix_iso]
#   where:
#       raw_disk    - RAW disk on which the given ISOs needs to be installed.
#       disk_json   - create_raw_disk.json output from earlier step that contains
#                     the details of the empty raw_disk.
#       bigip_iso   - BIG-IP RTM ISO.
#       hotfix_iso  - [Optional] EHF ISO.
#
# Return value:
#   Returns 0 in case of success and 1 otherwise.
#
function install_iso_on_disk {
    local disk="$1"
    local disk_json="$2"
    local bigip_iso="$3"
    # Optional argument.
    local hotfix_iso="$4"

    if [[ $# -lt 3 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <raw_disk> <raw_disk_json> <iso> [hotfix_iso]"
        return 1
    elif [[ ! -f "$disk" ]]; then
        log_error "RAW disk '$disk' doesn't exist."
        return 1
    elif [[ ! -s "$disk_json" ]]; then
        log_error "JSON file '$disk_json' is empty or doesn't exist."
        return 1
    elif [[ ! -s "$bigip_iso" ]]; then
        log_error "Invalid ISO '$bigip_iso' or it doesn't exist."
        return 1
    fi

    # Extract the default initrd and kernel images from the ISO.
    BOOT_DIR="$TEMP_DIR/boot"
    local boot_initrd_base="$BOOT_DIR/initrd.base.img"
    # Ensure the dir is clean from previous runs:
    rm -fr "$BOOT_DIR"
    mkdir "$BOOT_DIR"
    local boot_vmlinuz="$BOOT_DIR/vmlinuz"
    isoinfo -R -x /isolinux/vmlinuz -i "$bigip_iso" > "$boot_vmlinuz"

    # Create a new updated initrd image with custom files.
    update_initrd_image "RTM" "$bigip_iso" "$boot_initrd_base" \
            "$disk_json"

    # Build new kernel arguments to pass.
    local boot_conf="$BOOT_DIR/isolinux.cfg"
    isoinfo -R -x /isolinux/isolinux.cfg -i "$bigip_iso" > "$boot_conf"
    local kernel_args
    if ! kernel_args="$(get_kernel_args "$boot_conf")"; then
        log_error "Kernel arg extraction failed."
        return 1
    fi

    # Set the kernel disk to vda (paravirtual).
    local iso_kernel_args="$kernel_args mkvm_cpu_lm mkvm_device=/dev/vda"
    local qemu_logfile="$TEMP_DIR/qemu.iso.log"
    local qemu_pidfile="$TEMP_DIR/qemu.pid"

    exec_qemu_system "$disk" "$bigip_iso" "$qemu_pidfile" "$boot_vmlinuz" \
            "$boot_initrd_base" "$iso_kernel_args" "$qemu_logfile" \
            "installing RTM Image"

    if ! grep -q "MKVM FINAL STATUS = SUCCESS" "$qemu_logfile"; then
        log_error "RTM ISO installation failed."
        return 1
    fi

    # Apply HF if present - avoid extra mkvm options and use only
    # the common kernel command part.
    if [[ -n "$hotfix_iso" ]]; then
        update_initrd_image "HOTFIX" "$hotfix_iso" "$boot_initrd_base" \
                "$disk_json"

        qemu_logfile="$TEMP_DIR/qemu.hotfix.log"
        exec_qemu_system "$disk" "$hotfix_iso" "$qemu_pidfile" "$boot_vmlinuz" \
                "$boot_initrd_base" "$kernel_args" "$qemu_logfile" \
                "installing HF Image"

        if ! grep -q "HOTFIXVM FINAL STATUS = SUCCESS" "$qemu_logfile"; then
            log_error "Hotfix ISO installation failed."
            return 1
        fi
    fi

    qemu_logfile="$TEMP_DIR/qemu.selinux_relabeling.log"
    # Boot the instance to execute selinux relabeling...
    exec_qemu_system "$disk" 0 "$qemu_pidfile" 0 0 0 "$qemu_logfile" \
            "performing selinux relabeling"

    local platform
    platform=$(jq -r '.platform' "$disk_json" )
    if [[ -z "$platform" ]]; then
        log_error "Failed to read .platform from '$disk_json'"
        return 1
    fi

    if is_supported_cloud "$platform"; then
        local artifacts_dir
        artifacts_dir="$(get_config_value "ARTIFACTS_DIR")"
        # Is SELinux labeling done via legacy framework?
        if [[ -f "$artifacts_dir/.legacy_selinux_labeling" ]]; then
            if ! grep -q "SELinux relabeling finished successfully." "$qemu_logfile"; then
                log_error "SELinux labeling failed or skipped." \
                        "Check $qemu_logfile for complete logs"
                return 1
            fi
        else
            # Validate that final-cloud-setup successfully executed.
            if ! grep -q "Cloud setup succeeded." "$qemu_logfile"; then
                log_error "final-cloud-setup failed or skipped." \
                        "Check $qemu_logfile for complete logs"
                return 1
            fi
            # Validate that SELinux labeling successfully executed.
            if ! grep -q "SELinux targeted policy relabel is required." \
                    "$qemu_logfile"; then
                log_error "SELinux labeling failed or skipped." \
                        "Check $qemu_logfile for complete logs"
                return 1
            fi
        fi
    fi

    print_qemu_disk_info "$disk" "raw"
}
#####################################################################


#####################################################################
# Call python script that copies files/dir to a predefined location.
# This location will be available during post-install to copy these files to the image.
function add_injected_files {
    local top_call_dir="$1"
    if [[ $# != 1 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <top call dir>"
        return 1
    elif [[ ! -d "$top_call_dir" ]]; then
        log_error "$top_call_dir is missing or not a directory."
        return 1
    fi

    if "$(realpath "$(dirname "${BASH_SOURCE[0]}")")"/../../bin/read_injected_files.py "$top_call_dir" "$(realpath .)"; then
        log_info "read_injected_files.py passed"
        return 0
    else
        log_error "read_injected_files.py failed"
        return 1
    fi
}
#####################################################################


#####################################################################
# Adds src/bin/legacy files to the initramfs dest_dir.
#
function add_legacy_selinux_labeling_scripts {
    local dest_dir="$1"
    if [[ $# != 1 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <dest dir>"
        return 1
    elif [[ ! -d "$dest_dir" ]]; then
        log_error "$dest_dir is missing or not a directory."
        return 1
    fi
    log_debug "Adding legacy selinux labeling scripts."
    touch "$dest_dir/.legacy_selinux_labeling"
    find "$(realpath "$(dirname "${BASH_SOURCE[0]}")")"/../../bin/legacy/ -type f \
            -exec cp -v {} "$dest_dir" \;
}
#####################################################################


#####################################################################
# Extracts the base initrd image from the given ISO and injects VE specific
# files to it. This updated boot_initrd_base image is then used when booting
# the qemu instance with RTM/EHF ISO.
#       Expected Arguments:
#           - Arg1: "RTM" or "HOTFIX" (Represents both hotfix and ehf).
#           - Arg2: ISO name from which the initrd image is extracted.
#           - Arg3: Base boot initrd file path. This is the returned initrd
#                   image that the caller uses in its qemu run.
#           - Arg4: Option argument that gives the raw_disk.json from the previous
#                   step in the build pipeline. This json file contains the disk
#                   size for the partitions.
#
#       Returns 0 on success and 1 otherwise.
#
function update_initrd_image {
    local install_mode=$1
    local iso_file=$2
    local boot_initrd_base="$3"
    local disk_json="$4"
    if [[ $# != 4 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <install-mode> <ISO> <boot-initrd-img path>" \
                "  <raw-disk-json>"
        return 1
    elif [[ "$install_mode" != "RTM" ]] && [[ "$install_mode" != "HOTFIX" ]]; then
        log_error "Unknown install_mode = '$install_mode'."
        return 1
    elif [[ ! -s "$iso_file" ]]; then
        log_error "Expected an iso as the 2nd argument"
        return 1
    elif [[ ! -s "$disk_json" ]]; then
        log_error "JSON file '$disk_json' is empty or doesn't exist."
        return 1
    fi

    # Inject VE specific configuration and other scripts into the initrd.
    # This happens in following steps:
    #   Step 1) Create a local file-system under $stage_initrd directory that
    #           exactly reflects an extracted initrd in terms of file system
    #           and relative directory paths.
    #   Step 2) Once all the files are in the correct place under $stage_initrd
    #           unzip the boot_initrd locally.
    #   Step 3) Append all files under $stage_initrd (as prepared in Step 1)
    #           to the unzipped INITRD image named "$unzipped_boot_initrd".
    #   Step 4) Zip the "$unzipped_boot_initrd" back to bring it in the same
    #           state that it was in the beginning of Step 2).
    start_task=$(timer)
    log_info "Inserting VM installation environment for '$install_mode'"

    local boot_initrd="$BOOT_DIR/initrd.img"
    # Extract the initrd.img from the ISO.
    isoinfo -R -x /isolinux/initrd.img -i "$iso_file" > "$boot_initrd"

    # Clean-up the stale base initrd file from the previous run.
    [[ -f $boot_initrd_base ]] && rm -f "$boot_initrd_base"

    local top_call_dir
    top_call_dir=$(pwd)
    local stage_initrd="$TEMP_DIR/stage.initrd"
    mkdir "$stage_initrd"

    # Step 1) Create a local file-system under $stage_initrd directory.
    pushd "$stage_initrd" > /dev/null || exit

    local etc_dir="etc"
    local artifacts_dir
    artifacts_dir="$(get_config_value "ARTIFACTS_DIR")"
    if [ "$install_mode" == "RTM" ]; then
        local profile_dir="$etc_dir/profile.d"
        local vm_install_script="$profile_dir/vm.install.sh"
        mkdir -p "$profile_dir"

        if ! generate_vm_install_script "$vm_install_script" "$disk_json"; then
            log_error "Failed to generate '$vm_install_script'."
            return 1
        fi

        if ! add_injected_files "$top_call_dir"; then
            return 1
        fi

	# copy post-install in initrd
        log_info "Include post-install in initrd:"
        cp -f "$(realpath "$(dirname "${BASH_SOURCE[0]}")")"/../../bin/post-install \
                 "$etc_dir"
        if [[ -f "$artifacts_dir/.legacy_selinux_labeling" ]]; then
            add_legacy_selinux_labeling_scripts "$etc_dir"
        fi

	if ! add_one_boot_location_markers "$disk_json" "$etc_dir"; then
            log_error "add_one_boot_location_markers() failed."
            return 1
        fi
    elif [ "$install_mode" == "HOTFIX" ]; then
        mkdir -p "$etc_dir"
        if ! add_injected_files "$top_call_dir"; then
            return 1
        fi
        log_info "Include post-install in initrd:"
        cp -f "$(realpath "$(dirname "${BASH_SOURCE[0]}")")"/../../bin/post-install \
                "$etc_dir"
        if [[ -f "$artifacts_dir/.legacy_selinux_labeling" ]]; then
            add_legacy_selinux_labeling_scripts "$etc_dir"
        fi
    fi

    # Step 2) Unzip the boot_initrd image.
    gunzip -S .img "$boot_initrd"
    local unzipped_boot_initrd="${boot_initrd%.*}"

    # Step 3) Append new files to the initrd.
    log_info "Append the new files in INITRD image: $unzipped_boot_initrd"
    find . | cpio -o -H newc -A -F "$unzipped_boot_initrd"

    # Step 4) Zip the appended initrd.
    gzip -c --best "$unzipped_boot_initrd" > "$boot_initrd_base"
    popd > /dev/null || exit

    # Clean-up.
    rm -fr "$stage_initrd"
    rm -f "$unzipped_boot_initrd"
    rm -f "$boot_initrd"

    log_info "Inserting VM installation environment for '$install_mode' -- elapsed time:" \
            "$(timer "$start_task")"
}
#####################################################################


#####################################################################
# Executes qemu-system-x86_64 with the given cmdline arguments. Pass 0 as the
# value for all options that should be skipped.
#
# Usage:
#   exec_qemu_system() disk cd_disk pidfile kernel initrd append logfile tag 
#   where:
#       disk    - RAW disk on which the given qemu operation will be run.
#       cd_disk - Bootable ISO (RTM or EHF) used for installation. Pass 0 as
#                 the value if not an ISO installation step.
#       pidfile - Qemu process-id file path.
#       kernel  - Use the given bzImage as the kernel image. Pass 0 to skip.
#       initrd  - Use the given file as the initial ram disk. Pass 0 to skip.
#       append  - Space separated cmdline arguments for the passed-in kernel.
#                 Pass 0 to skip.
#       logfile - Log filepath where the output from qemu-system gets stored.
#       tag     - Verbose tag describing given operation.
#
# Return value:
#   Returns 1 in case of malformed arguments. However, it is worth noting that
#   qemu-system-x86_64 returns 0 even in the case of failure to install the ISO
#   or boot the instance. For that reason, the caller should always check the
#   contents of logfile to check if the function execution actually succeeded
#   instead of relying on the return value alone.
#
function exec_qemu_system {
    local disk="$1"
    local cd_disk="$2"
    local pidfile="$3"
    local kernel="$4"
    local initrd="$5"
    local append="$6"
    local logfile="$7"
    local tag="$8"

    if [[ $# -ne 8 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <disk> <cd_disk> <pidfile> <kernel>" \
                "<initrd> <append> <logfile>"
        return 1
    elif [[ "$disk" == "0" ]] || [[ ! -f "$disk" ]]; then
        # disk is a required argument.
        log_error "disk = '$disk', invalid or missing disk."
        return 1
    elif [[ "$pidfile" == "0" ]]; then
        # pidfile is a required argument.
        log_error "pidfile = '$pidfile', must specify a pidfile."
        return 1
    elif [[ "$logfile" == "0" ]]; then
        # logfile is a required argument.
        log_error "logfile = '$logfile', must specify a logfile."
        return 1
    elif [[ "$kernel" != "0" ]] && [[ ! -s "$kernel" ]]; then
        # If a kernel is passed, it must be a non-empty file.
        log_error "kernel = '$kernel', is an empty file."
        return 1
    fi

    # Common cmdline arguments.
    # To watch the GUI execution - remove -nographic and run the following
    # command:
    #       vncviewer -ViewOnly localhost:<Port number in the qemu output>
    # -no-reboot option because some qemu runs (like SELinux labeling) trigger
    # a reboot at the end, which must be blocked to avoid booting TMOS.
    local cmd_line_arg="$OPTION_KVM_ENABLED -nographic -m 2048 -machine kernel_irqchip=off -no-reboot"

    # Append the disk to the cmd_line_arg.
    cmd_line_arg="$cmd_line_arg -drive file=$disk,format=raw,if=virtio,cache=writeback"

    if [[ "$cd_disk" != "0" ]]; then
        cmd_line_arg="$cmd_line_arg -cdrom $cd_disk"
        # Make cd-drive the first boot device.
        cmd_line_arg="$cmd_line_arg -boot d"
    else
        # Make the hard-disk first boot device.
        cmd_line_arg="$cmd_line_arg -boot c"
    fi

    # Append the pidfile argument.
    cmd_line_arg="$cmd_line_arg -pidfile $pidfile"

    if [[ "$kernel" != "0" ]]; then
        cmd_line_arg="$cmd_line_arg -kernel $kernel"
    fi

    if [[ "$initrd" != "0" ]]; then
        cmd_line_arg="$cmd_line_arg -initrd $initrd"
    fi

    local start_task
    start_task=$(timer)

    log_info "qemu-system $tag -- start time: $(date +%T)"

    # qemu-syste-x86_64 doesn't handle empty string well. Therefore instead of running
    # the execute_cmd() that internally handles this, manage the progress-bar from here
    # directly.
    local marker_file
    local waiter_pid
    marker_file="$(mktemp -p "$(get_config_value "ARTIFACTS_DIR")" "${FUNCNAME[0]}".XXXXXX)"
    waiter "$marker_file" &
    waiter_pid="$!"
    log_trace "Created child waiter process:$waiter_pid"

    local tool_log_file
    if is_msg_level_high "$DEFAULT_LOG_LEVEL" && [[ -n "$LOG_FILE_NAME" ]]; then
        tool_log_file="$LOG_FILE_NAME"
    else
        tool_log_file="/dev/null"
    fi

    # append takes space separated value-pairs that need special handling
    # because qemu-system-x86_64 doesn't handle empty string well and fails
    # complaining that the given drive is empty.
    if [[ "$append" == "0" ]]; then
        log_debug "Executing: qemu-system-x86_64 $cmd_line_arg"
        # shellcheck disable=SC2086
        # Double quoting cmd_line_arg fails with qemu as it interprets entire
        # string as a single argument.
        qemu-system-x86_64 $cmd_line_arg < /dev/null 2>&1 | tee -a "$logfile" "$tool_log_file" > /dev/null
    else
        log_debug "Executing: qemu-system-x86_64 $cmd_line_arg -append \"$append\""
        # shellcheck disable=SC2086
        qemu-system-x86_64 $cmd_line_arg \
                -append "$append" < /dev/null 2>&1 | tee -a "$logfile" "$tool_log_file" > /dev/null
    fi
    # Clean-up the marker file to signal the child process to gracefully exit.
    rm -f "$marker_file"

    # Wait for the child process to exit. It should happen within 5 seconds as the
    # signaling marker file has been already removed.
    wait $waiter_pid
    # Add a new-line to pretty up the progress-bar.
    echo ""

    log_info "qemu-system $tag -- elapsed time: $(timer "$start_task")"
}
#####################################################################
