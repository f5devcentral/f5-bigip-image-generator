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


# shellcheck disable=SC2119,SC2120
# init_config takes either "$@", "validate + $@", or nothing.

# shellcheck source=src/lib/bash/util/logger.sh
source "$(realpath "$(dirname "${BASH_SOURCE[0]}")")/logger.sh"

# This function clears the arrays used to store the configuration details
function _clear_config_arrays {
    unset CONFIG_ACCEPTED
    unset CONFIG_CONFIGURABLE
    unset CONFIG_DEFAULTS
    unset CONFIG_DESCRIPTIONS
    unset CONFIG_DIRECT_EXPORT
    unset CONFIG_FLAGS
    unset CONFIG_FLAGS_REVERSE
    unset CONFIG_HIDDEN
    unset CONFIG_OPTIONAL
    unset CONFIG_PARAMETERS
    unset CONFIG_PROTECTED
    unset CONFIG_REQUIRED
    unset CONFIG_VALUES
}

# This function initializes the arrays used to store the configuration details
function _init_config_arrays {
    declare -gA CONFIG_ACCEPTED      # KEY: Variable name    # VALUE: List of accepted value regex strings
    declare -gA CONFIG_CONFIGURABLE  # KEY: Variable name    # VALUE: 1 indicates that the variable is configurable
    declare -gA CONFIG_DEFAULTS      # KEY: Variable name    # Value: Default value to use when not configured
    declare -gA CONFIG_DESCRIPTIONS  # KEY: Variable name    # VALUE: Variable description
    declare -gA CONFIG_DIRECT_EXPORT # KEY: Variable name    # VALUE: 1 indicates that the variable should be exported
    declare -gA CONFIG_FLAGS         # KEY: Variable name    # VALUE: Flag character associated with the variable
    declare -gA CONFIG_FLAGS_REVERSE # KEY: Single character # VALUE: Variable name that flag is associated with
    declare -gA CONFIG_FILES         # KEY: YAML file path   # VALUE: Contents of the file converted to JSON data
    declare -gA CONFIG_HIDDEN        # KEY: Variable name    # VALUE: 1 indicates that the variable is hidden
    declare -gA CONFIG_OPTIONAL      # KEY: Variable name    # VALUE: 1 indicates that the variable is optional
    declare -gA CONFIG_PARAMETERS    # KEY: Variable name    # VALUE: Number of expected arguments for variable
    declare -gA CONFIG_PROTECTED     # KEY: Variable name    # VALUE: 1 indicates that the variable is protected
    declare -gA CONFIG_REQUIRED      # KEY: Variable name    # VALUE: 1 indicates that the variable is required
    declare -gA CONFIG_VALUES        # KEY: Variable name    # VALUE: Variable value
}

# This is the function used to launch the config system.  It can either be called manually (IE: at program start) or
# automatically when get_config_value or set_config_value need the system to be initialized.  When calling this function
# manually the first argument can be set to "validate".  This will ensure that validations are performed on all of the
# provided values.  Subsequent arguments will be treated as if they were passed in on the command line at program start.
function init_config {
    # We only need to initialize the system once, so we'll return if that's already been done.
    if [[ -n "$CONFIG_SYSTEM_INITIALIZED" ]]; then
        return 0
    fi

    # Check first argument to see if we need to validate at the end.
    local validate
    if [[ "$1" == "validate" ]]; then
        validate="true"
        shift
    fi

    _init_config_arrays
    export CONFIG_SYSTEM_INITIALIZED=1

    # Load shared definitions for variables.
    log_info "Initializing global variable definitions"
    local script_dir
    script_dir="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
    _config_init_var_definitions "${script_dir}/../../../resource/vars/shared_vars.yml"

    # Initialize the ENVIRONMENT_VARIABLE_PREFIX key so we can start looking for values from the environment.
    _config_init_bootstrap_key "ENVIRONMENT_VARIABLE_PREFIX" "$@"

    # If a config file was specified then we'll validate that it's accessible.
    _config_init_bootstrap_key "CONFIG_FILE" "$@"
    local config_file="${CONFIG_VALUES[CONFIG_FILE]}"
    if [[ -n "$config_file" && ! -f "$config_file" ]]; then
        error_and_exit "CONFIG_FILE [${config_file}] is inaccessible!"
    fi

    # If the version key has been set then we'll immediately look for the version number, display it, and exit.
    _config_init_bootstrap_key "VERSION" "$@"
    if [[ -n "${CONFIG_VALUES[VERSION]}" ]]; then
        _config_init_bootstrap_key "VERSION_NUMBER" "$@"
        _config_output_version
        exit 0
    fi

    _config_init_bootstrap_key "INFO" "$@"
    if [[ -n "${CONFIG_VALUES[INFO]}" ]]; then
        _config_output_info
        exit 0
    fi

    if [[ -z "$config_file" ]]; then
        log_info "CONFIG_FILE not set"
    fi

    # If a platform was specified then we'll load variable definitions for it.
    _config_init_bootstrap_key "PLATFORM" "$@"
    local platform="${CONFIG_VALUES[PLATFORM]}"
    if [[ -n "$platform" ]]; then
        log_info "Initializing variable definitions for platform [${platform}]"
        if [[ "$platform" != "iso" ]]; then
            # iso alternations are independent of modules and boot locations
            _config_init_var_definitions "${script_dir}/../../../resource/vars/vm_vars.yml"
        fi
        if [[ "$platform" =~ ${CONFIG_ACCEPTED[CLOUD]} ]]; then
            # If the specified platform is a cloud then we'll also set the CLOUD variable.
            set_config_value "CLOUD" "$platform"
        fi
        _config_init_bootstrap_key "NO_UPLOAD" "$@"
        local no_upload
        no_upload="$(get_config_value "NO_UPLOAD")"
        local cloud
        cloud="$(get_config_value "CLOUD")"
        if [[ -n "$cloud" ]]; then
            if [[ -n "$no_upload" ]]; then
                log_info "The cloud image will be created but not uploaded, due to the --no-upload parameter."
            else
                _config_init_var_definitions "${script_dir}/../../../resource/vars/${platform}_vars.yml"
            fi
        else
            _config_init_var_definitions "${script_dir}/../../../resource/vars/${platform}_vars.yml"
            if [[ -n "$no_upload" ]]; then
                error_and_exit "$platform is not a cloud, and --no-upload parameter should not be used. Use --help to view the help."
            fi
        fi
    else
        log_info "PLATFORM not set"
    fi

    # If the help key has been set then we'll immediately display help and exit.
    _config_init_bootstrap_key "HELP" "$@"
    if [[ -n "${CONFIG_VALUES[HELP]}" ]]; then
        _config_output_help
        exit 0
    fi

    # Perform remaining initialization.
    _config_export_accepted_values
    _config_export_protected_values
    _config_parse_command_line_arguments 1 "$@"
    _config_parse_config_file_values
    _config_read_variables_from_environment
    _config_assign_defaults_from_definitions

    # If the docs key has been set then we'll generate config docs and exit.
    if [[ -n "${CONFIG_VALUES[DOCS]}" ]]; then
        _config_output_docs
        exit 0
    fi

    # Perform validation, if requested.
    if [[ -n "$validate" ]]; then
        _config_validate_required_variables
    fi

    # We're done!
    log_info "Configuration was successfully initialized"
}

