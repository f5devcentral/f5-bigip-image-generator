"""logging helpers"""
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



import logging

LOGGER_NAME = 'image-generator'

# Add custom trace log level to logger and all associated instances
logging.TRACE = 5
logging.addLevelName(logging.TRACE, 'TRACE')

def _log_trace(self, message, *args, **kwargs):
    """Trace level logging function"""
    if self.isEnabledFor(logging.TRACE):
        # This is the pattern to hook a custom log level into
        # the logger without declaring a derived class.
        # pylint:disable=protected-access
        self._log(logging.TRACE, message, args, **kwargs)

# Attach function to logger.  Allows use of LOGGER.trace()
logging.Logger.trace = _log_trace


def _create_logger():
    """
    local method to create the top level logger, which, by default
     - adds a custom trace log level and set the logger level to trace
     - creates a stream handler to write message to console
     - sets stream handler level to 'INFO'
     - sets stream handler formatting to just the message itself
    """
    # Get top level logger
    logger = logging.getLogger(LOGGER_NAME)

    # Set log level to trace,  Handlers filter messages, so to keep things
    # simple, the logger log level will pass all messages.
    logger.setLevel(logging.TRACE)

    # Create and add stream handler
    c_h = logging.StreamHandler()
    c_h.setLevel(logging.INFO)
    c_h.setFormatter(logging.Formatter('%(message)s'))
    logger.addHandler(c_h)

    return logger

LOGGER = _create_logger()

def derive_logger(name):
    """
    derive a new logger from the top level one, so the new name is
    '<LOGGER_NAME>.<name>'
     - name: string to be appended to top level logger name
    """

    return logging.getLogger('{0}.{1}'.format(LOGGER_NAME, name))

def create_file_handler(logger, path, log_level, mode='a'):
    """
    create a file handler with given <path> and add it to given <logger>
     - logger: logger to accept the created file handler to
     - path: file path to write logs to
    """

    f_h = logging.FileHandler(path, mode)
    f_h.setLevel(log_level)
    f_h.setFormatter(logging.Formatter('%(asctime)s %(name)s %(levelname)s - %(message)s', \
        '%Y-%m-%d %H:%M:%S'))
    logger.addHandler(f_h)
