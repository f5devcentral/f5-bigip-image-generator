"""Common utilities for all other modules and classes"""
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


import os
import re
import subprocess
import sys
import threading
import time
import json
from contextlib import contextmanager
import exceptions

from util.config import get_config_value, get_config_accepted, get_dict_from_config_json
from util.logger import LOGGER, create_file_handler

def is_supported_cloud(cloud_type):
    """Checks if the given cloud is a supported cloud."""
    supported_clouds = re.sub(r'[\^$]', '', get_config_accepted("CLOUD"))
    return cloud_type in supported_clouds.split('|')


def ensure_value_from_dict(value_dict, key):
    """Attempts to retrieve a value from a dictionary.  Throws an exception if it's empty."""
    try:
        value = value_dict[key]
    except KeyError:
        LOGGER.error("Unable to retrieve key [%s] from dictionary!", key)
        raise
    if not value:
        error_message = "Dictionary contained an empty value for key [{}]!".format(key)
        LOGGER.error(error_message)
        raise ValueError(error_message)
    return value

def save_image_id(image_id):
    """Takes in an image_id and saves it to artifacts_id/image_id.json."""
    image_id_json = {"image_id": image_id}
    artifacts_dir = get_config_value("ARTIFACTS_DIR")
    with open(artifacts_dir + "/image_id.json", "w") as image_id_json_file:
        json.dump(image_id_json, image_id_json_file)


def remove_prefix_from_string(prefix, string):
    """Removes a prefix from a string if it exists.  Otherwise returns the unmodified string."""
    if string.startswith(prefix):
        string = string[len(prefix):]
    return string


# pylint wishes this function could be simpler. Me too!
# pylint: disable=too-many-arguments,too-many-locals
def call_subprocess(command, input_data=None, timeout_millis=-1, check_return_code=True,
                    input_encoding="utf-8", output_encoding="utf-8"):
    """Calls a subprocess, records progress to console, performs error handling, and returns the
    output.
    ----
    command: The command and arguments to execute. This must either be a string or a list. String
    formatting is more convenient for simple cases while list formatting provides more control over
    escaped characters and whitespace within arguments. If list formatting is used then the first
    item in the list will be executed as a subprocess and the remaining commands will be treated as
    arguments to that subprocess.
    ----
    in_data: The data to send to the subprocess' STDIN. This is used for processes which
    ordinarily read data from pipes instead of arguments. This may either be a bytes-like-object or
    a string.
    ----
    timeout_millis: The number of milliseconds to wait for the subprocess to return before killing
    it. A negative number means that no timeout will occur.
    ----
    check_return_code: Raises a ReturnCodeError if the subprocess returns a non-zero exit status.
    ----
    input_encoding: Encoding type to use when passing data to STDIN as a string. This is ignored for
    bytes-like-objects.
    ----
    output_encoding: Encoding type to use when decoding output from the subprocess. Set this to None
    to receive raw binary output.
    """
    if isinstance(command, str):
        # Popen will only accept a list
        command = command.split()
    if input_data:
        if isinstance(input_data, str):
            # Popen.communicate will only accept a bytes-like-object
            input_data = input_data.encode(input_encoding)
        elif not isinstance(input_data, bytes):
            message = "input_data was not a string or bytes-like-object! " \
                      "Unable to send to command [{}]!".format(" ".join(command))
            LOGGER.error(message)
            raise TypeError(message)
    poll_millis = int(get_config_value("SUBPROCESS_POLL_MILLIS"))
    progress_update_delay_millis = \
        int(get_config_value("CONSOLE_PROGRESS_BAR_UPDATE_DELAY")) * 1000
    start_time_millis = time.time() * 1000
    next_progress_update_millis = start_time_millis + progress_update_delay_millis
    # We create the output buffer as a list so that we can pass it by reference to the
    # communications thread. Once that thread has joined we'll be able to safely unwrap the output
    # string from position 0 of this list.
    output = []
    LOGGER.info("Calling: %s", " ".join(command))
    with subprocess.Popen(command,
                             stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT) as child:
        # If the child process produces enough output to fill the STDOUT buffer then it will block
        #until another process frees up space in the buffer by reading from it. Unfortunately,
        # Python's subprocess.read function is a blocking call which will only return once the
        # child process exits and the pipe is closed. Since we need the main thread to make polling
        # and progress calls we're not able to call the blocking read function until after the
        # child process has already terminated.
        # This leads to a deadlock where nothing is reading from the STDOUT buffer because
        # the child process hasn't terminated yet and the child process hasn't terminated yet
        # because it's waiting for the STDOUT buffer to be freed up by a read call.
        #     A popular solution here is to to use subprocess.readline instead, as this will only
        # block until a newline character is detected in the output. However, this is still
        # unreliable since not all data sent to STDOUT is guaranteed to terminate in a newline.
        #     A better solution is to start a separate communications thread where we can begin
        # reading without blocking the main thread from polling the child process. Since writing is
        # affected by a similar issue (STDIN can fill up and cause the main thread to block) we use
        # the Popen.communicate method to perform both reading and writing asynchronously on the
        # communications thread.
        comm = threading.Thread(target=lambda p, i, o: o.append(p.communicate(i)[0]),
                                args=(child, input_data, output))
        comm.start()
        wrote_progress = False
        while child.poll() is None:
            current_time_millis = time.time() * 1000
            if current_time_millis > next_progress_update_millis:
                sys.stdout.write('.')
                sys.stdout.flush()
                wrote_progress = True
                next_progress_update_millis = current_time_millis + progress_update_delay_millis
            if timeout_millis > -1 and current_time_millis >= start_time_millis + timeout_millis:
                message = "Command [{}] has timed out!".format(" ".join(command))
                LOGGER.warning(message)
                child.kill()
                comm.join()
                if output_encoding == "utf-8":
                    LOGGER.warning("Command output was: %s", output[0]
                                   .decode(output_encoding).rstrip())
                raise TimeoutError(message)
            time.sleep(poll_millis / 1000)
        comm.join()
        if wrote_progress:
            sys.stdout.write('\n')
            sys.stdout.flush()
        if check_return_code and child.returncode != 0:
            message = "Command [{}] returned with error code [{}]!".format(" ".join(command),
                                                                           child.returncode)
            LOGGER.warning(message)
            if output_encoding == "utf-8":
                LOGGER.warning("Command output was: %s", output[0].decode(output_encoding).rstrip())
            raise exceptions.ReturnCodeError(child.returncode, message)
        if output_encoding:
            return output[0].decode(output_encoding).rstrip()
        return output[0]


