#!/usr/bin/env bash

# Copyright 2019 the Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#
# This script prepares a blank GCP project to run the rest of the scripts.
#

set -eEuo pipefail

gcloud services enable --project "${PROJECT_ID}" \
  binaryauthorization.googleapis.com \
  cloudbuild.googleapis.com \
  cloudkms.googleapis.com \
  cloudmonitoring.googleapis.com \
  cloudresourcemanager.googleapis.com \
  cloudshell.googleapis.com \
  compute.googleapis.com \
  container.googleapis.com \
  containeranalysis.googleapis.com \
  containerregistry.googleapis.com \
  containerscanning.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  oslogin.googleapis.com

gcloud services enable --project "${PROJECT_ID}" \
  pubsub.googleapis.com \
  run.googleapis.com \
  serviceusage.googleapis.com \
  sourcerepo.googleapis.com \
  stackdriver.googleapis.com \
  storage-api.googleapis.com \
  storage-component.googleapis.com

#
# Enable os-login across the project
#

gcloud compute project-info add-metadata \
  --project "${PROJECT_ID}" \
  --metadata "enable-oslogin=TRUE"
