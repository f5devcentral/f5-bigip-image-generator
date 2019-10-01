"""Module to read info about injected files"""
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


from os.path import basename, isdir, isfile, abspath, realpath, expanduser
from pathlib import Path
from shutil import copy2, copytree

from util.build_info import BuildInfo
from util.config import get_config_value, get_list_from_config_yaml
from util.logger import LOGGER


def extract_single_worded_key(dictionary, key):
    """ verify that key is in dictionary and its value is a single word """
    if key in dictionary:
        value = dictionary[key]
        if len(value.split()) == 1:
            return value
        raise RuntimeError('\'{}\' of injected file must be a single word, but got {}: \'{}\''
                           .format(key, len(value.split()), value))

    raise RuntimeError('\'{}\' is not specified for injected file \'{}\' !'
                       .format(key, dictionary))


def read_injected_files(top_call_dir, overall_dest_dir):
    """
    Copy file that need to be injected to temporary location,
    which will be accessible during post-install.
    Two mandatory arguments:
        a path from where build-image was called
        a path to initrd directory that will be available during post_install
    """

    # location used by post-install, should be created only if there are files to inject
    injected_files = 'etc/injected_files' # location used by post-install
    overall_dest_dir = overall_dest_dir + '/' + injected_files
    LOGGER.info('temporary location for injected files: %s', overall_dest_dir)

    # include user-specified files
    files_to_inject = get_list_from_config_yaml('UPDATE_IMAGE_FILES')

    # add build_info.json
    prep_build_info_for_injection(files_to_inject)

    # each injected file directory to be stored in a separate directory "file<number>"
    count = 0
    LOGGER.trace("files_to_inject: %s", files_to_inject)
    for file in files_to_inject:
        LOGGER.trace("file: %s", file)
        src = extract_single_worded_key(file, 'source')
        if src[0] != '/' and src[0] != '~':
            # make it an absolute path
            src = top_call_dir + '/' + src
        src = abspath(realpath(expanduser(src)))
        dest = extract_single_worded_key(file, 'destination')
        LOGGER.info('inject %s to temporary location %s', src, dest)

        file_holder = overall_dest_dir + '/file' + str(count) + '/'
        # copy source to "src"
        # source file name does not need to be preserved;
        # it will be copied to destination path on BIG-IP
        source_holder = file_holder + 'src'
        if isfile(src):
            Path(file_holder).mkdir(parents=True, exist_ok=True)
            copy2(src, source_holder)
        elif isdir(src):
            copytree(src, source_holder)
        else:
            raise RuntimeError('\'{}\' is neither a file nor a directory, cannot inject it!'
                               .format(src))

        # store destination
        if dest[0] != '/':
            raise RuntimeError('injected file destination \'{}\' must be an absolute path!'
                               .format(dest))
        with open(file_holder + 'dest', 'w') as dest_holder:
            print("{}".format(dest), file=dest_holder)

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
    build_info = BuildInfo()
    build_info.to_file(build_info_source)
