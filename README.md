# Mainspring Energy — Cloud Run Take-Home

This repo builds a small internal web service, packages it in a Docker
image, and uses Terraform to deploy it to Google Cloud Run so that only
approved identities can call it (nobody else, not even the public
internet).

## What's in this repo

```
app/         the Python web service + its Dockerfile + its tests
Terraform/   the infrastructure-as-code that deploys it to Cloud Run
.github/     a CI pipeline that runs both test suites automatically
```

## Architecture — what gets created and why

The service itself is a tiny Python program (`app/app.py`) that only
knows how to do one thing: answer `GET /` with the plain text
`Hello from <service-name>`. It uses nothing but Python's built-in
`http.server` module — no Flask, no dependencies to install — so the
Docker image is small and there's nothing extra to go wrong.

Before creating anything else, the Terraform also enables the Google
Cloud APIs this deployment needs (`run.googleapis.com`,
`iam.googleapis.com`, `cloudresourcemanager.googleapis.com`). A fresh or
rarely-used GCP project usually does **not** have the Cloud Run Admin API
turned on by default, so without this step the very first `terraform
apply` would fail with a 403 "API not enabled" error — even though
`gcloud auth application-default login` authenticated fine and the caller
is a Project Owner. Enabling them in Terraform means the whole thing works
from one `terraform apply`, with no manual `gcloud services enable`
step required first.

The Terraform in `Terraform/` then creates three things in Google Cloud:

1. **A Cloud Run service** that runs the Docker image you give it
   (`var.image`). This is the thing that actually serves traffic.
2. **A dedicated service account** made just for this Cloud Run service,
   instead of letting it run as the default "compute" account that GCP
   creates automatically. This follows the least-privilege idea: this
   identity can only do what this one service needs, nothing more.
3. **IAM invoker permissions** — this is what makes the service
   "internal." Cloud Run services are private by default: nobody can
   call them unless they're explicitly granted the `roles/run.invoker`
   permission. This Terraform grants that permission only to the exact
   list of identities you pass in (`var.invoker_members`). Nobody is
   granted `allUsers`, ever — that's what would make a service public,
   and it's never used anywhere in this code. There's even a safety
   check built into the Terraform variable itself: if someone
   accidentally tries to pass `allUsers` as an invoker, Terraform
   refuses to run rather than silently making the service public.

Terraform only asks for four inputs: `project_id`, `region`,
`image`, and `invoker_members`. Everything else that doesn't change
between deployments (the service's name, the service account's name,
the port it listens on) is set once inside the Terraform code as fixed
values, so nobody has to remember to pass them in every time.

There's no remote backend configured, so Terraform keeps track of what
it created in a local file (`terraform.tfstate`) instead of a shared
cloud location — that's expected and fine for this exercise. There are
also no credentials written into the code anywhere; Terraform simply
uses whatever Google Cloud login is already active on the machine
running it (via `gcloud auth application-default login`).

## Assumptions made beyond what's listed

- The Docker image is built and pushed to Docker Hub as a public image
  (`mandarphapale1234/mainspring:latest`) ahead of time. Terraform does
  not build or push the image — it only tells Cloud Run which existing
  image to pull.
- `invoker_members` is left empty by default on purpose. Whoever
  actually deploys this decides who's allowed to call the service by
  passing that list in at deploy time (for example, their own GCP user
  account or a service account) — this repo doesn't hardcode a specific
  person or account.
- No VPC, VPC connector, or Artifact Registry is set up, since Cloud
  Run's built-in IAM permission check is enough to satisfy "internal
  only" for this exercise — we don't also need network-level isolation.
- The GCP project this gets deployed into isn't fixed anywhere in the
  code; it's always supplied as `var.project_id`, so the same Terraform
  works in any project.
- Whoever runs `terraform apply` (via `gcloud auth application-default
  login`) is assumed to have Owner or Editor rights on the target
  project — true by default for a project someone created themselves in
  their own account, which is enough to create service accounts, create
  the Cloud Run service, set IAM policy on it, and enable the required
  APIs.
- Billing is assumed to already be enabled on the target GCP project.
  Cloud Run requires an active billing account even for usage that stays
  within the free tier, and that's an account-level setup step Terraform
  can't do on someone's behalf.

## How to build and run the container locally

```bash
cd app
docker build -t mainspring-energy-service .
docker run --rm -p 8080:8080 mainspring-energy-service

# in another terminal:
curl localhost:8080/
# -> Hello from mainspring-energy-service
```

## How to build and push the image for Cloud Run

Cloud Run only runs `linux/amd64` images. If you build on an Apple
Silicon Mac (or any arm64 machine) with a plain `docker build`, Docker
targets your machine's own architecture (arm64) by default, and
`terraform apply` will fail with an error like:

```
Cloud Run does not support image '...': Container manifest type
'...' must support amd64/linux.
```

Always build with `--platform linux/amd64` explicitly when pushing the
image Terraform will deploy:

```bash
cd app
docker build --platform linux/amd64 -t <your-dockerhub-user>/mainspring:latest .
docker push <your-dockerhub-user>/mainspring:latest
```

Then point `var.image` (in `Terraform/terraform.tfvars`) at that exact
tag.

## How to run the tests

There are two independent test suites, and neither one needs real
Google Cloud credentials to run.

**App tests** — spin up the actual `python3 app.py` process (the same
command the Docker image runs) and send it real HTTP requests:

```bash
cd app
python3 -m unittest discover -s tests -v
```

**Terraform tests** — use Terraform's own built-in test framework
(`terraform test`, needs Terraform 1.7 or newer) with a mocked Google
provider, so it checks that the configuration would create the right
resources — the dedicated service account, the right image, the right
invoker bindings, and that `allUsers` gets rejected — without ever
calling a real Google API or needing credentials:

```bash
cd Terraform
terraform init -backend=false
terraform test
```

Both suites also run automatically on every push and pull request via
GitHub Actions (`.github/workflows/ci.yml`), and neither job needs any
secrets configured in GitHub, since the Terraform tests are mocked.

## Deploying for real

`Terraform/terraform.tfvars` already holds the deploy values
(`project_id`, `region`, `image`, `invoker_members`) — edit that file
directly if any of them need to change, then:

```bash
gcloud auth application-default login

cd Terraform
terraform init
terraform apply
```

## Tradeoffs and what I'd do differently with more time

- **Image registry**: Docker Hub was the simplest way to satisfy "any
  public registry Cloud Run can pull from." With more time I'd use
  Google Artifact Registry with Cloud Build instead, so the image gets
  vulnerability-scanned and never has to be public.
- **State**: local Terraform state is fine solo, but it doesn't scale
  to a team — a real project would use a remote backend (a GCS bucket)
  with locking so two people can't apply at the same time.
- **Testing depth**: the Terraform tests check the plan (what Terraform
  *would* create) rather than a real deployment, since that needs no
  credentials or live project. With more time I'd add a separate,
  optional CI job that actually deploys to a throwaway project and
  tears it down again, to catch anything the mocked tests can't see.
- **Health checks**: the service only has the one `/` endpoint the
  assignment asked for. A real service would likely split that into a
  `/healthz` for infrastructure checks and a separate endpoint for
  actual traffic.
- **CI/CD credentials**: if this pipeline ever needed to actually
  deploy from GitHub Actions, I'd set up Workload Identity Federation
  rather than storing a long-lived GCP key as a GitHub secret.
- **Multiple environments**: right now there's one Terraform
  configuration for whatever project you point it at. A real setup
  would likely separate dev/staging/prod, either as separate
  directories or Terraform workspaces.
