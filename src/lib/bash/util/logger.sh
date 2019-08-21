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



# Error level to their numerical value converter map. The values are
# directly taken from syslog priority level definition.
declare -A LOG_LEVEL_MAP
LOG_LEVEL_MAP[CRITICAL]=50
LOG_LEVEL_MAP[ERROR]=40
LOG_LEVEL_MAP[WARNING]=30
LOG_LEVEL_MAP[INFO]=20
LOG_LEVEL_MAP[DEBUG]=10
LOG_LEVEL_MAP[TRACE]=5
LOG_LEVEL_MAP[NOTSET]=0

# Global debug level string for image generator tool.
declare -g LOG_FILE_NAME
declare -g LOG_LEVEL
declare -g TEMP_LOG_BUFFER=()
export DEFAULT_LOG_LEVEL="DEBUG"

# store the log filename and store/initialize the LOG_LEVEL
function create_logger {
    # Check arguments
    if [[ $# != 2 ]]; then
        error_and_exit "Usage: ${FUNCNAME[0]} <log_file> <log_level>"
    fi
    local new_log_file_name="$1"
    if [[ -z "$new_log_file_name" ]]; then
        echo "Logger Error: A valid file path is required"
        return 1
    fi
    local new_level="$2"

    # Create the new log file
    if [[ ! -f "$new_log_file_name" ]]; then
        local dir
        dir=$(dirname "$new_log_file_name")
        mkdir -p "$dir"
        touch "$new_log_file_name"
    fi
    export LOG_FILE_NAME="$new_log_file_name"
    set_log_level "$new_level"

    # Write any buffered output which has been waiting for the log file to be specified
    for line in "${TEMP_LOG_BUFFER[@]}"; do
        echo "$line" >> "${LOG_FILE_NAME}"
    done
    TEMP_LOG_BUFFER=()
}

# Set the global LOG_LEVEL to the user supplied log level.  If the user supplied log level does not
# exist then fall back to the current one instead.
function set_log_level {
    local new_level="$1"
    local current_level
    current_level="$(get_log_level)"
    if [[ -n "${LOG_LEVEL_MAP["$new_level"]}" ]]; then
        export LOG_LEVEL="$new_level"
    else
        echo "Unable to set invalid log level <$new_level>!"
        echo "Continuing to use current log level <$current_level> instead."
    fi
}

# Return the current global log level, or $DEFAULT_LOG_LEVEL if none is specified
function get_log_level {
    if [[ -n "$LOG_LEVEL" ]]; then
        echo "$LOG_LEVEL"
    else
        echo "$DEFAULT_LOG_LEVEL"
    fi
}

function is_msg_level_high {
    local msg_level="${1}"
    local current_level
    current_level="$(get_log_level)"
    if [[ ${LOG_LEVEL_MAP["${msg_level^^}"]} -ge ${LOG_LEVEL_MAP["${current_level^^}"]} ]]; then
        return 0
    fi
    return 1
}

# Main logger functions that compares the passed message's priority level
# with LOG_LEVEL and decides if the message should be printed...
function logger_message {
    local msg_level="$1"
    shift
    local msg="$*"
    local current_level
    current_level="$(get_log_level)"

    # Convert to the numerical equivalent...
    local date_time
    date_time=$(date +"%Y/%m/%d %H:%M:%S")
    local function_name="${FUNCNAME[2]}"

    # We'll only write to the log file if the supplied level is equal or more severe than the global
    # LOG_LEVEL.
    if [[ ${LOG_LEVEL_MAP["${msg_level^^}"]} -ge ${LOG_LEVEL_MAP["${current_level^^}"]} ]]; then
        local formatted_message="[$date_time]-[$function_name]-[$msg_level] ${msg}"
        if [[ -n "$LOG_FILE_NAME" ]]; then
            echo "$formatted_message" >> "${LOG_FILE_NAME}"
        else
            # We have a message which we'd like to write to the log file, but the file hasn't been
            # specified yet.  We'll save it into a temporary buffer for now.
            TEMP_LOG_BUFFER+=("$formatted_message")
        fi
    fi

    # if the supplied level is equal or more severe than "INFO"
    # then the log message will go to console also
    if [[ ${LOG_LEVEL_MAP["${msg_level^^}"]} -ge ${LOG_LEVEL_MAP["INFO"]} ]]; then
        echo "${msg}"
    fi
}

# trace level message...
function log_trace {
    logger_message "TRACE" "$@"
}

# debug level message...
function log_debug {
    logger_message "DEBUG" "$@"
}

# info level message...
function log_info {
    logger_message "INFO" "$@"
}

# warning level message...
function log_warning {
    logger_message "WARNING" "$@"
}

# error level message...
function log_error {
    logger_message "ERROR" "$@"
}

# critical level message...
function log_critical {
    logger_message "CRITICAL" "$@"
}

function error_and_exit {
    logger_message "ERROR" "$@"
    exit 1
}

# use this utility if logger needs to capture and show the output of a specific command
# based on the priority level. Don't use it for commands that takes a long time to execute
# and need a progress-bar. That's to ensure console remains responsive.
function log_cmd_output {
    local level="${1}"
    shift

    local ret_val
    local output
    output="$("$@" 2>&1)"
    ret_val=$?
    logger_message "$level" "$output"
    return $ret_val
}
