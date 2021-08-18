"""Module to read info about injected files"""
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


from os.path import basename, isdir, isfile, abspath, realpath, expanduser
from pathlib import Path
from shutil import copy2, copytree
import re
import requests

from telemetry.build_info_inject import BuildInfoInject
from util.config import get_config_value, get_list_from_config_yaml
from util.logger import LOGGER


def extract_single_worded_key(dictionary, key):
    """ verify that key is in dictionary and its value is a single word """
    if key in dictionary:
        value = dictionary[key]
        if not isinstance(value, str):
            raise RuntimeError('\'{}\' of injected file must be a string, but got {}'
                               .format(key, value))
        if len(value.split()) == 1:
            return value
        raise RuntimeError('\'{}\' of injected file must be a single word, but got {} words: \'{}\''
                           .format(key, len(value.split()), value))

    raise RuntimeError('\'{}\' is not specified for injected file \'{}\' !'
                       .format(key, dictionary))


def read_injected_files(top_call_dir, overall_dest_dir):
    """
    Copy files that need to be injected to a temporary location,
    which will be accessible during post-install.
    Two mandatory arguments:
        a path from where build-image was called
        a path to initrd directory that will be available during post_install
    """

    # location used by post-install, should be created only if there are files to inject
    injected_files = 'etc/injected_files' # location used by post-install
    overall_dest_dir = overall_dest_dir + '/' + injected_files
    LOGGER.info('Temporary location for injected files: \'%s\'', overall_dest_dir)

    # include user-specified files
    files_to_inject = get_list_from_config_yaml('UPDATE_IMAGE_FILES')

    # add build_info.json
    prep_build_info_for_injection(files_to_inject)

    # each injected file directory to be stored in a separate directory "file<number>"
    count = 0
    LOGGER.trace("files_to_inject: %s", files_to_inject)
    for file in files_to_inject:
        LOGGER.debug('Injecting file: \'%s\'.', file)
        src = extract_single_worded_key(file, 'source')
        dest = extract_single_worded_key(file, 'destination')
        if 'mode' in file:
            mode = extract_single_worded_key(file, 'mode')
        else:
            mode = None
        LOGGER.info('Copy \'%s\' to a temporary location for \'%s\'.', src, dest)

        url = src # treat 'src' as a file path and 'url' as a url
        if src[0] != '/' and src[0] != '~':
            # make it an absolute path
            src = top_call_dir + '/' + src
        src = abspath(realpath(expanduser(src)))

        file_holder = overall_dest_dir + '/file' + str(count) + '/'
        # copy source to "src"
        # source file name does not need to be preserved;
        # it will be copied to destination path on BIG-IP
        source_holder = file_holder + 'src'
        Path(file_holder).mkdir(parents=True, exist_ok=True)
        if isfile(src):
            LOGGER.info('Treating \'%s\' as a file for file injection', src)
            copy2(src, source_holder)
        elif isdir(src):
            LOGGER.info('Treating \'%s\' as a directory for file injection', src)
            copytree(src, source_holder)
        else:
            LOGGER.info('Treating \'%s\' as a URL for the file injection', url)
            download_file(url, source_holder)

        # store destination
        if dest[0] != '/':
            raise RuntimeError('injected file destination \'{}\' must be an absolute path!'
                               .format(dest))
        with open(file_holder + 'dest', 'w') as dest_holder:
            print("{}".format(dest), file=dest_holder)

        # Store mode. Should be a string consisting of one to four octal digits.
        if mode:
            LOGGER.debug('Creating mode holder for mode \'%s\'.', mode)
            mode_pattern = re.compile('^[0-7][0-7]?[0-7]?[0-7]?$')
            if not mode_pattern.match(mode):
                raise RuntimeError('Invalid mode \'' + mode + '\', must be a string ' +
                                   'consisting of one to four octal digits.')
            with open(file_holder + 'mode', 'w') as mode_holder:
                print("{}".format(mode), file=mode_holder)

        count += 1
        # end of for loop

    LOGGER.debug('leaving %s', basename(__file__))
    return 0


def prep_build_info_for_injection(files_to_inject):
    """ prepare information about installed software on the build machine """
    artifacts_dir = get_config_value("ARTIFACTS_DIR")
    build_info_file_name = "build_info.json"
    build_info_source = artifacts_dir + "/" + build_info_file_name
    build_info_destination = "/" + build_info_file_name
    files_to_inject.append({'source': build_info_source, 'destination': build_info_destination})
    build_info = BuildInfoInject()
    LOGGER.info(build_info.to_json())
    build_info.to_file(build_info_source)


def download_file(url, dest_file):
    """ Download from url to a local file.
        Throws exceptions with wording specific to the file injection.
        Assumes that the directory containing the destination file already exists. """
    verify_tls = bool(get_config_value("IGNORE_DOWNLOAD_URL_TLS") is None)
    try:
        remote_file = requests.get(url, verify=verify_tls, timeout=60)
    except requests.exceptions.SSLError as exc:
        LOGGER.exception(exc)
        raise RuntimeError(
            'Cannot access \'{}\' due to TLS problems! '.format(url) +
            'Consider abandoning TLS verification by usage of ' +
            '\'IGNORE_DOWNLOAD_URL_TLS\' parameter.') from exc
    except requests.exceptions.RequestException as exc:
        LOGGER.exception(exc)
        raise RuntimeError(
            '\'{}\' is neither a file nor a directory nor a valid url, cannot inject it!'
            .format(url)) from exc
    if remote_file.status_code != 200:
        LOGGER.info('requests.get response status: %s', remote_file.status_code)
        LOGGER.info('requests.get response headers: %s', remote_file.headers)
        raise RuntimeError(
            'URL \'{}\' did not return content, cannot inject it!'
            .format(url))
    open(dest_file, 'wb').write(remote_file.content)
