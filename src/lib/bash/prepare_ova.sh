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
# shellcheck source=src/lib/bash/common.sh
source "$(realpath "$(dirname "${BASH_SOURCE[0]}")")/common.sh"
# shellcheck source=src/lib/bash/util/logger.sh
source "$(realpath "$(dirname "${BASH_SOURCE[0]}")")/util/logger.sh"

#####################################################################

function print_fail_status_json {
    local output_json="$1"
    local log_file="$2"

    if [[ $# != 2 ]] || [[ -z "$output_json" ]] || [[ -z "$log_file" ]]; then
        log_error "Usage: ${FUNCNAME[0]} <status> <output_json> <log_file>"
        return 1
    fi

    # Generate the output_json.
    if jq -M -n \
            --arg description "Prepared Virtual disk status" \
            --arg build_host "$HOSTNAME" \
            --arg build_source "$(basename "${BASH_SOURCE[0]}")" \
            --arg build_user "$USER" \
            --arg log_file "$log_file" \
            --arg status "Failure" \
            '{ description: $description,
            build_host: $build_host,
            build_source: $build_source,
            build_user: $build_user,
            log_file: $log_file,
            status: $status }' \
            > "$output_json"
    then
        log_info "Wrote OVA generation status to '$output_json'."
        return 0
    else
        log_error "Failed to write '$output_json'."
        return 1
    fi
}

#####################################################################
function recreate_ova {
    if [[ $# != 4 ]] || [[ -z "$1" ]] || [[ -z "$2" ]] || [[ -z "$3" ]] || [[ -z "$4" ]]; then
        log_error "Received: $*"
        error_and_exit "Usage: <general_bundle_name> <bundle_file_name> <repack_dir> <out_dir>"
    fi
    local general_bundle_name="$1"
    local bundle_file_name="$2"
    local repack_dir="$3"
    local out_dir="$4"
    log_debug "Updating unpacked OVA contents at ${repack_dir}"
    pushd "$repack_dir" > /dev/null

    # Since the OVA contents have been modified we need to update the signatures in the manifest file
    local manifest_file encryption_type_prefix
    files_to_pack=("${general_bundle_name}.ovf")
    files_to_pack+=("$(ls -- *.vmdk)")
    manifest_file="${general_bundle_name}.mf"
    :> "$manifest_file"
    for file in "${files_to_pack[@]}"; do
        log_debug "Regenerating hash for file ${file}"
        # Unfortunately the VMWare VSphere client does not support modern encryption, so we're stuck
        # using SHA1 hashes here.  Signing of the manifest file itself doesn't affect deployment
        # within the client so we're free to use stronger encryption in the next step.
        encryption_type_prefix="SHA1($file)= "
        openssl SHA1 < "$file" | sed "s/(stdin)= /${encryption_type_prefix}/" >> "$manifest_file"
        if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
            log_error "Unable to determine hash for file ${file}!"
        fi
    done
    files_to_pack+=("$manifest_file")

    # Sign the manifest file if private/public signing keys were provided.  This will create a
    # digest of the manifest file using the provided private key.  This digest will be written to a
    # .sig file with the public key packaged alongside it in a .pub file.  This will enable users to
    # check the validity of the files in their OVAs as follows:
    #  * Extract the OVA to a temporary directory
    #  * Generate hashes of the extracted .vmdk and .ovf files
    #  * View the manifest file and confirm that the listed hashes match the generated ones.  This
    #    gives the user confidence that the file contents have not been changed since they were
    #    published.
    #  * Take the public key (.pub file) and digest (.sig file) and use them to verify the manifest
    #    file.  This provides an additional layer of security in case the manifest file itself has
    #    been tampered with.
    local private_key public_key sig_file pub_file
    private_key="$(get_config_value "IMAGE_SIG_PRIVATE_KEY")"
    public_key="$(get_config_value "IMAGE_SIG_PUBLIC_KEY")"
    if [[ ! -z "$private_key" ]] && [[ ! -z "$public_key" ]]; then
        encryption_type="$(get_config_value "IMAGE_SIG_ENCRYPTION_TYPE")"
        log_info "Signing manifest ${manifest_file} using encryption type ${encryption_type} with private key ${private_key}"
        sig_file="${general_bundle_name}.sig"
        if openssl dgst -"$encryption_type" -sign "$private_key" "$manifest_file" > "$sig_file"; then
            pub_file="${general_bundle_name}.pub"
            cat "$public_key" >> "$pub_file"
            files_to_pack+=("$sig_file")
            files_to_pack+=("$pub_file")
        else
            log_error "Unable to sign manifest ${manifest_file} using private key ${private_key}!"
            rm "$sig_file"
        fi
    else
        log_warning "No signing keys were provided.  Skipping OVA signing process!"
        log_warning "Please provide IMAGE_SIG_PRIVATE_KEY and IMAGE_SIG_PUBLIC_KEY if you wish to sign OVA files!"
    fi

    # Create new OVA file based on updated contents
    mkdir -p "$out_dir"
    local out_file=${out_dir}/${bundle_file_name}
    extension="${out_file##*.}"
    case "$extension" in
        ova|tar)
            if ! execute_cmd tar -cvf "$out_file" "${files_to_pack[@]}"; then
                error_and_exit "Unable to create OVA archive at ${out_file}"
            fi
            log_debug "OVA TAR file contents:"
            log_debug "------------------"
            log_cmd_output "$DEFAULT_LOG_LEVEL" tar -tvf "$out_file"
            ;;
        zip)
            if ! execute_cmd zip -1 "$out_file" "${files_to_pack[@]}"; then
                error_and_exit "Unable to create ZIP archive at ${out_file}"
            fi
            log_debug "OVA ZIP file contents:"
            log_debug "------------------"
            log_cmd_output "$DEFAULT_LOG_LEVEL" unzip -l "$out_file"
            ;;
        *)
            error_and_exit "Extension ${extension} is not supported for packing OVA files!"
            ;;
    esac

    # Save an md5 hash of the recreated OVA for use as a simple checksum
    gen_md5 "$out_file"
    popd > /dev/null
}
#####################################################################

