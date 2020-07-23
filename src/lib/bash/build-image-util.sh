#!/bin/bash
# Copyright (C) 2018-2020 F5 Networks, Inc
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


# initialize the log file name
function init_log_file {
    local canned_name
    local canned_path
    local log_file
    if [[ $# != 1 ]]; then
        error_and_exit "Usage: ${FUNCNAME[0]} <log_file>"
    fi
    log_file=$1

    # Setup canned path/name
    canned_path="$(realpath "$(dirname "${BASH_SOURCE[0]}")")/../../../logs"
    if [[ "$platform" == "iso" ]]; then
        canned_name="image-$platform"
    else
        canned_name="image-$platform-$modules-${boot_locations}slot"
    fi

    if [ -z "$log_file" ]; then
       # If log file is not provided, use canned directory and filename
       mkdir -p "$canned_path"
       log_file="$canned_path/$canned_name"
    else
        if [ -d "$log_file" ]; then
            # If directory is provided, use canned filename in that directory
            log_file="$log_file/$canned_name"
        else
            if [ "$(basename "$log_file")" == "$log_file" ]; then
                # If log file doesn't contain path, use canned path
                mkdir -p "$canned_path"
                log_file="$canned_path/$log_file"
            fi
        fi
    fi

    echo "$log_file"
}

# initialize the image directory
function init_image_dir {
    local base_dir
    if [[ $# != 1 ]]; then
        error_and_exit "Usage: ${FUNCNAME[0]} <base_dir>"
    fi
    base_dir="$1"

    # Get current config value
    local image_dir
    image_dir="$(get_config_value "IMAGE_DIR")"

    # Determine if current config value should be altered
    if [[ -z "$image_dir" ]]; then
        # If image_dir is not provided, use canned 'images' directory
        image_dir="${base_dir}/images"
    elif [[ "$image_dir" != "/"* ]]; then
        # If image_dir is not absolute, use path relative to pwd
        image_dir="$(realpath "$image_dir")"
    fi

    # Ensure directory exists
    if [[ ! -d "$image_dir" ]]; then
        log_info "Create image directory: $image_dir"
        mkdir -p "$image_dir"
    fi

    # Check if directory is writeable
    if [[ ! -w "$image_dir" ]]; then
        error_and_exit "Do not have permission to write to image directory: $image_dir"
    fi

    # Update config value
    set_config_value "IMAGE_DIR" "$image_dir"
    return 0
}


# deduce the volume configuration based on the module selection and
# the number of boot locations
# return 0 and print out the configuration out if the input is valid
# return 1 and print out the error otherwise
function get_modules_production_name {
    local modules=$1
    local boot_locations=$2

    if [[ $# != 2 ]]; then
        error_and_exit "Usage: ${FUNCNAME[0]} <modules> <boot_locations>"
    elif ! is_supported_module "$modules"; then
        error_and_exit "Unknown module '$modules' passed."
    elif ! is_supported_boot_locations "$boot_locations"; then
        error_and_exit "Unsupported boot locations '$boot_locations' passed."
    fi
    local output
    output="$(echo "$modules" | tr '[:lower:]' '[:upper:]')"
    if [[ $boot_locations == 1 ]]; then
        output+="_1SLOT"
    fi
    echo "$output"
}


# Check if the input iso path is a local file or a URL 
# If the file exists, return 0 to indicate it does not have to be downloaded
# If the URL is valid ( http status code 200 or 320 ) return 0
# else return 1
function is_iso_path_valid_url {
    local iso_url="$1"

    if [[ $# -lt 1 ]]; then
        error_and_exit "Usage: ${FUNCNAME[0]} <iso_path>"
    elif [[ -z "$1" ]]; then
        error_and_exit "Expected non-empty <iso_path>'$*'"
    fi

    local http_code
    local ignore_tls
    ignore_tls="$(get_config_value "IGNORE_DOWNLOAD_URL_TLS")"
    local cert_check
    cert_check=""
    if [[ -n "$ignore_tls" ]]; then
        cert_check="--insecure"
    fi

    http_code="$(curl "$cert_check" -o /dev/null -I -w "%{http_code}" "$iso_url")"
    if [[ "$http_code" -eq "200" ]] || [[ "$http_code" -eq "302" ]]; then
        return 0
    fi
    return 1
}


# Checks if the iso file is locally available or is it a URL
# If the iso is a file and locally available, then just returns
# the provided iso argument value
# If the iso is a URL then downloads the iso file and assigns
# a proper BIGIP iso name and returns the new iso file path.
function check_iso_src {
    local iso="$1" 
    local ehf_flag="$2"
    local store_dir="$3"
    local out_file="$4"

    if [[ $# -lt 4 ]]; then
        error_and_exit "Usage: ${FUNCNAME[0]} <iso> <ehf_file> <store_dir> <out_msg_file>"
    elif [[ -z "$1" ]] || [[ -z "$3" ]]  || [[ -z "$4" ]]; then
        error_and_exit "Expected non-empty <iso_out> <store_dir> <out_msg_file>. Received '$*'"
    fi

    if [[ -f "$iso" ]]; then
       echo "$iso" > "$out_file"
       return 0
    fi

    local version_file
    if [[ -z "$ehf_flag" ]]; then
        version_file="VERSION"
    else
        version_file="VERSION.LTM"
    fi

    # Check if the input iso path is a URL
    if is_iso_path_valid_url "$iso"; then
        log_info "$iso is a valid URL"
        # Create a temporary directory to download the iso to
                
        tmp_iso="downloaded.iso"
        tmp_iso_path="$store_dir/$tmp_iso"

        # Check if the iso path is actually an url
        if ! download_file_from_url "$iso" "$tmp_iso_path"; then
            echo "Error: BIGIP iso download failed" > "$out_file"
            return 1
        fi

        if [[ ! -f "$tmp_iso_path" ]]; then
            echo "Error: Could not find the iso - BIGIP iso download failed" > "$out_file"
            return 1
        fi

        log_info "Downloaded $tmp_iso_path"

        # extract VERSION file from the ISO and populate global vars
        if ! extract_bigip_product_info_from_iso "$tmp_iso_path" "$ehf_flag" "$version_file" "$store_dir"; then
            echo "Error: extract_bigip_product_info_from_iso has failed." > "$out_file"
            return 1
        fi

        local iso_name
        iso_name="$(compose_internal_disk_name "$PRODUCT_NAME" \
                "$PRODUCT_VERSION" "$PRODUCT_BUILD" "$PROJECT_NAME")"
        iso_name="$store_dir/$iso_name".iso

        if ! mv -fv "$tmp_iso_path" "$iso_name"; then
            echo "Error: Unable to move iso from $tmp_iso_path to $iso_name" > "$out_file"
            return 1
        fi
        echo "$iso_name" > "$out_file"
        return 0
    else
        echo "Error: Ths input iso does not exist" > "$out_file"
        return 1
    fi
    return 0
}


function check_iso_sig_src {
    local iso_sig="$1" 
    local out_file="$2"
    local save_to_loc="$3"

    if [[ $# -lt 3 ]]; then
        error_and_exit "Usage: ${FUNCNAME[0]} <iso_sig> <out_file>" \
                "<save_to_loc>]"
    elif [[ -z "$2" ]] || [[ -z "$3" ]]; then
        error_and_exit "Expected non-empty <iso_sig> <out_file> <save_to_loc>. Received '$*'"
    fi

    if [[ -f "$iso_sig" ]]; then
       echo "$iso_sig" > "$out_file"
       return 0
    fi

    # Check if the input iso path is a URL
    if is_iso_path_valid_url "$iso_sig"; then
        log_info "$iso_sig URL is available"
        # Check if the iso path is actually an url
        if ! download_file_from_url "$iso_sig" "$save_to_loc"; then
            echo "Error: BIGIP iso sig file download failed" > "$out_file"
            return 1
        fi

        if [[ ! -f "$save_to_loc" ]]; then
            echo "Error: BIGIP sig file download failed" > "$out_file"
            return 1
        fi
        echo "$save_to_loc" > "$out_file"
    fi
    return 0
}


# Download the iso into the provided path
function download_file_from_url {
    local iso_url="$1"
    local out_iso_path="$2"

    local ignore_tls
    ignore_tls="$(get_config_value "IGNORE_DOWNLOAD_URL_TLS")"
    local cert_check
    cert_check=""
    if [[ -n "$ignore_tls" ]]; then
        cert_check="--no-check-certificate"
    fi

    if ! wget "$cert_check" --progress=dot:giga -O "$out_iso_path" "$iso_url"; then
        log_error "Error: Unable to get iso from $iso_url"
        return 1
    fi

    log_info "Downloaded $out_iso_path from URL:$iso_url"
    return 0
}


# compose and printout internal disk name name
# it does not have any platform or sizing type information appended
function compose_internal_disk_name {
    local product="$1"
    local version="$2"
    local build="$3"
    local project_name="$4"

    if [[ $# -lt 3 ]]; then
        error_and_exit "Usage: ${FUNCNAME[0]} <product> <version> <build>" \
                "optional [<project-name>]"
    elif [[ -z "$1" ]] || [[ -z "$2" ]] || [[ -z "$3" ]]; then
        error_and_exit "Expected non-empty <product> <version> <build>. Received '$*'"
    fi

    # Start assembling the image name --
    local output="$product"

    # -- Project is optional
    if [[ -n "$project_name" ]]; then
        output+="-$project_name"
    fi

    # -- fixed suffix
    output+="-$version-$build"
    echo "$output"
}


# Form a substring to be used in names of EHF images
function form_ehf_marker {
    if [[ -n "$1" ]]; then
        echo "Hotfix-"
    fi
}

# compose and printout cloud image name
# currently company and license model are hardwired
function compose_cloud_image_name {
    local product="$1"
    local version="$2"
    local build="$3"
    local modules="$4"
    local boot_locations="$5"
    local project_name="$6"
    local ehf_iso="$7"

    # The first five args are required
    if [[ $# -ne 7 ]]; then
        error_and_exit "Usage: ${FUNCNAME[0]} <product> <version> <build>" \
                "<modules> <boot_locations> <project-name> <ehf_iso>"
    elif [[ -z "$1" ]] || [[ -z "$2" ]] || [[ -z "$3" ]] || \
         [[ -z "$4" ]] || [[ -z "$5" ]]; then
        error_and_exit "Expected non-empty <product> <version>" \
                "<build> <modules> <boot_locations> received '$*'"
    fi

    # -- EHF marker
    local ehf_marker
    ehf_marker="$(form_ehf_marker "$ehf_iso")"

    # Start assembling the image name --
    local output="F5-$ehf_marker$product"

    # -- Project is optional
    if [[ -n "$project_name" ]]; then
        output+="-$project_name"
    fi

    # -- fixed suffix
    output+="-$version-$build-BYOL-$modules-${boot_locations}slot"
    echo "$output"
}


# compose and printout bundle file extension 
function get_disk_extension {
    local platform="$1"
    if [[ -z "$platform" ]]; then
        log_error "Usage: ${FUNCNAME[0]} <platform>"
        return 1
    elif ! is_supported_platform "$platform"; then
        log_error "Unsupported platform = '$platform'"
        return 1
    fi

    local extension
    case "$platform" in
        alibaba|gce)
            extension='tar.gz'
            ;;
        aws|qcow2|vhd)
            extension='zip'
            ;;
        azure)
            extension='vhd.tar.gz'
            ;;
        vmware)
            extension='ova'
            ;;
        *) # Should never come here.
            log_error "Unknown platform '$platform'"
            return 1
    esac

    echo $extension
}


# extract given src file from the ISO to the dest file.
function extract_file_from_iso {
    local iso_name="$1"
    local src_path_in_iso="$2"
    local dest_file="$3"

    if [[ $# -ne 3 ]]; then
        error_and_exit "Usage: ${FUNCNAME[0]} <iso-path> <src-file-in-iso> <dest-file>"
    elif [[ -z "$iso_name" ]] || [[ ! -s "$iso_name" ]]; then
        error_and_exit "ISO argument '$iso_name' is missing or the iso doesn't exist."
    fi

    log_info "Extracting '$src_path_in_iso' from '$iso_name'"

    # Make sure the directory exists before extracting the file.
    mkdir -p "$(dirname "$dest_file")"
    if ! isoinfo -R -x "$src_path_in_iso" -i "$iso_name" > "$dest_file" ; then
        log_info "Couldn't extract '$dest_file' from the iso."
        return 1
    fi

    # is the file still empty ?
    if [[ ! -s "$dest_file" ]]; then
        log_error "Extracted file '$dest_file' is empty."
        return 1
    fi
    log_info "Successfully extracted '$dest_file' from '$iso'."
}


# extract value of the specified key from the file
# the value is separated from the key by ': '
# printout the value, or an error
# return 0 if passed; otherwise return 1
function extract_value {
    local key="$1"
    local file_name="$2"
    if [[ $# -ne 2 ]]; then
        error_and_exit "Received a wrong number ($#) of parameters: $*"
    fi

    local value
    value=$(grep "^$key:" "$file_name" | cut -d ' ' -f 2)
    if [[ ${PIPESTATUS[0]} -ne 0 ]] || [[ ${PIPESTATUS[1]} -ne 0 ]] || \
            [[ -z "$value" ]]; then
        log_debug "Could not find '$key:' in $file_name"
        return 1
    fi
    echo "$value"
}


# parse version file, set some global variables
# return 0 if passed; otherwise exit with 1
function parse_version_file {
    local version_file="$1"
    if [[ $# -ne 1 ]]; then
        error_and_exit "Received a wrong number ($#) of parameters: $*"
    fi

    unset PRODUCT_NAME
    if ! PRODUCT_NAME=$(extract_value Product "$version_file") ; then
        error_and_exit "Failed to extract PRODUCT_NAME from '$version_file'."
    fi
    PRODUCT_NAME=${PRODUCT_NAME//-/}
    log_info "PRODUCT_NAME: $PRODUCT_NAME"
    export PRODUCT_NAME

    unset PRODUCT_BASE_BUILD
    if ! PRODUCT_BASE_BUILD=$(extract_value BaseBuild "$version_file") ; then
        error_and_exit "Failed to extract PRODUCT_BASE_BUILD from '$version_file'."
    fi
    log_info "PRODUCT_BASE_BUILD: $PRODUCT_BASE_BUILD"
    export PRODUCT_BASE_BUILD

    unset PRODUCT_BUILD
    if ! PRODUCT_BUILD=$(extract_value Build "$version_file") ; then
        error_and_exit "Failed to extract PRODUCT_BUILD from '$version_file'."
    fi
    log_info "PRODUCT_BUILD: $PRODUCT_BUILD"
    export PRODUCT_BUILD

    unset PRODUCT_VERSION
    if ! PRODUCT_VERSION=$(extract_value Version "$version_file") ; then
        error_and_exit "Failed to extract PRODUCT_VERSION from '$version_file'."
    fi
    log_info "PRODUCT_VERSION: $PRODUCT_VERSION"
    export PRODUCT_VERSION

    # PROJECT_NAME is optional
    unset PROJECT_NAME
    if PROJECT_NAME=$(extract_value Project "$version_file") ; then
        log_info "PROJECT_NAME: $PROJECT_NAME"
        export PROJECT_NAME
    else
        unset PROJECT_NAME
    fi

}


# extract from iso path prefix that precedes every file/rtm
# print out the path prefix
function extract_bigip_prefix_from_iso {
    local iso="$1"
    if [[ $# -ne 1 ]]; then
        error_and_exit "Received a wrong number ($#) of parameters: $*"
    fi

    # find out directory name within the iso
    # examples /BIGIP1410, /BIGIP13107, /BIGIQ6012
    local path_prefix
    path_prefix=$(isoinfo -J -f -i "$iso" | grep '^/BIGI[PQ][[:digit:]]*$' | grep '^/BIGI[PQ][[:digit:]]*$')
    if [[ ${PIPESTATUS[0]} -ne 0 ]] || [[ ${PIPESTATUS[1]} -ne 0 ]] || \
            [[ ${PIPESTATUS[2]} -ne 0 ]] || [[ -z "$path_prefix" ]]; then
        error_and_exit "exit because could not find version based directory in the iso"
    fi

    echo "$path_prefix"
}


# Create metadata filter files for version_file
function create_version_file_metadata {
    local artifacts_dir="$1"
    local version_file="$2"
    if [[ $# -ne 2 ]]; then
        error_and_exit "Received a wrong number ($#) of parameters: $*"
    fi
    local script_dir
    script_dir="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"

    "${script_dir}/../../bin/version_file.py" -f "$version_file" -o "$artifacts_dir"
}


# Copy metadata filter config files
function copy_metadata_filter_config_files {
    local artifacts_dir="$1"
    if [[ $# -ne 1 ]]; then
        error_and_exit "Received a wrong number ($#) of parameters: $*"
    fi
    local script_dir
    script_dir="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"

    local metadata_resource_dir="${artifacts_dir}/resource/metadata"
    mkdir -p "$metadata_resource_dir"
    cp "${script_dir}/../../resource/metadata/"*.yml "$metadata_resource_dir"
}


# Create the artifacts directory.
#   block_deletion - block deletion of the old artifacts directory
function create_artifacts_directory {
    if [[ $# -ne 1 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <block_deletion>"
        return 1
    fi

    local block_deletion="$1"

    local artifacts_dir
    artifacts_dir="$(get_config_value "ARTIFACTS_DIR")"

    local output
    if [[ ! "$block_deletion" ]] && [[ -d "$artifacts_dir" ]]; then
        if ! output="$(rm -rf "$artifacts_dir")"; then
            log_error "Unable to delete the old artifacts directory [${artifacts_dir}]: $output"
            return 1
        fi
    fi
    if ! output="$(mkdir -p "$artifacts_dir")"; then
        log_error "Unable to make artifacts directory [${artifacts_dir}]: $output"
        return 1
    fi
}


# Prepares and creates the artifacts directory under artifacts/. The generated path typically
# looks like:
#   artifacts/BIGIP-15.0.0/aws/ltm_1slot/
#   artifacts/BIGIP-14.0.0/gce/all_2slot/
function prepare_artifacts_directory {
    if [[ $# -ne 4 ]]; then
        log_error "Usage: ${FUNCNAME[0]} <iso> <modules> <boot_locations> <platform>"
        return 1
    fi
    local iso="$1"
    local modules="$2"
    local boot_locations="$3"
    local platform="$4"
    local script_dir
    script_dir="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"

    # drop the path and .iso extension from the iso name
    iso=$(basename "$iso" .iso)

    # Create the artifacts directory.
    local artifacts_directory
    if [[ "$platform" == "iso" ]]; then
        artifacts_directory="${script_dir}/../../../artifacts/${iso}/${platform}"
    else
        artifacts_directory="${script_dir}/../../../artifacts/${iso}/${platform}/${modules}_${boot_locations}slot"
    fi

    # Save the generated value.
    set_config_value "ARTIFACTS_DIR" "$artifacts_directory"

    # create the directory
    local reuse
    reuse="$(get_config_value "REUSE")"
    create_artifacts_directory "$reuse"
}


# extract VERSION file from the full iso or VERSION.LTM from the ehf iso
# parse the file (set some global variables)
# create metadata filter files for version file
# return 0 if passed; otherwise exit with 1
function extract_bigip_product_info_from_iso {
    local iso="$1"
    local ehf_flag="$2"
    local version_file="$3"
    local artifacts_directory="$4"
    if [[ $# -ne 4 ]]; then
        error_and_exit "Received a wrong number ($#) of parameters: $*"
    fi

    local iso_path_prefix
    if [[ -z "$ehf_flag" ]]; then
        # full iso
        iso_path_prefix="$(extract_bigip_prefix_from_iso "$iso")"
    else
        # ehf iso
        iso_path_prefix="" # the version file is at the top in the ehf iso
    fi

    # extract version file
    rm -f "$artifacts_directory/$version_file"
    if ! extract_file_from_iso "$iso" "$iso_path_prefix/$version_file" \
        "$artifacts_directory/$version_file" ; then
        error_and_exit "Failed to extract '$version_file' from '$iso'."
    fi

    parse_version_file "$artifacts_directory/$version_file"
}


# extract VERSION file from iso and parse it (set some global variables)
# create metadata filter files for VERSION file
# return 0 if passed; otherwise exit with 1
function extract_bigip_version_file_from_iso {
    local iso="$1"
    local ehf_flag="$2"
    local create_metadata_flag="$3"
    local artifacts_directory="$4"
    if [[ $# -ne 4 ]]; then
        error_and_exit "Received a wrong number ($#) of parameters: $*"
    fi

    local version_file
    if [[ -z "$ehf_flag" ]]; then
        version_file="VERSION"
    else
        version_file="VERSION.LTM"
    fi

    extract_bigip_product_info_from_iso "$iso" "$ehf_flag" "$version_file" "$artifacts_directory"

    if [[ -n "$create_metadata_flag" ]]; then
        create_version_file_metadata "$artifacts_directory" "$artifacts_directory/$version_file"
    fi
    rm -f "$artifacts_directory/$version_file"
}


# Extract version file from the full iso (and ehf iso).
# Check compatibility of the full iso and ehf iso, if applicable.
# Create metadata filter files for the version file.
function check_version_file {
    local full_iso="$1"
    local ehf_iso="$2"
    local artifacts_directory="$3"
    if [[ $# -ne 3 ]]; then
        error_and_exit "Received a wrong number ($#) of parameters: $*"
    fi

    if [[ -z "$ehf_iso" ]]; then
        extract_bigip_version_file_from_iso "$full_iso" "" "create metadata flag" "$artifacts_directory"
    else
        extract_bigip_version_file_from_iso "$full_iso" "" "" "$artifacts_directory"
        local full_iso_product_name="$PRODUCT_NAME"
        local full_iso_product_build="$PRODUCT_BUILD"
        local full_iso_product_version="$PRODUCT_VERSION"

        extract_bigip_version_file_from_iso "$ehf_iso" "ehf flag" "create metadata flag" "$artifacts_directory"
        if [[ "$full_iso_product_name" != "$PRODUCT_NAME" ]]; then
            error_and_exit "Product names of full and EHF ISOs do not match: $full_iso_product_name vs $PRODUCT_NAME"
        fi
        if [[ "$full_iso_product_version" != "$PRODUCT_VERSION" ]]; then
            error_and_exit "Product versions of full and EHF ISOs do not match: $full_iso_product_version vs $PRODUCT_VERSION"
        fi
        if [[ "$full_iso_product_build" != "$PRODUCT_BASE_BUILD" ]]; then
            error_and_exit "Product build of full ISO and product base build of EHF ISO do not match: $full_iso_product_build vs $PRODUCT_BASE_BUILD"
        fi
    fi
}


# extract ve.info.json from iso if one exists. If not, looks at the BIG-IP version being installed
# to determine if there are relevant legacy ve.info.json files that can be used.
# return 0 if successful; otherwise exits with 1.
function extract_ve_info_file_from_iso {
    local iso="$1"
    local artifacts_directory="$2"
    local ve_info_json="$3"
    if [[ $# -ne 3 ]]; then
        error_and_exit "Received a wrong number ($#) of parameters: $*"
    fi

    local iso_path_prefix
    iso_path_prefix="$(extract_bigip_prefix_from_iso "$iso")"

    # extract ve.info.json
    if ! extract_file_from_iso "$iso" "$iso_path_prefix/install/$ve_info_json" \
            "$artifacts_directory/$ve_info_json" ; then
        local script_dir
        script_dir="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"

        if [[ $BIGIP_VERSION_NUMBER -ge 13010002 ]] && 
                [[ $BIGIP_VERSION_NUMBER -lt 14010000 ]] ; then
            log_debug "Using legacy ve.info.json compatible with version '$PRODUCT_VERSION'."
            # Use the compatible ve.info.json for 13.1.0.2 <= version < 14.1.0
            cp -v "${script_dir}/../../resource/ve_info/13.1.0.2-ve.info.json" \
                "$artifacts_directory/$ve_info_json"
        elif [[ $BIGIP_VERSION_NUMBER -ge 14010000 ]]; then
            log_debug "Using legacy ve.info.json compatible with version '$PRODUCT_VERSION'."
            # Use the compatible ve.info.json for version >= 14.1.0
            cp -v "${script_dir}/../../resource/ve_info/14.1.0-ve.info.json" \
                "$artifacts_directory/$ve_info_json"
        else
            error_and_exit "Unsupported BIG-IP version '$BIGIP_VERSION_NUMBER'."
        fi
    fi
    if [[ ! -s "$artifacts_directory/$ve_info_json" ]]; then
        error_and_exit "Couldn't extract '$ve_info_json' from '$iso' and no compatible" \
                "legacy '$ve_info_json' exists."
    fi
}


# Convert the BIG-IP Version String in to an 8-digit number for easy comparisons.
#
# RETURNS:
#       BIG-IP Version in format like 12000000 (for 12.0.0) as output.
#
# Reads VersionInfo.json file and converts 'version_version' string into an 8-digit
# number. Regardless of the number of '.' components in the version (i.e. 13.0.0 or
# 14.1.2.1), this routine always returns the version number assuming there were 4
# version components in version_version with 2 digits each.
# For the missing components on the right, it pads 0s and so 12.0.0 becomes
# 12000000. As can be seen, for the 2nd and 3rd component, an extra '0' is
# padded as well as the fourth missing component has been added as 00 on the
# right.
# Output examples:
#   "14.0.0"            =>  14000000
#   "13.1.0"            =>  13010000
#   "11.5.14"           =>  11051400
#   "12.1.1.2"          =>  12010102
#   "12.1.1.1.1.1.1.2"  =>  12010101
#
function get_release_version_number {
	local version_file="$1"

    if [[ -z "$version_file" ]]; then
		log_error "Usage: ${FUNCNAME[0]} <version_file>"
        return 1
	elif [[ ! -f "$version_file" ]]; then
        log_error "$version_file is missing."
        return 1
    fi

    local version_string
    version_string=$(jq -r '.version_version' "$version_file")
    if [[ -z "$version_string" ]]; then 
        log_error "Failed to read .version_version from '$version_file'"
        return 1
    fi

    local ret_array=()
    # Split the version_string based on '.' as the separator
    IFS='.' read -r -a ret_array <<< "${version_string}"

    local temp=""
    local rel_version=""
    local num_of_elements=4
    # Regardless of the number of elements in ret_array, always loop through
    # 4 times as we are only interested in the first 4 components. For a 3
    # element array, the 4th time this loop will run with an empty string thus
    # padding two 0s.
    local i
    for ((i = 0 ; i < num_of_elements ; i++));
    do  
        temp=$(printf "%02d" "${ret_array[$i]}")
        rel_version="${rel_version}${temp}"
    done
    echo "${rel_version}"
}


# validate that iso version is supported by the tool for the specified platform
function validate_iso_version {
    local platform="$1"

    if [[ $# -ne 1 ]]; then
        error_and_exit "Usage: ${FUNCNAME[0]} <platform>"
    elif ! is_supported_platform "$platform"; then
        error_and_exit "Unsupported platform '$platform'"
    fi

    local floor_release
    case "$platform" in
        alibaba) # alibaba is supported starting v14.1.0.3
            floor_release=14010003
            ;;
        *) # all other platforms have been supported at least starting v13.1.0.2
            floor_release=13010002
            ;;
    esac

    if [[ $BIGIP_VERSION_NUMBER -lt $floor_release ]]; then
        error_and_exit "Platform '$platform' is supported starting release $floor_release," \
            "but iso version is $BIGIP_VERSION_NUMBER."
    fi
}


# find out path for iso with updated rpms and print it
function form_updated_iso_path {
    local platform="$1"
    local iso="$2"
    local cloud_image_name="$3"
    local artifacts_directory="$4"

    if [[ $# -ne 4 ]]; then
        error_and_exit "Usage: ${FUNCNAME[0]} <platform> <iso> <cloud_image_name> <artifacts_directory>"
    elif ! is_supported_platform "$platform"; then
        error_and_exit "Unsupported platform '$platform'"
    fi

    local updated_iso_path
    if [[ "$platform" == "iso" ]] && [[ -n "$cloud_image_name" ]]; then
        updated_iso_path="$artifacts_directory/$cloud_image_name"
    else
        updated_iso_path="$artifacts_directory/updated-$(basename "$iso")"
    fi
    echo "$updated_iso_path"
}


# creates the disk name based on the given parameters. For RAW
# GCE disk, it returns disk.raw as the default name.
#
function create_disk_name {
    local format="$1"
    local product="$2"
    local version="$3"
    local build="$4"
    local platform="$5"
    local modules="$6"
    local boot_loc="$7"
    local project_name="$8"
    local ehf_iso="$9"
    local img_tag="${10}"

    if [[ $# -lt 7 ]]; then
        error_and_exit "Usage: ${FUNCNAME[0]} <format> <product> <version> <build>" \
                "<platform> <modules> <boot_loc> <project-name> <ehf_iso> <img_tag>"
    elif ! is_supported_platform "$platform"; then
        error_and_exit "Unsupported platform '$platform'"
    elif ! is_supported_module "$modules"; then
        error_and_exit "Unknown module '$modules'."
    elif ! is_supported_boot_locations "$boot_loc"; then
        error_and_exit "Unsupported boot locations '$boot_loc'."
    fi

    # For the GCE raw disk, it accepts only disk.raw as file name:
    if [[ "$platform" == "gce" ]] && [[ "$format" == "raw" ]]; then
        echo "disk.raw"
        return
    fi

    # Start assembling the image name --
    # -- fixed prefix
    local output="$product"

    # -- Project is optional
    if [[ -n "$project_name" ]]; then
        output="$output-$project_name"
    fi

    # -- optional custom tag
    if [[ -n "$img_tag" ]]; then
        output="$output-$img_tag"
    fi

    # -- EHF marker
    local ehf_marker
    ehf_marker="$(form_ehf_marker "$ehf_iso")"

    local sizing_type
    sizing_type="$(get_modules_production_name "$modules" "$boot_loc")"

    # -- fixed suffix
    output="$ehf_marker$output-$version-$build.$sizing_type.$platform.$format"
    echo "$output"
}


# Checks for the KVM support in the host and exports OPTION_KVM_ENABLED global
# variable for later use.
#
function check_kvm_support {
    OPTION_KVM_ENABLED=""
    if [[ -r /proc/cpuinfo ]]; then
        local kvm_enabled_cpus
        kvm_enabled_cpus="$(grep -c -E "svm|vmx" /proc/cpuinfo)" || true
        if [[ $kvm_enabled_cpus -gt 0 ]] ; then
            OPTION_KVM_ENABLED="-enable-kvm"
            log_info "CPU supports virtualization."
        else
            log_warning "-----------------------------------------------------------------------------"
            log_warning "CPU does not support virtualization, bundle generation will be slow."
            log_warning "-----------------------------------------------------------------------------"
        fi
    fi
    export OPTION_KVM_ENABLED
}


# Encapsulates the steps for virtual disk generation 
#
function produce_virtual_disk {
    local platform="$1"
    local modules="$2"
    local boot_locations="$3"
    local input_raw_disk="$4"
    local artifacts_dir="$5"
    local prepare_vdisk_json="$6"
    local staged_disk="$7"
    local log_file="$8"
    local script_dir
    script_dir="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"

    if [[ $# -lt 8 ]]; then
        error_and_exit "Received a wrong number ($#) of parameters: $*"
    fi

    local staging_dir
    staging_dir="$(realpath "$(dirname "$staged_disk")")"
    mkdir -p "$staging_dir"
    log_info "Staging virtual disk at: $staged_disk":

    local internal_disk_name
    internal_disk_name="$(compose_internal_disk_name "$PRODUCT_NAME" \
            "$PRODUCT_VERSION" "$PRODUCT_BUILD" "$PROJECT_NAME")"

    input_raw_disk="$(basename "$input_raw_disk")"
    case $platform in
        vmware | aws)
            # shellcheck disable=SC2094
            bash "${script_dir}/../../bin/ova_package_disk" "$platform" "$input_raw_disk" \
                    "$artifacts_dir" "$internal_disk_name" "$staged_disk" \
                    "$prepare_vdisk_json" "$log_file"
            ;;
        alibaba)
            # shellcheck disable=SC2094
            bash "${script_dir}/../../bin/alibaba_package_disk" "$input_raw_disk" "$staged_disk" "$artifacts_dir" \
                    "$prepare_vdisk_json"
            ;;
        gce)
            # shellcheck disable=SC2094
            bash "${script_dir}/../../bin/gce_package_disk" "$input_raw_disk" "$artifacts_dir" "$staged_disk" \
                    "$prepare_vdisk_json" "$log_file"
            ;;
        azure | vhd)
            # shellcheck disable=SC2094
            bash "${script_dir}/../../lib/bash/prepare_vhd.sh" "$platform" "$input_raw_disk" "$artifacts_dir" \
                    "$internal_disk_name" "$staged_disk" "$prepare_vdisk_json" "$log_file"
            ;;
        qcow2)
            # shellcheck disable=SC2094
            bash "${script_dir}/../../bin/prepare_qcow2" "$input_raw_disk" "$staged_disk" \
                    "$artifacts_dir" "$prepare_vdisk_json"
            ;;
        *)
            error_and_exit "Unhandled platform=$platform"
    esac
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]]; then
        error_and_exit "Packaging virtual disk failed."
    fi
}


# Verifies that there is enough disk space to complete the run
function verify_disk_space {
    local min_free_disk_storage_MB
    min_free_disk_storage_MB="$(get_config_value "MIN_FREE_DISK_STORAGE_MB")" 
    local space_remaining
    space_remaining=$(df -B M ./ | awk '{ print $4 }' | sed -n '2 p')

    if [[ "$space_remaining" == *M* ]]; then
        space_remaining="${space_remaining::-1}"
    fi

    if (( space_remaining < min_free_disk_storage_MB )); then
        error_and_exit "At least $min_free_disk_storage_MB MB storage needed. Only $space_remaining MB found"
    fi
}


# Perform ISO verifications including file checks, public key checks, signature file default fallback, signature file
# checks, and signature verification.
# returns
# 0 - if the iso is not present, or the verification passed
# 1 - if the verification failed, or iso is not accessible
# 2 - if image verification skipped due to missing signature or key
function verify_iso {
    local iso="$1"
    local iso_sig="$2"
    local pub_key="$3"
    local encryption_type="$4"

    # If there's no ISO then we don't need to verify anything.
    if [[ -z "$iso" ]]; then
        return 0
    fi

    # If the provided ISO isn't accessible then the program won't work.
    if [[ ! -f "$iso" ]]; then
        log_error "Provided ISO file [${iso}] is inaccessible!  Unable to perform operation(s)."
        return 1
    fi

    local missing_signature_or_key
    # If no public key is present then we'll skip verification.
    if [[ -z "$pub_key" ]] || [[ ! -f "$pub_key" ]]; then
        log_warning "Missing public key! Please provide \
ISO_SIG_VERIFICATION_PUBLIC_KEY or IMAGE_SIG_PUBLIC_KEY as \
a path to the public key to enable signature verification!"
        missing_signature_or_key="true"
    fi

    # If the user didn't provide a signature file then we'll check for the default one next to the ISO.
    if [[ -z "$iso_sig" ]]; then
        log_warning "ISO signature file was not provided, trying to find the signature file \
from hashing type"
        sig_ext=$(get_sig_file_extension "$encryption_type")
        iso_sig="${iso}${sig_ext}"
    fi

    # If the user didn't provide an encryption type, then we can't perform verification.
    if [[ -z "$encryption_type" ]]; then
        log_warning "Missing ISO signature verification encryption type [${encryption_type}]!"
        missing_signature_or_key="true"
    fi

    # If the signature file is inaccessible then we can't perform verification.
    if [[ ! -f "$iso_sig" ]]; then
        log_warning "Missing ISO signature file [${iso_sig}]!"
        missing_signature_or_key="true"
    fi

    # iso signature or public key is missing
    if [[ -n "$missing_signature_or_key" ]]; then
        log_warning "Skipping signature verification for ISO [${iso}]."
        return 2
    fi

    # Perform signature verification.
    local output
    if ! output=$(openssl dgst -"${encryption_type}" -verify "$pub_key" -signature "$iso_sig" "$iso" 2>&1) ; then
        log_error "Signature verification for ISO [${iso}] with signature file [${iso_sig}] using public key \
[${pub_key}] and encryption type [${encryption_type}] failed with output: $output"
        return 1
    fi

    log_info "Successfully verified ISO [${iso}] with signature file [${iso_sig}] using public key [${pub_key}] \
and encryption_type [${encryption_type}]"
}

# Copy image and its md5 to the publishing location
# md5 file must be alongside the image and have matching path: <iso_path>.md5
# signature_file_path can be empty
# publishing location must exist
function publish_image {
    image_path="$1"
    sig_file_path="$2"
    publish_dir="$3"
    image_description="$4"

    if [[ $# -ne 3 ]] && [[ $# -ne 4 ]]; then
        error_and_exit "${FUNCNAME[0]} received $# parameters instead of 3 or 4: $*"
    fi

    if [[ ! -d "$publish_dir" ]]; then
        error_and_exit "Publishing directory $publish_dir does not exist"
    fi

    log_info "Copying $image_description [${image_path}] and its MD5 to [${publish_dir}]"
    if ! execute_cmd cp -f "$image_path" "$publish_dir"; then
        error_and_exit "Failed to copy $image_description [${image_path}] to [${publish_dir}]!"
    elif ! cp -f "$image_path".md5 "$publish_dir"; then
        error_and_exit "Failed to copy $image_description MD5 [${image_path}] to [${publish_dir}]!"
    fi

    if [[ -n "$sig_file_path" ]]; then
        log_info "Copying $sig_file_path to [${publish_dir}]"
        if ! cp -f "$sig_file_path" "$publish_dir"; then
            error_and_exit "Failed to copy $sig_file_path to [${publish_dir}]!"
        fi
    fi
}

# Check that the setup script has run.
#
# Note: This script runs before the logger has been initialized, so log level text is required.
function check_setup {
    local num_args=1
    local check_setup_json_dir="$1"
    if [[ $# -ne $num_args ]]; then
        error_and_exit "${FUNCNAME[0]} received $# arguments, but was expecting $num_args"
    fi
    log_info "Check that the setup script has been run."

    # There are a number of conditions that will be flagged, but the message to the user will
    # be the same.
    local setup_script="setup-build-env"
    local error_msg="Error: Run ${setup_script} before running build-image."

    # Check check setup json file directory exists
    if [[ ! -d "$check_setup_json_dir" ]]; then
        log_warning "Setup json directory $check_setup_json_dir doesn't exist"
        log_warning "Warning: The ${setup_script} script must be run when creating a workspace."
        error_and_exit "$error_msg"
    fi

    # Check check setup json file exists
    local info_file="${check_setup_json_dir}/.${setup_script}.json"
    if [[ ! -f "$info_file" ]]; then
        log_warning "Setup json file $info_file doesn't exist"
        log_warning "Warning: The ${setup_script} script must be run when creating a workspace."
        error_and_exit "$error_msg"
    fi

    # Get the version associated with the setup script run
    local json_read
    json_read="$(<"$info_file")"
    if ! setup_version="$(jq -r '.VERSION // empty' <<< "$json_read" 2>&1)"; then
        error_and_exit "jq error while retrieving VERSION from json data: $json_read from $info_file"
    fi

    # Look up current generator version
    local current_version
    current_version="$(get_config_value "VERSION_NUMBER")"

    if [[ "$setup_version" != "$current_version" ]]; then
        log_warning "Warning: The ${setup_script} script must be run after updating a workspace."
        log_warning "Warning: Setup version:$setup_version does not match current version:$current_version."
        error_and_exit "$error_msg"
    fi

    log_info "The setup script has been run for version:$current_version."
}

# Create/overwrite generator-info.json file.
function create_generator_info_json {
    # Form path of generator-info file.
    local artifacts_dir
    artifacts_dir="$(get_config_value "ARTIFACTS_DIR")"
    local info_file="${artifacts_dir}/generator-info.json"

    # Delete the old file.
    if [[ -f "$info_file" ]]; then
        if ! output="$(rm -f "$info_file")"; then
            error_and_exit "Unable to delete '${info_file}': $output"
        fi
    fi

    # Look up current generator version.
    local current_version
    current_version="$(get_config_value "VERSION_NUMBER")"

    # Create the new file.
    local json_write
    log_info "Creating generator info file with generator version $current_version"
    if ! json_write="$(jq -n --arg v "$current_version" '{"VERSION": $v}' 2>&1)"; then
        error_and_exit "jq error while adding VERSION to json data: $json_write"
    fi
    echo "$json_write" > "$info_file"
}

# Perform logic for handling an upgrade to a new image generator version. This will check the
# generator-info.json file in the artifacts directory (if it exists). If the version specified in
# this file doesn't match the current image generator version then the REUSE variable will be
# overriden and set to false. This is done since changes in logic between versions could cause
# errors if existing artifacts were reused.
function handle_upgrade {

    # Parse arguments
    num_args=1
    if [[ $# -ne $num_args ]]; then
        error_and_exit "${FUNCNAME[0]} received $# arguments, but was expecting $num_args"
    fi
    artifacts_dir=$1
    local info_file json_read json_write last_version current_version reuse

    # Look up current generator version
    current_version="$(get_config_value "VERSION_NUMBER")"

    # Check for presense of generator-info file
    info_file="${artifacts_dir}/generator-info.json"
    if [[ -f "$info_file" ]]; then

        # The info file exists, so we'll check the last generator version that was used for this build
        json_read="$(<"$info_file")"
        if ! last_version="$(jq -r '.VERSION // empty' <<< "$json_read" 2>&1)"; then
            error_and_exit "jq error while retrieving VERSION from json data: $json_read"
        fi

        if [[ "$last_version" == "$current_version" ]]; then
            # The last version matches the current version, so we don't have to do anything
            log_info "Generator info version matches current version $current_version"
            return 0
        else
            # The image generator version has changed since the last image generator run of this build, so we'll
            # override the reuse variable and update the file with the current version
            log_info "Generator version has been updated from $last_version to $current_version since the last run"
            reuse="$(get_config_value "REUSE")"
            if [[ -n "$reuse" ]]; then
                log_info "Ignoring 'REUSE' setting for this build since files generated by an older generator version may not be reused."
            fi
        fi
    fi

    # We are here because the artifacts directory either was just (re)created or
    # was created with the old version of the tool or enexpectedly generator version file is missing.
    # So it should be unconditially recreated.
    create_artifacts_directory ""
    # Recreate a new generator-info file.
    create_generator_info_json
}


# Publish to telemetry server unless disable telemetry config value is enabled
function publish_telemetry {
    if [[ -n "$(get_config_value "DISABLE_TELEMETRY")" ]]; then
        log_info "Telemetry feature disabled. Telemetry data was not posted."
	return
    fi

    build_end_time="$(date "+%FT%H:%M:%S")"
    result="$1"
    artifacts_directory="$2"

    telemetry_end_file="$artifacts_directory/telemetry_end.json"
    if ! jq -M -n \
          --arg build_end_time "$build_end_time" \
          --arg result "$result" \
        '{ build_end_time: $build_end_time,
    	result: $result }' \
        > "$telemetry_end_file"
    then
        log_error "jq failed to create document."
        log_error "Removing file $telemetry_end_file"
        rm "$telemetry_end_file"
        exit 1
    fi
    "$(realpath "$(dirname "${BASH_SOURCE[0]}")")"/../../bin/publish_telemetry.py
}


# Take a snapshot of the working space for the postmortem analysis.
# The snapshot will include the log file and text files from the artifacts dir.
# The snapshot will reside next to the log.
function take_snapshot {
    log_debug "Taking the snapshot of the workspace."

    # Create the snapshot file next to the log file.
    local log_file
    log_file=$(get_config_value "LOG_FILE")
    if [[ -z "$log_file" ]]; then
        log_debug "Log file has not been set. Cannot collect snapshots."
        return 1
    fi

    local snapshot
    snapshot="${log_file}.snapshot.zip"
    if ! rm -f "$snapshot"; then
        log_warning "Failed to delete $snapshot"
        return 1
    fi

    # Add the log file to the snapshot file.
    if ! zip -qr "$snapshot" "$log_file"; then
        log_warning "Failed to add $log_file to $snapshot"
        return 1
    fi

    # Add the list of the artifacts files to the snapshot file.
    local artifacts_dir
    artifacts_dir=$(get_config_value "ARTIFACTS_DIR")
    if [[ -d "$artifacts_dir" ]]; then
        local file_list
        file_list="$artifacts_dir/files.txt"
        if ! du -a "$artifacts_dir" > "$file_list"; then
            log_warning "Failed to execute du for $artifacts_dir"
            return 1
        fi

        if ! zip -qr "$snapshot" "$file_list"; then
            log_warning "Failed to add $file_list to $snapshot"
            return 1
        fi

        # Add text artifact files to the snapshot file.
        # shellcheck disable=SC2034
        while IFS=$'\t' read -r file_size file_name
        do
            if [[ "text" == $(file -b --mime-type "$file_name" | sed 's|/.*||') ]]; then
                if ! zip -qr "$snapshot" "$file_name"; then
                    log_warning "Failed to add $file_name to $snapshot"
                    return 1
                fi
            fi
        done < "$file_list"
    fi

    log_debug "The snapshot of the workspace is ready and located at $snapshot"
}
