#!/usr/bin/env python3

"""publish build information to telemetry"""
# Copyright (C) 2019-2020 F5 Networks, Inc
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


import sys
import uuid
from os import environ
from urllib3.exceptions import ReadTimeoutError

from f5teem import AnonymousDeviceClient

from telemetry.build_info_telemetry import BuildInfoTelemetry
from util.logger import LOGGER
from util.misc import create_log_handler
from util.retrier import Retrier
from util.config import get_config_value

def main():
    """main publish telemetry information function"""
    # create log handler for the global LOGGER
    create_log_handler()

    # gather telemetry info
    build_info_telemetry = BuildInfoTelemetry()
    LOGGER.debug(build_info_telemetry.build_info)

    version = build_info_telemetry.build_info['product']['version']

    # Check if specific api key is set, if not use default
    if environ.get("F5_TEEM_API_KEY") is not None:
        environ['F5_TEEM_API_ENVIRONMENT'] = "staging"
        f5_api_key = environ.get("F5_TEEM_API_KEY")
    else:
        f5_api_key = 'mmhJU2sCd63BznXAXDh4kxLIyfIMm3Ar'

    generated_uuid = str(uuid.uuid4())
    LOGGER.debug("telemetry UUID: %s", generated_uuid)
    client_info = {
        'name': 'f5-image-generator',
        'version': str(version),
        'id': generated_uuid
    }
    telemetry_client = AnonymousDeviceClient(
        client_info, api_key=f5_api_key)

    retrier = Retrier(_publish_telemetry_database, build_info_telemetry, telemetry_client)
    retrier.tries = int(get_config_value('PUBLISH_TELEMETRY_TASK_RETRY_COUNT'))
    retrier.delay = int(get_config_value('PUBLISH_TELEMETRY_TASK_RETRY_DELAY'))
    if retrier.execute():
        LOGGER.info("Publishing to telemetry success.")
        return True
    LOGGER.info("Publishing to telemetry did not succeed.")
    sys.exit(0)


def _publish_telemetry_database(build_info_telemetry, telemetry_client):
    """Retry function for publishing to telemetry servers."""
    LOGGER.info('Attempt to post telemetry data.')
    try:
        telemetry_client.report(
            build_info_telemetry.build_info,
            telemetry_type='Installation Usage',
            telemetry_type_version='1'
        )
    except ReadTimeoutError:
        LOGGER.error("ReadTimeoutError occured during publishing to telemetry database")
        return False
    return True


if __name__ == "__main__":
    main()