#####################################################################
function add_deployment_options_in_ovf {
    local ovf_file="$1"

    # shellcheck disable=SC2181
    if [[ $# != 1 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <OVF filename>"
        return 1
    fi

    if [[ -z "$ovf_file" ]]; then
        log_error "Missing OVF filename parameter"
        return 1
    fi

    log_debug "Adding DeploymentOptions"
    sed -i "/<VirtualSystem ovf:id/ i\
        <DeploymentOptionSection>\n\
          <Info>DeploymentOption Info</Info>\n\
          <Configuration ovf:id=\"singlecpu\">\n\
            <Label>1 CPU/2048 MB RAM</Label>\n\
            <Description>1 CPU and 2048 MB RAM.</Description>\n\
          </Configuration>\n\
          <Configuration ovf:id=\"dualcpu\">\n\
            <Label>2 CPUs/4096 MB RAM</Label>\n\
            <Description>2 CPUs and 4096 MB RAM.</Description>\n\
          </Configuration>\n\
          <Configuration ovf:id=\"quadcpu\">\n\
            <Label>4 CPUs/8192 MB RAM</Label>\n\
            <Description>4 CPUs and 8192 MB RAM.</Description>\n\
          </Configuration>\n\
          <Configuration ovf:id=\"octalcpu\">\n\
            <Label>8 CPUs/16384 MB RAM</Label>\n\
            <Description>8 CPUs and 16384 MB RAM.  High-performance configuration.</Description>\n\
          </Configuration>\n\
        </DeploymentOptionSection>
        " "$ovf_file"
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]]; then
        log_error "Error while adding DeploymentOptions in $ovf_file"
        return 1
    fi

    #check if DeploymentOptionSection was properly added to ovf_file
    p1=$(grep -n "</DeploymentOptionSection>" "$ovf_file" | awk -F ":" '{print $1;}')
    p2=$(grep -n "<VirtualSystem" "$ovf_file" | awk -F ":" '{print $1;}')

    if [[ ! $p1 -lt $p2 ]]; then
        log_error "The DeploymentOptions were not added correctly in $ovf_file"
        return 1
    fi
}

