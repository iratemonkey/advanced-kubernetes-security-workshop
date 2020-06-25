# Advanced Kubernetes Security Workshop

This repository contains the sample code and scripts for Kubernetes Security
Best Practices, which is a guided workshop to showcase some of Kubernetes and
GKE's best practices with respect to security.

## Setup

1.  The sample code and scripts use the following environment variables. You
    should set these to your associated values:

    ```text
    PROJECT_ID="..."
    ```

1.  Configure the project:

    ```shell
    ./bin/00-configure.sh
    ```

1.  Create a GKE cluster which will run as the attached service account:

    ```shell
    ./bin/01-create-cluster.sh
    ```

1.  Show that GKE nodes are not publicly accessible:

    ```text
    gcloud compute instances list --project $PROJECT_ID
    ```

1.  SSH into the bastion host:

    ```text
    gcloud compute ssh my-bastion \
      --project $PROJECT_ID \
      --zone us-central1-b
    ```

1.  Install `kubectl` command line tool:

    ```text
    sudo apt-get -yqq install kubectl
    ```

1.  Authenticate to talk to the GKE cluster:

    ```text
    gcloud container clusters get-credentials my-cluster \
      --region us-central1
    ```

1.  Explore cluster:

    ```text
    kubectl get po -n kube-system
    ```


### Aduit Logging

1.  Enable system-level audit logs:

    ```text
    curl -sf https://raw.githubusercontent.com/GoogleCloudPlatform/k8s-node-tools/master/os-audit/cos-auditd-logging.yaml | kubectl apply -f -
    ```

    Events will show up as "linux-auditd" events in Cloud Ops under "GCE VM Instance".

1.  To disable system audit logs:

    ```text
    kubectl delete ns cos-auditd
    ```


### Network Policy

1.  Deploy and expose an nginx container:

    ```text
    kubectl create deployment nginx --image nginx
    ```

    ```text
    kubectl expose deployment nginx --port 80
    ```

1.  Exec into a shell container and show that nginx is accessible:

    ```text
    kubectl run busybox --rm -it --image busybox /bin/sh
    ```

    ```text
    wget --spider --timeout 2 nginx
    ```

1.  Create a network policy that restricts access to the nginx pod:

    ```yaml
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: access-nginx
    spec:
      podSelector:
        matchLabels:
          app: nginx
      ingress:
      - from:
        - podSelector:
            matchLabels:
              can-nginx: "true"
    ```

    Apply this with `kubectl apply -f`.

1.  Exec into a shell container and show that nginx is no longer accessible:

    ```text
    kubectl run busybox --rm -it --image busybox /bin/sh
    ```

    ```text
    wget --spider --timeout 2 nginx
    ```

1.  Start pod with label and try again:

    ```text
    kubectl run busybox --rm -it --labels "can-nginx=true" --image busybox /bin/sh
    ```

    ```text
    wget --spider --timeout 2 nginx
    ```

1.  Delete the nginx deployment:

    ```text
    kubectl delete deployment nginx
    ```

    ```text
    kubectl delete svc nginx
    ```

    ```text
    kubectl delete networkpolicy access-nginx
    ```

### Pod Security Policy

1.  Create a psp that prevents pods from running as root:

    ```yaml
    apiVersion: extensions/v1beta1
    kind: PodSecurityPolicy
    metadata:
      name: restrict-root
    spec:
      privileged: false
      runAsUser:
        rule: MustRunAsNonRoot
      seLinux:
        rule: RunAsAny
      fsGroup:
        rule: RunAsAny
      supplementalGroups:
        rule: RunAsAny
      volumes:
      - '*'
    ```

    Apply this with `kubectl apply -f`.

1.  Update the cluster to start enforcing psp:

    ```text
    gcloud beta container clusters update my-cluster \
        --project $PROJECT_ID \
        --region us-central1 \
        --enable-pod-security-policy
    ```

    Note: this process can take many minutes on an existing cluster.


### Container Security Context