@contextmanager
def change_dir(new_dir):
    """Perform a temporary directory change while ensuring that the working directory will be
    reverted to its original state afterwards. Example:

    with change_dir(new_dir):
        # Working directory changed to new_dir
        do_stuff_in_new_dir
    # Working directory reverted to old_dir
    do_stuff_in_old_dir

    """
    old_dir = os.getcwd()
    os.chdir(os.path.expanduser(new_dir))
    try:
        yield
    finally:
        os.chdir(old_dir)

def create_log_handler():
    """create log handler for the global LOGGER based on LOG_FILE and LOG_LEVEL"""
    log_file = get_config_value('LOG_FILE')
    log_level = get_config_value('LOG_LEVEL').upper()
    create_file_handler(LOGGER, log_file, log_level)


def read_lv_sizes(lv_sizes_patch_json):
    """ Read user defined values for LV sizes, validate them and store in a json file """
    if not get_config_value('UPDATE_LV_SIZES'):
        # LV sizes are not overridden
        return

    modifiable_size_lvs = {'appdata', 'config', 'log', 'shared', 'var'}
    lv_sizes_dict = get_dict_from_config_json('UPDATE_LV_SIZES')
    filtered_dict = {}
    for lv_name in lv_sizes_dict:
        lv_size = lv_sizes_dict[lv_name]
        lv_name = lv_name.lower()
        if not isinstance(lv_size, int):
            raise RuntimeError('LV size for \'{}\' must be an integer, '.format(lv_name) +
                               'denoting the size in MiBs (without quotation marks).')
        if lv_name not in modifiable_size_lvs:
            raise RuntimeError('\'{}\' is not a member '.format(lv_name) +
                               'of modifiable size LVs: {}. '.format(modifiable_size_lvs) +
                               '\'{}\' is not an LV or '.format(lv_name) +
                               'its size cannot be changed!')
        filtered_dict[lv_name] = lv_size

    with open(lv_sizes_patch_json, 'w') as patch_file:
        json.dump(filtered_dict, patch_file, indent=2)