function set_default_deployment_config {
    local ovf_file="$1"

    if [[ $# != 1 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <OVF filename>"
        return 1
    fi

    if [[ -z "$ovf_file" ]]; then
        log_error "Missing OVF filename parameter"
        return 1
    fi

    log_debug "Set the default deployment."
    sed -i 's/<Configuration ovf:id="dualcpu">/<Configuration ovf:id="dualcpu" ovf:default="true">/g' "$ovf_file"
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]] ; then
        log_error "Error while setting default deployment in $ovf_file"
        return 1
    fi
}

function set_ovf_property_retrieval_method {
    local ovf_file="$1"

    if [[ $# != 1 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <OVF filename>"
        return 1
    fi

    if [[ -z "$ovf_file" ]]; then
        log_error "Missing OVF filename parameter"
        return 1
    fi

    # Set the OVF property retrieval method to VMWare tools. With these
    # options, vmtoolsd can be used to query the OVF properties using
    # "info-get guestinfo.ovfEnv" as the --cmd.
    sed -i "/<\/VirtualHardwareSection>/ i \
      <vmw:Config ovf:required=\"true\" vmw:key=\"tools.afterPowerOn\" vmw:value=\"true\" />\n\
      <vmw:Config ovf:required=\"true\" vmw:key=\"tools.afterResume\" vmw:value=\"true\" />\n\
      <vmw:Config ovf:required=\"true\" vmw:key=\"tools.beforeGuestShutdown\" vmw:value=\"true\" />\n\
      <vmw:Config ovf:required=\"true\" vmw:key=\"tools.beforeGuestStandby\" vmw:value=\"true\" />
        "  "$ovf_file"
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]] ; then
        log_error "Error while inserting VirtualHardwareSection in $ovf_file"
        return 1
    fi
}
#####################################################################


#####################################################################
function add_cpu_choices_in_ovf {
    # and right after that, append singlecpu, quadcpu and octalcpu.
    local ovf_file="$1"
    if [[ $# != 1 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <OVF file name>"
        return 1
    fi

    if [[ -z "$ovf_file" ]]; then
        log_error "Missing variable file_name"
        return 1
    fi

    sed -i "1,/<Item>/{ /<\/Item>/a\
          <Item ovf:configuration=\"singlecpu\">\n\
          <rasd:AllocationUnits>hertz * 10^6</rasd:AllocationUnits>\n\
          <rasd:Description>Number of Virtual CPUs</rasd:Description>\n\
          <rasd:ElementName>1 virtual CPU</rasd:ElementName>\n\
          <rasd:InstanceID>1</rasd:InstanceID>\n\
          <rasd:ResourceType>CPUTYPE</rasd:ResourceType>\n\
          <rasd:VirtualQuantity>1</rasd:VirtualQuantity>\n\
        </Item> \n\
        <Item ovf:configuration=\"singlecpu\">\n\
          <rasd:AllocationUnits>byte * 2^20</rasd:AllocationUnits>\n\
          <rasd:Description>Memory Size</rasd:Description>\n\
          <rasd:ElementName>2048MB of memory</rasd:ElementName>\n\
          <rasd:InstanceID>2</rasd:InstanceID>\n\
          <rasd:Reservation>2048</rasd:Reservation>\n\
          <rasd:ResourceType>MEMTYPE</rasd:ResourceType>\n\
          <rasd:VirtualQuantity>2048</rasd:VirtualQuantity>\n\
        </Item> \n\
        <Item ovf:configuration=\"quadcpu\">\n\
        <rasd:AllocationUnits>hertz * 10^6</rasd:AllocationUnits>\n\
          <rasd:Description>Number of Virtual CPUs</rasd:Description>\n\
          <rasd:ElementName>4 virtual CPU(s)</rasd:ElementName>\n\
          <rasd:InstanceID>1</rasd:InstanceID>\n\
          <rasd:ResourceType>CPUTYPE</rasd:ResourceType>\n\
          <rasd:VirtualQuantity>4</rasd:VirtualQuantity>\n\
        </Item> \n\
        <Item ovf:configuration=\"quadcpu\">\n\
          <rasd:AllocationUnits>byte * 2^20</rasd:AllocationUnits>\n\
          <rasd:Description>Memory Size</rasd:Description>\n\
          <rasd:ElementName>8192MB of memory</rasd:ElementName>\n\
          <rasd:InstanceID>2</rasd:InstanceID>\n\
          <rasd:Reservation>8192</rasd:Reservation>\n\
          <rasd:ResourceType>MEMTYPE</rasd:ResourceType>\n\
          <rasd:VirtualQuantity>8192</rasd:VirtualQuantity>\n\
        </Item> \n\
        <Item ovf:configuration=\"octalcpu\">\n\
          <rasd:AllocationUnits>hertz * 10^6</rasd:AllocationUnits>\n\
          <rasd:Description>Number of Virtual CPUs</rasd:Description>\n\
          <rasd:ElementName>8 virtual CPU(s)</rasd:ElementName>\n\
          <rasd:InstanceID>1</rasd:InstanceID>\n\
          <rasd:ResourceType>CPUTYPE</rasd:ResourceType>\n\
          <rasd:VirtualQuantity>8</rasd:VirtualQuantity>\n\
        </Item> \n\
        <Item ovf:configuration=\"octalcpu\">\n\
          <rasd:AllocationUnits>byte * 2^20</rasd:AllocationUnits>\n\
          <rasd:Description>Memory Size</rasd:Description>\n\
          <rasd:ElementName>16384MB of memory</rasd:ElementName>\n\
          <rasd:InstanceID>2</rasd:InstanceID>\n\
          <rasd:Reservation>16384</rasd:Reservation>\n\
          <rasd:ResourceType>MEMTYPE</rasd:ResourceType>\n\
          <rasd:VirtualQuantity>16384</rasd:VirtualQuantity>\n\
        </Item>
        }" "$ovf_file"
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]] ; then
        log_error "${FUNCNAME[0]} - Error while inserting CPU choices in $ovf_file"
        return 1
    fi
}
#####################################################################