# Look up the accepted values for a provided key.  Return code of 1 indicates that the value was empty.
function get_config_accepted {
    # Confirm that a key was provided.
    local key="${1^^}"
    key="$(echo "$key" | tr - _)"
    if [[ -z "$key" ]]; then
        error_and_exit "Unable to perform config lookup for empty key!"
    fi

    # Ensure that the config system has been initialized.
    init_config >> /dev/null

    # Look up the corresponding accepted regex for the provided key using the config system prefix.
    local env_prefix="$ENVIRONMENT_VARIABLE_PREFIX"
    local accepted_prefix="ACCEPTED_"
    local env_key="${env_prefix}${accepted_prefix}${key}"
    local value="${!env_key}"
    echo "$value"
}

# Look up the value for a specified key using the config system.  Return code of 1 indicates that the value was empty.
function get_config_value {
    # Confirm that a key was provided.
    local key="${1^^}"
    key="$(echo "$key" | tr - _)"
    if [[ -z "$key" ]]; then
        error_and_exit "Unable to perform config lookup for empty key!"
    fi

    # Ensure that the config system has been initialized.
    init_config >> /dev/null

    # Look up the corresponding value for the provided key using the config system prefix.
    local prefix="$ENVIRONMENT_VARIABLE_PREFIX"
    local env_key="${prefix}${key}"
    local value="${!env_key}"
    echo "$value"
}

# Set the value for a specified key using the config system.
function set_config_value {
    # Confirm that a key was provided.
    local key="${1^^}"
    key="$(echo "$key" | tr - _)"
    if [[ -z "$key" ]]; then
        error_and_exit "Unable to set value for empty key!"
    fi

    # Ensure that the config system has been initialized.
    init_config

    # Set the corresponding value for the provided key using the config system prefix.
    local value="$2"
    local prefix="$ENVIRONMENT_VARIABLE_PREFIX"
    local env_key="${prefix}${key}"
    local -n env_key_ref="$env_key"
    export env_key_ref="$value"
    CONFIG_VALUES[${key}]="$value"
    local protected="${CONFIG_PROTECTED[${key}]}"
    if [[ -n "$protected" ]]; then
        log_debug "Configuration key [$key] set to value [<protected>]"
    else
        log_debug "Configuration key [$key] set to value [$value]"
    fi

    # If the direct export flag was set for this variable then we'll also export it without the prefix.
    local direct_export="${CONFIG_DIRECT_EXPORT[${key}]}"
    if [[ -n "$direct_export" ]]; then
        local -n key_ref="$key"
        export key_ref="$value"
        log_debug "Configuration key [$key] exported to environment"
    fi
}


# ======== THE FOLLOWING FUNCTIONS ARE INTERNAL TO THIS SCRIPT AND SHOULD NOT BE CALLED EXTERNALLY ======== #