1.  First, demonstrate that a container will run as root unless otherwise
    specified:

    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: demo
    spec:
      containers:
      - name: demo
        image: busybox
        command: ["sh", "-c", "sleep 1h"]
    ```

    Apply this with `kubectl apply -f`.

1.  Show that the container is running as root:

    ```text
    kubectl exec -it demo -- /bin/sh
    ```

    ```text
    ps
    # ...

    id
    uid=0(root) gid=0(root) groups=10(wheel)

    touch foo
    # succeeds
    ```

    ```text
    kubectl delete po demo
    ```


1.  Create a container with a securityContext:

    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: demo
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 2000
        fsGroup: 3000

      containers:
      - name: demo
        image: busybox
        command: ["sh", "-c", "sleep 1h"]
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
    ```

    Apply this with `kubectl apply -f`.

1.  Show that the container is running as an unprivileged user:

    ```text
    kubectl exec -it demo -- /bin/sh
    ```

    ```text
    ps
    # ...

    id
    uid=1000 gid=2000

    touch foo
    Read-only file system
    ```

    ```text
    kubectl delete po demo
    ```

1.  Create a container with a apparmor, seccomp, and selinux options:

    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: demo
      annotations:
        seccomp.security.kubernetes.io/demo: runtime/default
        container.apparmor.security.kubernetes.io/demo: runtime/default
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 2000
        fsGroup: 3000
        seLinuxOptions:
          level: "s0:c123,c456"

      containers:
      - name: demo
        image: busybox
        command: ["sh", "-c", "sleep 1h"]
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
    ```

    Apply this with `kubectl apply -f`.

    Delete it when you're done:

    ```text
    kubectl delete po demo
    ```

### Sandbox

1.  Deploy under gvisor:

    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: demo
    spec:
      runtimeClassName: gvisor
      securityContext:
        runAsUser: 1000
        runAsGroup: 2000

      containers:
      - name: demo
        image: busybox
        command: ["sh", "-c", "sleep 1h"]
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
    ```

    Apply this with `kubectl apply -f`.

1.  Show that the container is running under gvisor:

    ```text
    kubectl get po demo -o yaml
    # runtimeClassName should be gvisor
    ```

    ```text
    kubectl delete po demo
    ```


### Workload Identity

Suppose I want to give a Kubernetes service account permissions to talk to a Google Cloud API. I can do this using Workload Identity!

Note that IAM is eventually consistent, so permission changes on the GCP service
account will not be immediately available to pods.

1.  Ensure the `--identity-namespace` flag was passed into the cluster.

1.  Create a Google service account which will be mapped to a Kubernetes Service
    Account shortly:

    ```text
    gcloud iam service-accounts create my-gcp-sa \
      --project $PROJECT_ID
    ```

1.  Give the Google service account the ability to mint tokens:

    ```text
    gcloud projects add-iam-policy-binding $PROJECT_ID \
      --role roles/iam.serviceAccountTokenCreator \
      --member "serviceAccount:my-gcp-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    ```

1.  Give the Google service account viewer permissions (so we can test them
    later inside a pod):

    ```text
    gcloud projects add-iam-policy-binding $PROJECT_ID \
      --role roles/viewer \
      --member "serviceAccount:my-gcp-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    ```

1.  Create a Kubernetes Service Account:

    ```text
    kubectl create serviceaccount my-k8s-sa
    ```

1.  Allow the KSA to use the GSA:

    ```text
    gcloud iam service-accounts add-iam-policy-binding \
      --project $PROJECT_ID \
      --role roles/iam.workloadIdentityUser \
      --member "serviceAccount:${PROJECT_ID}.svc.id.goog[default/my-k8s-sa]" \
      my-gcp-sa@${PROJECT_ID}.iam.gserviceaccount.com
    ```

    ```text
    kubectl annotate serviceaccount my-k8s-sa \
      iam.gke.io/gcp-service-account=my-gcp-sa@${PROJECT_ID}.iam.gserviceaccount.com
    ```

1.  Deploy a pod with the attached service account:

    ```text
    kubectl run -it --rm \
      --image gcr.io/google.com/cloudsdktool/cloud-sdk:slim \
      --serviceaccount my-k8s-sa \
      demo
    ```

    ```text
    gcloud auth list
    ```

    ```text
    gcloud compute instances list
    ```

    ```text
    gcloud compute instances create foo --zone us-central1-b # fails
    ```


### Binary Authorization Demo

See [sethvargo/binary-authorization-demo](https://github.com/sethvargo/binary-authorization-demo).