#####################################################################
# Modify the vmx file to update display names and other attributes
# with BIGIP specific info.
function modify_template_vmx_file {
    local platform="$1"
    local general_bundle_name="$2"
    local mem_size="$3"
    local num_cpus="$4"
    local input_vmx_file="$5"
    local output_vmx_file="$6"

    if [[ $# != 6 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <platform> <bundle name> <mem size>" \
          "<number of cpus> <input VMX file> <output VMX file>"
        return 1
    fi

    if [[ -z "$platform" ]]; then
        log_error "Missing variable platform."
        return 1
    fi
    if [[ -z "$general_bundle_name" ]]; then
        log_error "Missing variable bundle name"
        return 1
    fi
    if [[ -z "$mem_size" ]]; then
        log_error "Missing variable mem_size"
        return 1
    fi
    if [[ -z "$num_cpus" ]]; then
        log_error "Missing variable num_cpus"
        return 1
    fi
    if [[ -z "$input_vmx_file" ]]; then
        log_error "Missing variable input_vmx_file"
        return 1
    fi
    if [[ -z "$output_vmx_file" ]]; then
        log_error "Missing variable output_vmx_file"
        return 1
    fi

    log_debug "Assemble the machine and disk with appropriate names."
    sed -e "s/__DISPLAY_NAME__/$general_bundle_name/" \
        -e "s/__GUEST_OS_ALT_NAME__/$general_bundle_name/" \
        -e "s/__VMDK_FILE_NAME__/$general_bundle_name.vmdk/" \
        -e "s/__MEM_SIZE__/$mem_size/" \
        -e "s/__NUM_CPUS__/$num_cpus/" \
        -e 's/[ ]*#.*$//' \
        -e '/^$/d' \
        "$input_vmx_file" > "$output_vmx_file"
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]] ; then
        log_error "Error while modifying $input_vmx_file"
        return 1
    fi
}
#####################################################################