# Here we'll assign default values to variables which have not been configured.  We'll load the default values from our
# own internal definitions, if present.
function _config_assign_defaults_from_definitions {
    log_info "Assigning default values to eligible variables"
    local key
    for key in "${!CONFIG_DEFAULTS[@]}"; do
        local value="${CONFIG_VALUES[${key}]}"
        if [[ -z "$value" ]]; then
            # Note that we don't use set_user_value here because default values come from internal definitions which
            # don't need to be validated.
            local default=${CONFIG_DEFAULTS[${key}]}
            set_config_value "$key" "$default"
        fi
    done
}

# Some of our internal code needs access to the accepted value strings.  This function exports those values in order to
# make them readable by sub-processes.
function _config_export_accepted_values {
    local env_prefix="${CONFIG_VALUES[ENVIRONMENT_VARIABLE_PREFIX]}"
    local accepted_prefix="ACCEPTED_"
    local key
    for key in "${!CONFIG_ACCEPTED[@]}"; do
        local value="${CONFIG_ACCEPTED[${key}]}"
        local env_key="${env_prefix}${accepted_prefix}${key}"
        local -n env_key_ref="$env_key"
        export env_key_ref="$value"
    done
}

# Some of our code needs access to the protected value strings.  This function exports those values in order to
# make them readable by sub-processes.
function _config_export_protected_values {
    local env_prefix="${CONFIG_VALUES[ENVIRONMENT_VARIABLE_PREFIX]}"
    local protected_prefix="PROTECTED_"
    local key
    for key in "${!CONFIG_PROTECTED[@]}"; do
        local value="${CONFIG_PROTECTED[${key}]}"
        local env_key="${env_prefix}${protected_prefix}${key}"
        local -n env_key_ref="$env_key"
        export env_key_ref="$value"
    done
}

# Read a YAML file and convert its contents to JSON data.  We'll cache the contents in an array.  Not only is JSON much
# faster to process than YAML, but this will eliminate the need for subsequent disk I/O.
function _config_get_json_data {
    local yaml_file="$1"

    # If we've already loaded this file into memory then return its contents immediately instead of converting it again.
    local json_data="${CONFIG_FILES[${yaml_file}]}"
    if [[ -n "$json_data" ]]; then
        echo "$json_data"
        return 0
    fi

    # Ensure that the file is readable.
    if [[ ! -f "$yaml_file" ]]; then
        error_and_exit "YAML file [${yaml_file}] is unreadable.  Unable to load data!"
    fi

    # Attempt to read the YAML file from the disk and convert it to JSON.
    if ! json_data="$(yq -rc "with_entries(.key|=ascii_upcase)" "$yaml_file" 2>&1)"; then
        error_and_exit "yq error while reading ${yaml_file}: $json_data"
    fi
    CONFIG_FILES[${yaml_file}]="$json_data"
    echo "$json_data"
}

# A helper function for init_config.  Performs several bootstrapping tasks which are shared between keys.
function _config_init_bootstrap_key {
    local bootstrap_key="$1"
    local value
    shift

    # Parse command line arguments for a value.
    _config_parse_command_line_arguments 0 "$bootstrap_key" "$@"
    value="${CONFIG_VALUES[${bootstrap_key}]}"
    if [[ -n "$value" ]]; then
        return 0
    fi

    # If no value was specified on the command line then we'll try reading it from the config file, if specified.
    local config_file="${CONFIG_VALUES[CONFIG_FILE]}"
    if [[ -n "$config_file" ]]; then
        local config_data
        if ! config_data="$(_config_get_json_data "$config_file")"; then
          error_and_exit "$config_data"
        fi
        if ! value="$(jq -rc ".$bootstrap_key // empty" <<< "$config_data" 2>&1)" && [[ $? -gt 1 ]]; then
            error_and_exit "jq error while scanning ${config_file} for ${bootstrap_key}: $value"
        elif [[ -n "$value" ]]; then
            _config_set_user_value "$bootstrap_key" "$value"
            return 0
        fi
    fi

    # If no value was specified in the config file either then we'll try reading it from the environment instead.
    local env_variable_prefix="${CONFIG_VALUES[ENVIRONMENT_VARIABLE_PREFIX]}"
    if [[ -n "$env_variable_prefix" ]] || [[ "$bootstrap_key" == "ENVIRONMENT_VARIABLE_PREFIX" ]]; then
        local env_bootstrap_key="${env_variable_prefix}${bootstrap_key}"
        value="${!env_bootstrap_key}"
        if [[ -n "$value" ]]; then
            _config_set_user_value "$bootstrap_key" "$value"
            return 0
        fi
    fi

    # If a value still wasn't specified then we'll try reading it from default values as a last resort.
    value="${CONFIG_DEFAULTS[${bootstrap_key}]}"
    if [[ -n "$value" ]]; then
        set_config_value "$bootstrap_key" "$value"
        return 0
    fi
}

