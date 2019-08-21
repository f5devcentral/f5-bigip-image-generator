#!/usr/bin/env python3
"""Python API command handler"""
# Copyright (C) 2018-2019 F5 Networks, Inc
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
import sys
import json
import aliyunsdkcore.request

from aliyunsdkcore.client import AcsClient
from aliyunsdkcore.acs_exception.exceptions import ClientException
from aliyunsdkcore.acs_exception.exceptions import ServerException
from aliyunsdkecs.request.v20140526.AddTagsRequest \
    import AddTagsRequest
from aliyunsdkecs.request.v20140526.ImportImageRequest \
    import ImportImageRequest
from aliyunsdkecs.request.v20140526.DeleteImageRequest \
    import DeleteImageRequest
from aliyunsdkecs.request.v20140526.DescribeImagesRequest \
    import DescribeImagesRequest
from aliyunsdkecs.request.v20140526.DescribeImageSharePermissionRequest \
    import DescribeImageSharePermissionRequest
from aliyunsdkecs.request.v20140526.DescribeTaskAttributeRequest \
    import DescribeTaskAttributeRequest
from aliyunsdkecs.request.v20140526.CancelTaskRequest \
    import CancelTaskRequest
from aliyunsdkecs.request.v20140526.ModifyImageSharePermissionRequest \
    import ModifyImageSharePermissionRequest


def get_acs_client(region):
    """Return client to Alibaba cloud.
       Requires environment variables ALIBABA_ACCESS_KEY_ID and
       ALIBABA_ACCESS_KEY_SECRET to be set.
    """
    if os.environ.get('ALIBABA_ACCESS_KEY_ID') is None:
        print('ALIBABA_ACCESS_KEY_ID environment variable is not defined' \
            + ', exit.')
        sys.exit(1)

    if os.environ.get('ALIBABA_ACCESS_KEY_SECRET') is None:
        print('ALIBABA_ACCESS_KEY_SECRET environment variable is not defined' \
            + ', exit.')
        sys.exit(1)

    client = AcsClient(
        os.environ.get('ALIBABA_ACCESS_KEY_ID'),
        os.environ.get('ALIBABA_ACCESS_KEY_SECRET'), region)
    return client


def send_request(request, region):
    """Send request to Alibaba cloud."""
    aliyunsdkcore.request.set_default_protocol_type("https")
    request.set_protocol_type("https")
    request.set_accept_format('json')
    try:
        client = get_acs_client(region)
        response_str = client.do_action(request)
        response_detail = json.loads(response_str)
        return response_detail
    except (ClientException, ServerException) as exc:
        print('exception in send_request: %s, exit.' % exc)
        sys.exit(1)


def import_image(oss_bucket, oss_object, image_name, description, disk_size):
    """Request image import based on the previously uploaded disk (oss_object).
       Print the whole response.
    """
    oss_image = [{
        'OSSBucket': oss_bucket, 'OSSObject': oss_object,
        'DiskImSize': disk_size}]
    request = ImportImageRequest()
    request.set_DiskDeviceMappings(oss_image)
    request.set_OSType('Linux')
    request.set_Architecture('x86_64')
    request.set_Platform('Others Linux')
    request.set_ImageName(image_name)
    request.set_Description(description)
    # successful request has "ImageId" attribute
    # unsuccessful has "Code": "InvalidImageName.Duplicated" pair
    return request


def describe_images(image_id, image_name):
    """Print description of an image with matching id or name."""
    request = DescribeImagesRequest()
    if image_id:
        request.set_ImageId(image_id)
    if image_name:
        request.set_ImageName(image_name)
    return request


def describe_image_share_permission(image_id):
    """Print description of an image's share permissions"""
    if image_id is None or not image_id:
        raise Exception('No image id provided')
    request = DescribeImageSharePermissionRequest()
    if image_id:
        request.set_ImageId(image_id)
    return request


def delete_image(image_id):
    """Delete image by image id."""
    if image_id is None or not image_id:
        raise Exception('No image id was provided')
    request = DeleteImageRequest()
    request.set_ImageId(image_id)
    return request


def describe_task_attribute(task_id):
    """Print description of a task with matching id."""
    request = DescribeTaskAttributeRequest()
    request.set_TaskId(task_id)
    return request


def cancel_task(task_id):
    """Cancel task by task id."""
    if task_id is None or not task_id:
        raise Exception('No task id was provided')
    request = CancelTaskRequest()
    request.set_TaskId(task_id)
    return request


def add_tags(resource_id, resource_type, tags_str):
    """Add Resource Tags by resource id."""
    if resource_id is None or not resource_id:
        raise Exception('No resource id was provided')
    if resource_type is None or not resource_type:
        raise Exception('No resource type was provided')
    if tags_str is None or not tags_str:
        raise Exception('No tags string was provided')

    # Transform tags string to tags array
    tags_dict = dict(item.split("=") for item in tags_str.split(","))
    tags_array = []
    for key, value in tags_dict.items():
        array_entry = {"Key":key, "Value":value}
        tags_array.append(array_entry)

    request = AddTagsRequest()
    request.set_ResourceId(resource_id)
    request.set_ResourceType(resource_type)
    request.set_Tags(tags_array)
    return request


def modify_image_share_permission(image_id, accounts_str):
    """Share image with accounts by image id"""
    if image_id is None or not image_id:
        raise Exception('No image id was provided')
    if accounts_str is None or not accounts_str:
        raise Exception('No accounts string was provided')

    # Transform accounts string to account array
    accounts_array = accounts_str.split(",")

    request = ModifyImageSharePermissionRequest()
    request.set_ImageId(image_id)
    request.set_AddAccounts(accounts_array)
    return request


# commands and args
COMMAND_MAP = {
    'add_tags': ['resource_id', 'resource_type', 'tags_str', 'region'],
    'cancel_task': ['task_id', 'region'],
    'delete_image': ['image_id', 'region'],
    'describe_images': ['image_id', 'image_name', 'region'],
    'describe_image_share_permission': ['image_id', 'region'],
    'describe_task_attribute': ['task_id', 'region'],
    'import_image':
        ['oss_bucket', 'oss_object', 'image_name', 'description', 'disk_size', 'region'],
    'modify_image_share_permission': ['image_id', 'accounts_str', 'region']
}


def main():
    """main command handler"""

    # get command
    try:
        command = sys.argv[1]
    except IndexError:
        print('No command supplied')
        raise

    # log command - currently all commands have at least one arg
    if len(sys.argv) == 2:
        raise Exception('No args supplied')
    print(os.path.basename(__file__) + ' is called with ' \
        + ' '.join(sys.argv[1:]))

    # check args
    if len(sys.argv) != (len(COMMAND_MAP[command]) + 2):
        raise Exception('Incorrect number of arguments to %s supplied.  Expecting %s' % \
                        (command, COMMAND_MAP[command]))

    # map command args to keyword args
    command_kw_args = dict(zip(COMMAND_MAP[command], sys.argv[2:]))

    # get region (and remove it from the keyword args map)
    region = command_kw_args.pop('region')

    # call command with remaining keyword args to get request object
    request = globals()[command](**command_kw_args)

    # send request and dump the response
    response = send_request(request, region)
    print(json.dumps(response, sort_keys=True, indent=4, separators=(',', ': ')))


if __name__ == "__main__":
    main()