#####################################################################
# Modify several sections of the ovf file to contain BIGIP specific info
function update_ovf_file_fields {
    local ovf_file="$1"
    local product_build="$2"
    local product_version="$3"

    local ve_product_name="BIG-IP"
    local ve_product_descr="BIG-IP Local Traffic Manager Virtual Edition"

    if [[ $# != 3 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <OVF file name> <product build> <product version>"
        return 1
    fi

    if [[ -z "$ovf_file" ]]; then
        log_error "Missing variable ovf_file"
        return 1
    fi

    if [[ -z "$product_build" ]]; then
        log_error "Missing variable product_build"
        return 1
    fi

    if [[ -z "$product_version" ]]; then
        log_error "Missing variable product_version"
        return 1
    fi

    log_debug "Check for OperatingSystemSection:"
    grep "OperatingSystemSection" "$ovf_file"
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]]; then
         log_error "$ovf_file does not contain OperatingSystemSection"
         return 1
    fi

    # ISSUE - Try to replace the logic below.
    # Use a tool which can parser/change XML directly instead of massaging it with sed.
    log_debug "Adding new AnnotationSection and ProductSection"
    sed -i "/<OperatingSystemSection/ i\
        <AnnotationSection>\n\
          <Info>F5 $ve_product_name Virtual Edition</Info>\n\
          <Annotation>$ve_product_descr\n\
    Copyright 2009-2016 F5 Networks (http://www.f5.com)\n\
    \n\
    For support please visit http://support.f5.com\n\
          </Annotation>\n\
        </AnnotationSection>\n\
        <ProductSection>\n\
          <Info>F5 $ve_product_name</Info>\n\
          <Product>$ve_product_descr VE $product_version.$product_build</Product>\n\
          <Vendor>F5 Networks</Vendor>\n\
          <Version>$product_version</Version>\n\
          <FullVersion>$product_version-$product_build</FullVersion>\n\
          <VendorUrl>http://www.f5.com</VendorUrl>\n\
        </ProductSection>
    " "$ovf_file"
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]] ;then
        log_error "Error while modifying $ovf_file with product info"
        return 1
    fi

    if ! grep -q "<AnnotationSection" "$ovf_file"; then
        log_error "$ovf_file does not contain AnnotationSection"
        return 1
    fi

    if ! grep -q "<ProductSection" "$ovf_file"; then
        log_error "$ovf_file does not contain ProductSection"
        return 1
    fi

    #check if DeploymentOptionSection was properly added to ovf_file
    p1=$(grep -n "</ProductSection>" "$ovf_file" | awk -F ":" '{print $1;}')
    p2=$(grep -n "<OperatingSystemSection" "$ovf_file" | awk -F ":" '{print $1;}')
    if [[ ! $p1 -lt $p2 ]]; then
        log_error "AnnotationSection and productSection was not added correctly in the $ovf_file"
        return 1
    fi

    # Changing the default network adapter names to more friendly ones.
    sed -i 's/ethernet0/Management/' "$ovf_file"
    sed -i 's/ethernet1/Internal/' "$ovf_file"
    sed -i 's/ethernet2/External/' "$ovf_file"
    sed -i 's/ethernet3/HA/' "$ovf_file"
}
#####################################################################

