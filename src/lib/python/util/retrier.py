#!/usr/bin/env python3
"""retrier module"""
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

from retry import retry

from util.logger import LOGGER


# pylint would prefer that this entire class be turned into a function which tracks its state
# internally.  This would be possible if adding the optional 'tries' and 'delay' variables to the
# calling signature didn't cause ambiguity with the *args and **kwargs passed to the retried method.
# Instead, we use this class as a container for optionally injecting the 'tries' and 'delay'
# variables as state which is external to the signature.  For example:
# retrier = Retrier(some_function, value1, arg2=value2) # unambiguous calling signature
# retrier.tries = 5                                     # state declared optionally
# retrier.execute()                                     # state gets injected into signature here
# pylint: disable=too-few-public-methods
class Retrier:
    """Wrapper class for retry execution using the retry decorator"""
    def __init__(self, func, *args, **kwargs):
        self.func = func
        self.args = args
        self.kwargs = kwargs
        self.tries = 10
        self.delay = 30
        self.logs = []

        # Determine log files to record progress to
        for handler in LOGGER.handlers:
            # pylint is worried because _CapturingHandler doesn't have a .baseFilename member.
            # This is actually irrelevant because _CapturingHandler is a pibling of FileHandler and
            # will never pass the isinstance check.
            # pylint: disable=no-member
            if isinstance(handler, logging.FileHandler):
                self.logs.append(handler.baseFilename)

    def _record(self, content):
        """Prints progress info to console and logs files"""
        print(content, end='', flush=True)
        for log in self.logs:
            with open(log, 'a+') as file:
                file.write(content)

    def execute(self):
        """Calls the function defined in the constructor with the arguments provided to the
        constructor.  Retries the function call <tries> times if it fails to return True.  Logs
        progress to the console as well as any file handlers attached to LOGGER."""
        @retry(AssertionError, tries=self.tries, delay=self.delay)
        def _execute():
            """In order to access self.tries and self.delay_secs the retry decorator must be
            declared within the scope of the Retrier class.  We accomplish this be applying the
            decorator to an inner function within the class scope of the outer method."""
            _execute.remaining -= 1
            if self.func(*self.args, **self.kwargs):
                self._record('\n')
                return True
            self._record('.')
            if _execute.remaining < 1:
                self._record('\n')
                return False
            raise AssertionError('{} tries remaining'.format(_execute.remaining))
        _execute.remaining = self.tries
        if _execute():
            return True