# Load the YAML file specified by the definitions_file path.  We'll parse this file for variable definitions.  These
# definitions will define how the user interacts with the program.
function _config_init_var_definitions {
    # Retrieve JSON data for the specified file
    local definitions_file="$1"
    log_debug "Reading yaml definition file $definitions_file"
    local definition_data
    if ! definition_data="$(_config_get_json_data "$definitions_file")"; then
      error_and_exit "$config_data"
    fi
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]]; then
        error_and_exit "could not convert yaml to json for $definitions_file"
    fi

    # Parse every key in the JSON data.
    local keys key
    if ! keys="$(jq -rc ". | keys[]" <<< "$definition_data")"; then
        error_and_exit "jq error while scanning keys in ${definitions_file}: $keys"
    fi
    for key in ${keys}; do
        key=${key^^}
        key="$(echo "$key" | tr - _)"
        if ! var_definition="$(jq -rc ".$key" <<< "$definition_data" 2>&1)"; then
            error_and_exit "jq error while scanning definition for ${key}: $var_definition"
        fi

        # Determine if the variable has already been defined.
        if [[ -n "${CONFIG_DESCRIPTIONS[${key}]}" ]]; then
            error_and_exit "Variable [${key}] has already been defined!"
        fi

        # Determine the variable's accepted values.
        local accepted
        if ! accepted="$(echo "$var_definition" | jq -rc ".accepted // empty" 2>&1)" && [[ $? -gt 1 ]]; then
            error_and_exit "jq error while scanning accepted values for ${key}: $accepted"
        elif [[ -n "$accepted" ]]; then
            CONFIG_ACCEPTED["$key"]="$accepted"
        fi

        # Determine if the variable is hidden
        local hidden
        if ! hidden="$(echo "$var_definition" | jq -rc ".hidden // empty" 2>&1)" && [[ $? -gt 1 ]]; then
            error_and_exit "jq error while scanning hidden setting for ${key}: $hidden"
        elif [[ "$hidden" == "true" ]]; then
            CONFIG_HIDDEN["$key"]=1
        fi

        # Determine if the variable is internal or configurable.
        local internal
        if ! internal="$(echo "$var_definition" | jq -rc ".internal // empty" 2>&1)" && [[ $? -gt 1 ]]; then
            error_and_exit "jq error while scanning internal setting for ${key}: $internal"
        elif [[ "$internal" != "true" ]]; then
            CONFIG_CONFIGURABLE["$key"]=1
        fi

        # Determine the variable's default value.
        local default
        if ! default="$(echo "$var_definition" | jq -rc ".default // empty" 2>&1)" && [[ $? -gt 1 ]]; then
            error_and_exit "jq error while scanning default value for ${key}: $default"
        elif [[ -n "$default" ]]; then
            CONFIG_DEFAULTS["$key"]="$default"
        fi

        # Determine the variable's description.
        local description
        if ! description="$(echo "$var_definition" | jq -rc ".description // empty" 2>&1)" && [[ $? -gt 1 ]]; then
            error_and_exit "jq error while scanning description for ${key}: $description"
        elif [[ -n "$description" ]]; then
            CONFIG_DESCRIPTIONS["$key"]="$description"
        else
            error_and_exit "Variable [${key}] has no description.  Please provide one in [${definitions_file}]!"
        fi

        # Determine if variable should be directly exported into the environment.
        local direct_export
        if ! direct_export="$(echo "$var_definition" | jq -rc ".direct_export // empty" 2>&1)" && [[ $? -gt 1 ]]; then
            error_and_exit "jq error while scanning direct_export setting for ${key}: $direct_export"
        elif [[ -n "$direct_export" ]]; then
            CONFIG_DIRECT_EXPORT["$key"]="$direct_export"
        fi

        # Determine whether the variable supports a command line flag.
        local flag
        if ! flag="$(echo "$var_definition" | jq -rc ".flag // empty" 2>&1)" && [[ $? -gt 1 ]]; then
            error_and_exit "jq error while scanning flag assignment for ${key}: $flag"
        elif [[ -n "$flag" ]]; then
            if [[ ${#flag} -ne 1 ]]; then
                error_and_exit "Please shorten the flag [${flag}] for key [${key}] to one character or remove it!"
            fi

            # Make sure the flag hasn't already been set
            local existing_key="${CONFIG_FLAGS_REVERSE[${flag}]}"
            if [[ -z "$existing_key" ]]; then
               CONFIG_FLAGS[${key}]="$flag"
               CONFIG_FLAGS_REVERSE[${flag}]="$key"
            else
                error_and_exit "Flag [${flag}] was already assigned to [${existing_key}].  Unable to assign to [${key}]!"
            fi
        fi

        # Determine if the variable is optional or required.
        local required
        if ! required="$(echo "$var_definition" | jq -rc ".required // empty" 2>&1)" && [[ $? -gt 1 ]]; then
            error_and_exit "jq error while scanning required setting for ${key}: $required"
        elif [[ "$required" == "true" ]]; then
            CONFIG_REQUIRED["$key"]=1
        else
            CONFIG_OPTIONAL["$key"]=1
        fi

        # Determine the number of parameters for this variable.
        local parameters
        if ! parameters="$(echo "$var_definition" | jq -rc ".parameters // empty" 2>&1)" && [[ $? -gt 1 ]]; then
            error_and_exit "jq error while scanning parameters setting for ${key}: $parameters"
        elif [[ -z "$parameters" ]]; then
            # Variables will be key/value pairs by default.
            CONFIG_PARAMETERS["$key"]=1
        elif [[ "$parameters" =~ ^[0-9]+$ ]]; then
            # Boolean variables may specify a parameter count of 0.  Complex variables may take multiple parameters.
            CONFIG_PARAMETERS["$key"]="$parameters"
        else
            error_and_exit "Parameters value [${parameters}] for key [${key}] is not a positive integer!"
        fi

        # Determine if the variable is protected.
        local protected
        if ! protected="$(echo "$var_definition" | jq -rc ".protected // empty" 2>&1)" && [[ $? -gt 1 ]]; then
            error_and_exit "jq error while scanning protected setting for ${key}: $protected"
        elif [[ "$protected" == "true" ]]; then
            # When we log anything we'll scan the contents for the values of protected variables.  If any of these
            # values are detected then we'll replace that portion of the contents with "<protected>" instead.
            # Shellcheck wants us to use this value in this script, but it's intended to be read elsewhere.
            # shellcheck disable=2034
            CONFIG_PROTECTED["$key"]=1
        fi
    done
}

# A helper function used to build a list of accepted values for a given key.
function _config_output_arg_info {
    local key="$1"
    local output

    # Strip away the ^ and $ characters from the accepted regex strings for readability.
    local accepted_values="${CONFIG_ACCEPTED[${key}]}"
    accepted_values="${accepted_values//^}"
    accepted_values="${accepted_values//$}"

    local values_remaining="${CONFIG_PARAMETERS[${key}]}"
    while [[ $values_remaining -gt 0 ]]; do
        if [[ -n "$accepted_values" ]]; then
            output="${output} [${accepted_values}]"
        else
            output="${output} [value]"
        fi
        values_remaining=$((values_remaining - 1))
    done
    echo "$output"
}

# Create markdown table for specified platform
function _config_output_platform_vars_doc {
    local platform="$1"

    # Build a sorted list of all keys
    local keys
    keys=("${!CONFIG_REQUIRED[@]}" "${!CONFIG_OPTIONAL[@]}")
    mapfile -t sorted_keys < <(printf '%s\n' "${keys[@]}" | sort)

    # If the key list is empty, do not output a file
    if [[ ${#sorted_keys[@]} -eq 0 ]]; then
        return
    fi

    # Map 'any' platform to 'shared' to match config yml files
    if [[ "$platform" == "any" ]]; then
        platform="shared"
    fi

    # Set docs filename
    echo "Create vars file for $platform vars"
    local docs_file
    mkdir -p "$DOCS_DIR/vars"
    docs_file="$DOCS_DIR/vars/${platform}_vars.md"

    # Determine if optional columns are required
    local flags_column_required="false"
    for key in "${sorted_keys[@]}"; do
        local check_flag="${CONFIG_FLAGS["$key"]}"
        if [[ -n "$check_flag" ]]; then
            flags_column_required="true"
        fi
    done

    # Write header and separator to file
    local header="|Parameter"
    local separator="|:--------"
    if [[ "$flags_column_required" == "true" ]]; then
        header="${header}|Flag"
        separator="${separator}|:---"
    fi
    header="${header}|Required|Values|Description|"
    separator="${separator}|:-------|:-----|:----------|"
    echo "$header" > "$docs_file"
    echo "$separator" >> "$docs_file"

    # Output a line for each key (var)
    for key in "${sorted_keys[@]}"; do
        # Don't show non-configurable and hidden variables
        if [[ -z "${CONFIG_CONFIGURABLE[${key}]}" ]] || \
           [[ "${CONFIG_HIDDEN[${key}]}" -eq "1" ]]; then
            continue
        fi

        # Build var table line
        local table_line
        table_line="|$key"

        # Flag column
        if [[ "$flags_column_required" == "true" ]]; then
            local flag
            flag="${CONFIG_FLAGS["$key"]}"
            if [[ -n "$flag" ]]; then
                flag="-${flag}"
            else
                flag=" "
            fi
            table_line="${table_line}|${flag}"
        fi

        # Required column
        local req_string
        [[ "${CONFIG_REQUIRED[${key}]}" -eq 1 ]] && req_string="Yes" || req_string="No"
        table_line="${table_line}|$req_string"

        # Values column
        local values
        values=$(_config_output_arg_info "${key}")
        if [[ -n "$values" ]]; then
            values=${values//|/ \\| }
            values="${values## }"
        else
            values=" "
        fi
        table_line="${table_line}|$values"

        # Description 
        table_line="${table_line}|${CONFIG_DESCRIPTIONS[${key}]}|"

        # Output line to file
        echo "$table_line" >> "$docs_file"
    done
}

# Create arg list and usage of config data for docs
function _config_output_docs {
    echo "Create documentation for config"

    # Determine project root
    local project_dir
    project_dir=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../../../..")

    # Ensure docs directory exists
    DOCS_DIR="${CONFIG_VALUES[DOCS_DIR]}"
    mkdir -p "$DOCS_DIR"

    # Shared config is loaded by default.  Create shared vars doc first.
    _config_output_platform_vars_doc "any"

    # Get accepted values for platforms. Strip away the ^ and $ characters
    # from the accepted regex strings and create a platforms array
    local platforms="${CONFIG_ACCEPTED[PLATFORM]}"
    platforms="${platforms//^}"
    platforms="${platforms//$}"
    platforms="${platforms//|/ }"
    # platform "vm" does not exist, but yaml file shared by all vm platforms does
    platforms="${platforms} vm"

    # shellcheck disable=SC2206
    platforms=(${platforms})

    # Create a doc for each platform
    local platform
    for platform in "${platforms[@]}"; do
        # flush previously loaded config
        _clear_config_arrays
        _init_config_arrays

        # load config for current platform
        if ! _config_init_var_definitions "${project_dir}/src/resource/vars/${platform}_vars.yml"; then
            echo "Couldn't load config for $platform"
            exit 1
        fi

        # Create platform vars doc
        _config_output_platform_vars_doc "$platform"
    done

    return 0
}

# Display usage information and variable definitions for initialized variables
function _config_output_help {
    # Ensure that the config system has been initialized.
    local output
    init_config >> /dev/null

    # Build a string which lists all of the accepted platforms
    local platform_string
    platform_string="$(_config_output_arg_info "PLATFORM")"

    # Display usage header message
    log_info "Displaying usage for platform [${CONFIG_VALUES[PLATFORM]:-any}].  Run --help --platform${platform_string} \
to view usage information for a specific platform."
    log_info ""
    log_info "----------------MINIMAL COMMAND LINE USAGE:----------------"

    # Combine required keys and allowed inputs into a single command line example string.
    local usage_string="build-image"
    local key
    for key in "${!CONFIG_REQUIRED[@]}"; do
        # Don't show usage for non-configurable variables
        if [[ -z "${CONFIG_CONFIGURABLE[${key}]}" ]] || \
           [[ "${CONFIG_HIDDEN[${key}]}" -eq "1" ]]; then
            continue
        fi

        # Prepend the next configuration key with a space.
        usage_string="$usage_string "

        # If the key supports a flag then we'll display that in the example.  Otherwise we'll display the long version.
        local flag="${CONFIG_FLAGS[${key}]}"
        if [[ -z "$flag" ]]; then
            usage_string="${usage_string}--${key,,}"
        else
            usage_string="${usage_string}-${flag}"
        fi

        # If the key has parameters specified then we'll print the allowed arguments one by one after the key
        usage_string="${usage_string}$(_config_output_arg_info "$key")"
    done
    log_info "$usage_string"
    log_info ""
    log_info "----------------ALTERNATIVE USAGE:----------------"
    log_info "All configuration keys may be supplied one of the following ways (descending priority):"
    log_info "1.) As a command line argument using --keyname or a single character flag associated with the key (IE: -x). \
Case will be ignored for keys, but not their values.  Boolean flags may be chained together as the first argument to \
the program (IE: -xyz).  Keys and their values must be separated by spaces (IE: --foo \"bar\").  This is also true for \
keys which require multiple arguments (IE: --foo \"bar\" \"baz\")."
    log_info "2.) As a key/value pair at the top level of a YAML config file (IE: foo: \"bar\").  Specify this file on the \
command line with --config_file or set CONFIG_FILE in your environment.  Values which contain lists must still have \
their arguments separated by spaces (IE: foo: \"bar baz\").  Case will be ignored for keys, but not values.  If \
present, lower level YAML keys will be collapsed together into a single JSON string and assigned to the outer level \
key.  Command line and environment keys representing these multi-level structures must already be formatted as JSON \
strings (IE: --foo \"[{\"bar:baz\",\"wibble:wobble\"}]\"."
    log_info "3.) As an environment variable (IE: export FOO=\"bar\").  Environment variables must be uppercase.  Again, \
values which represent lists must use spaces for separators (IE: export FOO=\"bar baz\")."
    log_info ""
    log_info "----------------REQUIRED KEYS:----------------"
    for key in "${!CONFIG_REQUIRED[@]}"; do
        _config_output_key_usage "$key"
    done
    log_info "----------------OPTIONAL KEYS:----------------"
    for key in "${!CONFIG_OPTIONAL[@]}"; do
        _config_output_key_usage "$key"
    done
}

# A helper function for output_help.  This will output the key name, flag (if associated), allowed arguments, and
# description.
function _config_output_key_usage {
    local key="$1"

    # Don't show usage for non-configurable variables
    if [[ -z "${CONFIG_CONFIGURABLE[${key}]}" ]] || \
       [[ "${CONFIG_HIDDEN[${key}]}" -eq "1" ]]; then
        return 0
    fi

    local key_string="${key}"
    local flag="${CONFIG_FLAGS[${key}]}"

    # Add the flag for this key, if it exists.
    if [[ -n "$flag" ]]; then
        key_string="${key_string} (-${flag})"
    fi

    # Add argument information for this key, if it exists.
    key_string="${key_string}$(_config_output_arg_info "${key}")"

    # Output key usage information.
    log_info "$key_string"

    # Output the description for the key on a separate line.
    log_info "${CONFIG_DESCRIPTIONS[${key}]}"
    log_info ""
}

# Output the current version of the program.
function _config_output_version {
    local version="${CONFIG_VALUES[VERSION_NUMBER]}"
    log_info "version=$version"
}

# Output the build info.
function _config_output_info {
    if "$(realpath "$(dirname "${BASH_SOURCE[0]}")")"/../../../bin/get_build_info.py "$(realpath .)"; then
        return 0
    else
        log_info "Getting info failed"
    fi
}

# Parse command line arguments for defined keys and record their values based on the configurations for those keys.
# This can be called in two different modes:
# --------------- #
# Bootstrap mode: # Used to look for specific keys whose values are required in order to initialize the config system
# 0 "KEY" "$@"    # itself.  Other keys will be ignored because their definitions may not have been loaded yet.  Without
#                 # definitions for these keys we won't be able to validate them or assign the correct number of
#                 # arguments to them.
#                 #
# Full mode:      # Used once the config system has been bootstrapped.  All keys will be parsed and assigned values
# 1 "$@"          # According to their configured definitions.  At this point:
#                 # 1. The configuration file has been determined (if specified).
#                 # 2. The platform has been determined (if specified).
#                 # 3. Definitions have been loaded for shared variables along with the specified platform.
# --------------- #
function _config_parse_command_line_arguments {
    # Determine mode
    local bootstrap_key
    local mode="$1"
    case "$mode" in
    0)  # Bootstrap mode
        bootstrap_key="$2"
        shift 2
        ;;
    1)  # Full mode
        log_info "Parsing remaining command line arguments"
        shift
        ;;
    *)  # Unrecognized mode
        error_and_exit "Unrecognized command line parsing mode [${mode}]!"
        ;;
    esac
    local flag key last_key value
    local expected_values=0
    local first_argument="$1"

    # If the first argument is a sequence of flags (IE: -xyz) then we'll parse them all together.
    if [[ "$first_argument" =~ ^-[a-zA-Z]+$ ]]; then
        local flags_length=${#first_argument}
        local flag_position=1
        while [[ $flag_position -lt $flags_length ]]; do
            # Lookup key associated with flag
            flag="${first_argument:${flag_position}:1}"
            key="${CONFIG_FLAGS_REVERSE[${flag}]}"

            # If we're in bootstrap mode and this isn't the key we're looking for then we'll skip to the next flag.
            if [[ -n "$bootstrap_key" ]] && [[ "$key" != "$bootstrap_key" ]]; then
                last_key="$key"
                flag_position=$((flag_position + 1))
                continue
            fi

            # If the flag is invalid then we'll return.
            if [[ -z "$key" ]]; then
                log_error "Flag [${flag}] is not supported for platform [${CONFIG_VALUES[PLATFORM]:-any}]!"
                error_and_exit "Please run with -h flag for detailed help"
            fi

            # Retrieve the expected values for this key and determine if we need to read more arguments to set them.
            expected_values="${CONFIG_PARAMETERS[${key}]}"
            if [[ $expected_values -eq 0 ]]; then
                # Save value as true since the key is boolean and no more arguments are needed.
                if ! _config_set_user_value "$key" "true"; then
                    return 1
                elif [[ -n "$bootstrap_key" ]]; then
                    # We've got a value for the bootstrap key!
                    return 0
                fi
            elif [[ $flag_position -lt $((flags_length - 1)) ]]; then
                # A flag expecting arguments is considered invalid if it's placed directly before another flag.
                log_error "Flag [${flag}] can't be directly followed by another flag since it takes arguments!"
                error_and_exit "Please run with -h flag for detailed help"
            fi
            last_key="$key"
            flag_position=$((flag_position + 1))
        done
        shift
    fi

    # Parse the remaining command line arguments
    while [[ ${#@} -gt 0 ]]; do
        local argument="$1"
        if [[ $expected_values -gt 0 ]]; then
            # If a key from the previous step or iteration still requires values then we'll append the next argument to
            # the existing value string.
            value="${value}${argument}"
            expected_values=$((expected_values - 1))

            # If this isn't the last argument supplied to a multi-parameter variable then we'll append a space to the
            # value to make room for the next argument in the list.
            if [[ $expected_values -gt 0 ]]; then
                value="${value} "
            else
                # This is the last argument needed for the value.  We'll save it to config now.
                _config_set_user_value "$last_key" "$value"

                # Reset value so it can be rebuilt for another key when appended to in subsequent iterations.
                unset value
                if [[ -n "$bootstrap_key" ]]; then
                    # We've got a value for the bootstrap key!
                    return 0
                fi
            fi
        else
            # We're expecting a new key.
            if [[ "$argument" =~ ^-[a-zA-Z]$ ]]; then
                # The key is specified by a flag.
                flag="${argument:1:1}"
                key="${CONFIG_FLAGS_REVERSE[${flag}]}"
            elif [[ "$argument" =~ ^--.+$ ]]; then
                # The key is specified directly.
                local key_length=${#argument}
                key_length=$((key_length - 2))
                key="${argument:2:$key_length}"
                key="${key^^}"
                key="$(echo "$key" | tr - _)"
            fi

            # If we're in bootstrap mode and this isn't the key we're looking for then we'll skip to the next argument.
            if [[ -n "$bootstrap_key" ]] && [[ "$key" != "$bootstrap_key" ]]; then
                last_key="$key"
                shift
                continue
            fi

            # If the argument is invalid then we'll exit.
            if [[ -z "$key" ]]; then
                log_error "[${argument}] is not a valid key or flag for platform [${CONFIG_VALUES[PLATFORM]:-any}]!"
                error_and_exit "Please run with -h flag for detailed help"
            fi

            # Retrieve the expected values for this key and determine if we need to read more arguments to set them.
            expected_values="${CONFIG_PARAMETERS[${key}]}"
            if [[ $expected_values -eq 0 ]]; then
                # Save value as true since the key is boolean and no more arguments are needed.
                _config_set_user_value "$key" "true"
                if [[ -n "$bootstrap_key" ]]; then
                    # We've got a value for the bootstrap key!
                    return 0
                fi
            fi
            last_key="$key"
            unset key
        fi
        shift
    done
    if [[ $expected_values -gt 0 ]]; then
        log_error "Key [${last_key}] was expecting a value but never received one!"
        error_and_exit "Please run with -h flag for detailed help"
    fi
}

# Here we'll check the specified configuration file for user-provided key/value pairs.  Validating that the file is
# accessible is handled by the caller.  Validating that the file is valid YAML is handled during the call to yq.
function _config_parse_config_file_values {
    # If there's no config file then we have nothing to do here.
    local config_file="${CONFIG_VALUES[CONFIG_FILE]}"
    if [[ -z "$config_file" ]]; then
        return 0
    fi

    log_info "Parsing remaining configuration values from config file [${config_file}]"
    local config_data
    if ! config_data="$(_config_get_json_data "$config_file")"; then
      error_and_exit "$config_data"
    fi

    # Attempt to save every key which the user specified into CONFIG_VALUES.  set_user_value will automatically prevent
    # us from writing values which aren't supposed to be configurable.
    local keys key value
    if ! keys="$(jq -rc ". | keys[]" <<< "$config_data")"; then
        error_and_exit "jq error while scanning provided file ${config_file}: $keys"
    fi
    for key in ${keys}; do
        key="${key^^}"
        key="$(echo "$key" | tr - _)"
        if ! value="$(jq -rc ".$key // empty" <<< "$config_data" 2>&1)" && [[ $? -gt 1 ]]; then
            error_and_exit "jq error while scanning provided key ${key}: $value"
        elif [[ -z "${CONFIG_VALUES[${key}]}" ]]; then
            _config_set_user_value "$key" "$value"
        fi
    done
}

# Here we'll read environment variable values for any configurable keys which haven't already been set.
function _config_read_variables_from_environment {
    local key
    for key in "${!CONFIG_CONFIGURABLE[@]}"; do
        local current_value="${CONFIG_VALUES[${key}]}"
        if [[ -z "$current_value" ]]; then
            local value="${!key}"
            if [[ -n "$value" ]]; then
                _config_set_user_value "$key" "$value"
            fi
        fi
    done
}

# Performs additional validations before calling set_config_value.
function _config_set_user_value {
    local key="${1^^}"
    key="$(echo "$key" | tr - _)"
    local value="$2"

    # Check if key configurable.
    if [[ -z "${CONFIG_CONFIGURABLE[${key}]}" ]]; then
        local platform="${CONFIG_VALUES[PLATFORM]:-any}"
        log_info "Configuration key [${key}] is not configurable for platform [${platform}]!  Skipping."
        return 0
    fi

    # If the user has already configured this value earlier then we'll skip it.  This ensures that priority is obeyed.
    if [[ -n "${CONFIG_VALUES[${key}]}" ]]; then
        return 0
    fi

    # Check if value is accepted.
    local accepted_regex="${CONFIG_ACCEPTED[${key}]}"
    if [[ -n "$accepted_regex" ]]; then
        # An accepted values regex is present. We'll have to check if the provided value matches it.
        if [[ ! "$value" =~ $accepted_regex ]]; then
            log_error "Value [${value}] for key [${key}] did not match accepted regex [${accepted_regex}]!"
            error_and_exit "Please run with -h flag for detailed help"
        fi
    fi

    # Set the config value.
    set_config_value "$key" "$value"
}

# Here we'll confirm that every variable which requires a value for the current platform has been configured to have
# one.  If there's anything missing then we'll alert the user.
function _config_validate_required_variables {
    # Ensure that the config system has been initialized.
    local output
    init_config

    # Perform validations
    log_info "Validating that required variables are present"
    local key
    for key in "${!CONFIG_REQUIRED[@]}"; do
        if [[ -z "${CONFIG_VALUES[${key}]}" ]]; then
            log_error "Key [${key}] is required for platform [${CONFIG_VALUES[PLATFORM]:-any}]!"
            error_and_exit "Please run with -h flag for detailed help"
        fi
    done
}