#####################################################################
function prepare_ova {
    local platform="$1"
    local raw_disk="$2"
    local artifacts_dir="$3"
    local general_bundle_name="$4"
    local bundle_name="$5"
    local output_json="$6"
    local log_file="$7"

    output_json="$(realpath "$output_json")"

    if [[ $# != 7 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <platform> <raw_disk> <artifacts_dir>" \
                 "<general_bundle_name> <bundle_name> <output_json>"
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi

    if [[ -z "$platform" ]]; then
        log_error "Missing variable platform"
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi
    if [[ -z "$raw_disk" ]]; then
        log_error "Missing variable raw_disk"
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi
    if [[ -z "$artifacts_dir" ]]; then
        log_error "Missing variable artifacts_dir"
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi
    if [[ -z "$general_bundle_name" ]]; then
        log_error "Missing variable general_bundle_name"
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi
    if [[ -z "$bundle_name" ]]; then
        log_error "Missing variable bundle_name"
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi
    if [[ -z "$output_json" ]]; then
        log_error "Missing variable output_json"
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi
    if [[ -z "$log_file" ]]; then
        log_error "Missing variable log_file"
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi

    # Check if the current execution is a re-run of previously successful execution.
    if check_previous_run_status "$output_json" "$bundle_name" ; then
        log_info "Skipping OVA generation as the output virtual disk '$bundle_name'" \
                "was generated successfully earlier."
        return 0
    fi

    local out_dir=""
    local temp_dir=""
    local bundle_file_name=""

    # Get the output directory from the bundle_name path.
    out_dir="$(realpath "$(dirname "$bundle_name")")"
    bundle_file_name="$(basename "$bundle_name")"
    output_json="$(realpath "$output_json")"
    temp_dir=$(mktemp -d -p "$artifacts_dir")
    
    local vmdk_disk_name="$artifacts_dir/$general_bundle_name.vmdk"
    local machine_class="production"

    local template_dir=""
    template_dir="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"/../../resource/vmx
    if [[ ! -d "$template_dir" ]]; then
        log_error "$template_dir is not a directory"
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi

    local template_vmx="$template_dir/$machine_class.template.vmx"
    # shellcheck disable=SC2181
    if [[ ! -f "$template_vmx" ]]; then
        log_error "$template_vmx does not exist or is not a file"
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi

    # Resource provisions
    local num_cpus=2
    local mem_size=0
    mem_size=$((num_cpus * 2048))

    # VMWare and AWS VMDKs need lsilogic adapter.
    if [[ "$platform" == "vmware" ]] || [[ "$platform" == "aws" ]]; then
        local qemu_vmware_disk_opt="adapter_type=lsilogic"
    fi

    # Convert raw disk to vmdk format
    "$( dirname "${BASH_SOURCE[0]}" )"/../../bin/convert vmdk "$artifacts_dir/$raw_disk" \
            "$vmdk_disk_name" $qemu_vmware_disk_opt
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]] ; then
        log_error "Conversion of raw disk image did not work"
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi

    echo "ddb tags in $vmdk_disk_name:"
    grep --binary-files=text "^ddb." "$vmdk_disk_name"

    local prod_vmx_file="$artifacts_dir/$machine_class.vmx"
    modify_template_vmx_file "$platform" "$general_bundle_name" "$mem_size" "$num_cpus" "$template_vmx" "$prod_vmx_file"
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]] ; then
        log_error "Modifying $template_vmx file failed"
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi

    if [[ ! -f $prod_vmx_file ]]; then
        log_error "$prod_vmx_file does not exist, virtual disk creation will exit."
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi

    chmod u+w "$prod_vmx_file"

    log_debug "Check OS in $prod_vmx_file"
    log_cmd_output "$DEFAULT_LOG_LEVEL" grep OS "$prod_vmx_file"

    local out_ova_file="$temp_dir/$general_bundle_name.ova"

    # Bundle into OVA
    start_task=$(timer)
    log_info "Initial OVA generation -- start time: $(date +%T)"
    ovftool --diskMode=streamOptimized "$prod_vmx_file" "$out_ova_file"
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]] ; then
        log_error "Error while running ovftool on $prod_vmx_file"
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi
    log_info "Initial OVA generation -- elapsed time: $(timer "$start_task")"

    if [[ ! -f "$out_ova_file" ]]; then
        log_error "The $out_ova_file is not present"
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi

    local repack_dir="$temp_dir/repackage"
    mkdir "$repack_dir"
    cd "$repack_dir" || return
    log_info "Extract OVA to fix up OVF translation. Files from OVA:"

    tar fxv "$out_ova_file"

    local ovf_file="${general_bundle_name}.ovf"

    if [[ ! -f "$ovf_file" ]]; then
        log_error "The $ovf_file is not present"
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi

    # shellcheck disable=SC2153
    update_ovf_file_fields "$ovf_file" "$PRODUCT_BUILD" "$PRODUCT_VERSION"
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]]; then
        log_error "Error while updating fields in $ovf_file"
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi

    # Copy that OVF file to one that we'll use for vCloud ver 1.5
    # It must be done prior adding deployment options as vCloud Director
    # cannot handle them.
    local my_ovf
    if [[ "$platform" == "aws" ]]; then
        my_ovf="$bundle_file_name.ovf"
        cp "$ovf_file" "$my_ovf"
    fi

    # The old ovftool cannot handle it if set in VMX template
    log_debug "Replacing osType to 'other3xlinux-64'"
    sed -i "s/<OperatingSystemSection.*>/<OperatingSystemSection ovf:id=\"100\" vmw:osType=\"other3xLinux64Guest\">/" \
            "$ovf_file"
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]]; then
        log_error "Error while replacing osType in $ovf_file"
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi

    add_deployment_options_in_ovf "$ovf_file"
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]]; then
        log_error "add_deployment_options_in_ovf during OVA generation failed"
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi

    set_default_deployment_config "$ovf_file"
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]]; then
        log_error "Error setting default deployment configuration in OVF file; OVA cannot be generated"
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi
    log_debug "Modifying the memory and cpu deployment options."
    # replace the first Item (the dual CPU) with a configured item
    sed -i '1,/<Item>/s/<Item>/<Item ovf:configuration="dualcpu">/' "$ovf_file"
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]] ; then
        log_error "Error while replacing configuration in $ovf_file"
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi

    add_cpu_choices_in_ovf "$ovf_file"
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]] ; then
        log_error "Error while inserting cpu choices info in $ovf_file"
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi

    set_ovf_property_retrieval_method "$ovf_file"
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]] ; then
        log_error "Error while setting property for retrieval method in $ovf_file"
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi

    sed -i 's/<VirtualHardwareSection>/<VirtualHardwareSection ovf:transport="com.vmware.guestInfo">/' "$ovf_file"
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]] ; then
        log_error "Error while inserting guest OS info in $ovf_file"
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi

    echo "Making a Deployment item"
    sed -i '1,/<Item>/s/<Item>/<Item ovf:configuration="dualcpu">/' "$ovf_file"
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]] ; then
        log_error "Error while inseting a dualCPU item in $ovf_file"
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi

    local f_ovf
    log_debug "Adding Memory resource reservation"
    for f_ovf in $ovf_file $my_ovf; do
        if [[ ! -f "$f_ovf" ]]; then
            log_error "The $f_ovf is not present"
            print_fail_status_json "$output_json" "$log_file"
            return 1
        fi
        sed -i 's%<rasd:ResourceType>4%<rasd:Reservation>4096</rasd:Reservation>\n        <rasd:ResourceType>4%' \
                "$f_ovf"
        # shellcheck disable=SC2181
        if [[ $? -ne 0 ]] ; then
            log_error "Error while inserting Reservation infor in $f_ovf"
            print_fail_status_json "$output_json" "$log_file"
            return 1
        fi
    done
    sed -i -e 's/CPUTYPE/3/' -e 's/MEMTYPE/4/' "$ovf_file"
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]] ; then
        log_error "Error while modifying CPUTYPE and MEMTYPE in $ovf_file"
        print_fail_status_json "$output_json" "$log_file"
        return 1
    fi

    if [[ "$platform" == "aws" ]]; then
        # Put back the vCloud director file and build a zip file
        cp "$my_ovf" "$ovf_file"
    fi
    recreate_ova "$general_bundle_name" "$bundle_file_name" "$repack_dir" "$out_dir"

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

    local status="success"
    # Generate the output_json.
    if jq -M -n \
            --arg description "Prepared Virtual disk status" \
            --arg build_host "$HOSTNAME" \
            --arg build_source "$(basename "${BASH_SOURCE[0]}")" \
            --arg build_user "$USER" \
            --arg platform "$platform" \
            --arg input "$raw_disk" \
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
            output: $output,
            sig_file: $sig_file,
            output_partial_md5: $output_partial_md5,
            output_size: $output_size,
            log_file: $log_file,
            status: $status }' \
            > "$output_json"
    then
        log_info "Wrote OVA generation status to '$output_json'."
    else
        log_error "Failed to write '$output_json'."
    fi

    # Remove temporary file:
    if [[ "$temp_dir" != "" ]]; then
        if [[ -d "$temp_dir" ]]; then
            rm -fr "$temp_dir"
        fi
    fi
}
#####################################################################
