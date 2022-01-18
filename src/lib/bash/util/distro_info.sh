#!/bin/bash
# Copyright (C) 2019-2021 F5 Networks, Inc
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



# Outputs a concatenated name and version for the current Linux distribution.
function get_distro {
    local distro_name="unknown"
    local distro_version=""
    if [[ -f "/etc/os-release" ]]; then
        # shellcheck disable=SC1091
        source "/etc/os-release"
        distro_name="${ID,,}"
        distro_version="${VERSION_ID,,}"
    elif [[ -f "/etc/lsb-release" ]]; then
        # shellcheck disable=SC1091
        source "/etc/lsb-release"
        distro_name="${DISTRIB_ID,,}"
        distro_version="${VERSION_RELEASE,,}"
    fi
    echo "${distro_name}${distro_version}"
}

# Checks if a specific Linux distribution and version are supported by the tool.  If no argument is
# specified then it will automatically determine the current Linux distribution.  Return 0 if the
# distro is supported or 1 if it's not.
function is_supported_distro {
    local distro="$1"
    local supported=1
    if [[ -z "$distro" ]]; then
        distro="$(get_distro)"
    fi
    case "$distro" in
        "ubuntu18.04")
            supported=0
            ;;
        "ubuntu20.04")
            supported=0
            ;;
	"alpine3.11.5")
            supported=0
	    ;;
    esac
    return "$supported"
}
