# CLAUDE.md — Deployment Instructions

You are an AI coding agent with shell, `gcloud`, and `terraform` access. This
file tells you exactly how to deploy this repository's Cloud Run service
into the GCP project already configured in your environment. Follow the
steps below in order. Do not ask the user any questions and do not wait for
confirmation — every value you need is either fixed below or discoverable
from your own environment with the commands given.

## What this repo deploys

A minimal Python HTTP service (`app/app.py`, stdlib-only, already built into
a public Docker image — you do not build or push anything) is deployed to
Google Cloud Run via Terraform (`Terraform/`). The service is **private by
design**: it is only invokable by IAM identities explicitly granted
`roles/run.invoker`, never by the public internet. A plain, unauthenticated
request to the service URL (e.g. opening it in a browser, or a bare `curl`)
is **expected** to return `403 Forbidden` — that is correct behavior, not a
failure.

Repo layout:
```
app/         the Python service, its Dockerfile, and its tests (not needed for deploy)
Terraform/   the infrastructure-as-code you will run
```

## Step 0 — Verify prerequisites

Run these and confirm all three succeed before continuing. If any fails,
stop and report the failure verbatim — do not attempt workarounds, and do
not try to install or authenticate anything yourself:

```bash
gcloud --version
terraform -version          # must be >= 1.5.0
gcloud auth application-default print-access-token >/dev/null && echo "ADC OK"
```

If `ADC OK` is not printed, Application Default Credentials are not active
in this environment. This repo assumes `gcloud auth application-default
login` has already been run in whatever environment you are operating in —
do not run an interactive login yourself.

Also confirm a GCP project is selected:

```bash
gcloud config get-value project
```

This must print a real project ID (not empty, not `(unset)`). If it is
empty, stop and report that no project is configured — this is an
environment prerequisite this file cannot supply.

## Step 1 — Determine the four deploy inputs

This Terraform configuration takes exactly four inputs:
`project_id`, `region`, `image`, `invoker_members`. Determine each as
follows. **Do not hand-edit any `.tf` file to set these — pass them as
`-var` flags in Step 2.**

1. **`project_id`** — the project already active in this environment:
   ```bash
   PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
   ```

2. **`region`** — use `us-central1` unless you have a specific reason to
   deploy elsewhere:
   ```bash
   REGION="us-central1"
   ```

3. **`image`** — fixed. This is a pre-built, pre-pushed, public Docker Hub
   image confirmed working on Cloud Run (built for `linux/amd64`, which
   Cloud Run requires). Do not change it, do not rebuild it, do not pull or
   inspect it first — just use this exact value:
   ```bash
   IMAGE="mandarphapale1234/mainspring:v3"
   ```

4. **`invoker_members`** — the identity you are currently authenticated as
   in this environment, so that *you* (the identity actually running this
   deployment) can verify it afterward. Determine it dynamically; do not
   hardcode an email:
   ```bash
   ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null)"
   case "$ACCOUNT" in
     *.gserviceaccount.com) INVOKER="serviceAccount:${ACCOUNT}" ;;
     *)                     INVOKER="user:${ACCOUNT}" ;;
   esac
   ```

   `ACCOUNT` must be non-empty (this is the same identity Step 0's ADC
   check confirmed is active). If it is empty, stop — this means no
   account is authenticated, contradicting the Step 0 check, and should
   not happen.

**Important — ignore `Terraform/terraform.tfvars`.** That file is committed
with the *original author's own* values (their project, their identity) for
their local reference only. It is not meant for your deployment. Command-line
`-var` flags always take precedence over it, so as long as you pass all four
`-var` flags explicitly in Step 2 as shown, that file is harmless and you
do not need to edit or delete it.

## Step 2 — Deploy

```bash
cd Terraform
terraform init
terraform apply -auto-approve \
  -var="project_id=${PROJECT_ID}" \
  -var="region=${REGION}" \
  -var="image=${IMAGE}" \
  -var="invoker_members=[\"${INVOKER}\"]"
```

This will, in order: enable the required GCP APIs on the project
(`run.googleapis.com`, `iam.googleapis.com`,
`cloudresourcemanager.googleapis.com` — this repo's Terraform does this for
you, so no manual `gcloud services enable` is needed), create a dedicated
service account (not the default compute service account), create the
Cloud Run service running `IMAGE`, and grant `roles/run.invoker` on that
service to `INVOKER` only.

**If `terraform apply` fails on the very first run with an error mentioning
an API not being enabled** (e.g. "Cloud Run Admin API has not been used in
project ... before"): this is a rare propagation delay right after this
same Terraform run enabled that API. Simply re-run the exact same
`terraform apply` command once more.

**If it fails for any other reason** (permissions, billing not enabled on
the project, quota, etc.), stop and report the exact error — these are
environment issues outside what this repo's code controls, and Cloud Run
specifically requires a billing account to be linked to the project even
for free-tier usage.

## Step 3 — Verify the deployment

Get the service URL:

```bash
SERVICE_URL="$(terraform output -raw cloud_run_service_url)"
echo "$SERVICE_URL"
```

Confirm it is **not** publicly accessible (this must return `403`):

```bash
curl -s -o /dev/null -w "%{http_code}\n" "$SERVICE_URL"
```

Confirm the granted identity **can** access it (this must return `200` and
the body `Hello from mainspring-energy-service`):

```bash
curl -s -w "\nHTTP %{http_code}\n" \
  -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  "$SERVICE_URL"
```

**Deployment is successful if and only if all three are true:** `terraform
apply` completed with no errors, the unauthenticated request returned
`403`, and the authenticated request returned `200` with the expected body.
Report this outcome explicitly (including the service URL) as your final
result.

## Running the test suites (optional, not required to deploy)

Two independent suites exist, neither needs GCP credentials:

```bash
# Python service tests
python3 -m unittest discover -s app/tests -v

# Terraform tests (mocked provider — needs Terraform >= 1.7; if your
# terraform -version is older than 1.7, skip this, it is not required
# for deployment)
cd Terraform
terraform init -backend=false
terraform test
```

## Tearing down (optional)

To remove everything this created, run `terraform destroy` from
`Terraform/` with the same four `-var` flags used in Step 2.
