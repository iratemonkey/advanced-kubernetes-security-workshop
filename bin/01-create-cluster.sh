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
# This script creates a bastion host, networking fabric, and a completely
# private (no public access) GKE cluster.
#

set -eEuo pipefail

#
# Create GKE node service account
#

gcloud iam service-accounts create "my-node-sa" \
  --project "${PROJECT_ID}"

for role in "logging.logWriter" "monitoring.metricWriter" "monitoring.viewer" "stackdriver.resourceMetadata.writer" "cloudtrace.agent" "iam.serviceAccountTokenCreator"; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member "serviceAccount:my-node-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role "roles/${role}"
done

#
# Create a dedicated network (VPC)
#

gcloud compute networks create "my-network" \
  --project "${PROJECT_ID}" \
  --subnet-mode "custom"

gcloud compute networks subnets create "my-subnet-us-central1-192" \
  --project "${PROJECT_ID}" \
  --region "us-central1" \
  --network "my-network" \
  --range "192.168.1.0/24"

#
# Create a bastion host
#

gcloud iam service-accounts create "my-bastion-sa" \
  --project "${PROJECT_ID}"

for role in "owner" "container.admin" "iam.serviceAccountAdmin"; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member "serviceAccount:my-bastion-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role "roles/${role}"
done

gcloud compute instances create "my-bastion" \
  --project "${PROJECT_ID}" \
  --image-project "debian-cloud" \
  --image-family "debian-10" \
  --network "my-network" \
  --subnet "my-subnet-us-central1-192" \
  --zone "us-central1-b" \
  --tags "allow-ssh" \
  --can-ip-forward \
  --shielded-integrity-monitoring \
  --shielded-secure-boot \
  --scopes "cloud-platform" \
  --service-account "my-bastion-sa@${PROJECT_ID}.iam.gserviceaccount.com"

#
# Create a firewall rule that enables SSHing to our bastion host
#

gcloud compute firewall-rules create "allow-ssh" \
  --project "${PROJECT_ID}" \
  --network "my-network" \
  --allow "tcp:22" \
  --target-tags "allow-ssh"

#
# Create a KMS key for GKE Application Layer Encryption of Kubernetes secrets
#

gcloud kms keyrings create "gke" \
  --project "${PROJECT_ID}" \
  --location "us-central1"

gcloud kms keys create "secrets" \
  --project "${PROJECT_ID}" \
  --keyring "gke" \
  --location "us-central1" \
  --purpose encryption \
  --protection-level "hsm"

gcloud kms keys add-iam-policy-binding "secrets" \
  --project "${PROJECT_ID}" \
  --keyring "gke" \
  --location "us-central1" \
  --member "serviceAccount:my-node-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role "roles/cloudkms.cryptoKeyEncrypterDecrypter"

PROJECT_NUMBER="$(gcloud projects describe ${PROJECT_ID} --format 'value(projectNumber)')"
gcloud kms keys add-iam-policy-binding "secrets" \
  --project "${PROJECT_ID}" \
  --keyring "gke" \
  --location "us-central1" \
  --member "serviceAccount:service-${PROJECT_NUMBER}@container-engine-robot.iam.gserviceaccount.com" \
  --role "roles/cloudkms.cryptoKeyEncrypterDecrypter"



#
# Create NAT router so nodes can egress
#

gcloud compute routers create "my-nat-router" \
  --project "${PROJECT_ID}" \
  --region "us-central1" \
  --network "my-network"

gcloud compute routers nats create "my-nat-config" \
  --project "${PROJECT_ID}" \
  --router-region "us-central1" \
  --router "my-nat-router" \
  --nat-all-subnet-ip-ranges \
  --auto-allocate-nat-external-ips


#
# Create the GKE cluster
#

gcloud beta container clusters create "my-cluster" \
  --project "${PROJECT_ID}" \
  --region "us-central1" \
  --num-nodes "1" \
  --node-version "1.15" \
  --cluster-version "1.15" \
  --machine-type "n1-standard-2" \
  --image-type "cos_containerd" \
  --network "my-network" \
  --subnetwork "my-subnet-us-central1-192" \
  --master-ipv4-cidr "172.16.0.0/28" \
  --cluster-ipv4-cidr "/16" \
  --services-ipv4-cidr "/22" \
  --service-account "my-node-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --database-encryption-key "projects/${PROJECT_ID}/locations/us-central1/keyRings/gke/cryptoKeys/secrets" \
  --enable-ip-alias \
  --enable-private-nodes \
  --enable-private-endpoint \
  --enable-master-authorized-networks \
  --master-authorized-networks "192.168.1.0/24" \
  --enable-stackdriver-kubernetes \
  --enable-binauthz \
  --enable-intra-node-visibility \
  --enable-network-policy \
  --workload-metadata-from-node "GKE_METADATA_SERVER" \
  --identity-namespace "${PROJECT_ID}.svc.id.goog" \
  --addons "HorizontalPodAutoscaling,HttpLoadBalancing,NetworkPolicy" \
  --scopes "cloud-platform" \
  --no-enable-legacy-authorization \
  --no-enable-basic-auth \
  --no-issue-client-certificate \
  --metadata "disable-legacy-endpoints=true" \
  --maintenance-window "2:00"

# gcloud beta container node-pools create sandboxed \
#   --project "${PROJECT_ID}" \
#   --cluster "my-cluster" \
#   --region "us-central1" \
#   --num-nodes "1" \
#   --node-version "1.15" \
#   --machine-type "n1-standard-2" \
#   --image-type "cos_containerd" \
#   --sandbox "type=gvisor" \
#   --service-account "my-node-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
#   --workload-metadata-from-node "GKE_METADATA_SERVER" \
#   --scopes "cloud-platform" \
#   --metadata "disable-legacy-endpoints=true"

#
# The following options can be added to further increase cluster security. They
# make use of TPMs and secure boot modules to verify system integrity. I don't
# include them here because they add about 10 minutes to node pool creation
# time.
#
# --shielded-integrity-monitoring \
# --shielded-secure-boot \
# --enable-shielded-nodes


#
# Give cos-auditd permissions to write logs. This is require because of workload
# identity.
#

gcloud iam service-accounts add-iam-policy-binding \
  --project "${PROJECT_ID}" \
  --role "roles/iam.workloadIdentityUser" \
  --member "serviceAccount:${PROJECT_ID}.svc.id.goog[cos-auditd/default]" \
  "my-node-sa@${PROJECT_ID}.iam.gserviceaccount.com"
