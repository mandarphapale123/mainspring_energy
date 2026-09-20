# Mainspring Energy Cloud Run Assignment

This repo has a small internal web service packaged as a Docker image, plus Terraform that deploys it to Google Cloud Run so that only approved people or service accounts can actually call it.

## What's in here

`app/` has the Python service, its Dockerfile, and its tests.

`Terraform/` has the infrastructure code that deploys the service to Cloud Run.

`.github/` has a CI pipeline that runs both test suites on every push and pull request.

## Architecture, and why it's built this way

The service itself is a small Python script (`app/app.py`). It only does one thing: `GET /` returns the plain text `Hello from <service name>`. It uses nothing outside Python's standard library, so there's no Flask and no pip install step, which keeps the Docker image small and keeps the number of things that can go wrong low.

Before creating anything, the Terraform also turns on the GCP APIs the deployment needs (`run.googleapis.com`, `iam.googleapis.com`, `cloudresourcemanager.googleapis.com`). A fresh or rarely used GCP project usually doesn't have the Cloud Run Admin API enabled by default, so without this step the very first `terraform apply` would fail with a 403 "API not enabled" error, even if you're logged in correctly and own the project. Turning the APIs on inside Terraform means the whole deploy works from one `terraform apply`, with no `gcloud services enable` step needed first.

The Terraform then creates three things in Google Cloud:

1. A Cloud Run service that runs whatever image you give it (`var.image`). This is the piece that actually serves traffic.
2. A dedicated service account made just for this service, instead of letting it run as the default compute account that GCP creates automatically. It only has the permissions this one service actually needs.
3. IAM invoker permissions. This is the part that keeps the service internal. Cloud Run services are private by default, nobody can call them unless they're explicitly granted the `roles/run.invoker` permission. This Terraform grants that permission only to the identities listed in `var.invoker_members`. Nobody ever gets `allUsers`, that's what would make the service public, and it's not used anywhere in this code. There's also a validation rule on the variable itself, so if someone accidentally tries to pass `allUsers` in, Terraform refuses to even plan.

Terraform only asks for four inputs: `project_id`, `region`, `image`, and `invoker_members`. Everything that doesn't change between deployments (the service name, the service account name, the port) is set once as a local value in the code, so nobody has to remember to pass it in every time.

There's no remote backend configured, so Terraform keeps track of what it created in a local file (`terraform.tfstate`). That's expected for this exercise. There are also no credentials written into the code anywhere. Terraform just uses whatever Google Cloud login is already active on the machine running it, via `gcloud auth application-default login`.

## Assumptions I made beyond what's listed

The Docker image is built and pushed to Docker Hub as a public image ahead of time. Terraform doesn't build or push the image, it only tells Cloud Run which existing image to pull.

`invoker_members` is empty by default on purpose. Whoever actually deploys this decides who's allowed to call the service, by passing that list in at deploy time. This repo doesn't hardcode a specific person or account.

There's no VPC connector or Artifact Registry set up. Cloud Run's built in IAM check already satisfies "internal only" for this exercise, so network level isolation on top of it didn't seem necessary.

The GCP project isn't fixed anywhere in the code, it's always supplied as `var.project_id`, so the same Terraform works in any project.

Whoever runs `terraform apply` is assumed to have Owner or Editor rights on the target project. That's the default for a project someone created themselves, and it's enough to create service accounts, create the Cloud Run service, set IAM policy on it, and enable the required APIs.

Billing is assumed to already be enabled on the target GCP project. Cloud Run needs an active billing account even for usage that stays inside the free tier, and that's an account level setup step Terraform can't do on someone's behalf.

## Building and running the container locally

```bash
cd app
docker build -t mainspring-energy-service .
docker run --rm -p 8080:8080 mainspring-energy-service

# in another terminal:
curl localhost:8080/
# Hello from mainspring-energy-service
```

## Building and pushing the image for Cloud Run

Cloud Run only runs `linux/amd64` images. If you build on an Apple Silicon Mac (or any arm64 machine) with a plain `docker build`, Docker targets your own machine's architecture by default, and `terraform apply` will fail with something like:

```
Cloud Run does not support image '...': Container manifest type
'...' must support amd64/linux.
```

So build with `--platform linux/amd64` explicitly when pushing the image Terraform is going to deploy:

```bash
cd app
docker build --platform linux/amd64 -t <your dockerhub user>/mainspring:latest .
docker push <your dockerhub user>/mainspring:latest
```

Then point `var.image` (in `Terraform/terraform.tfvars`) at that exact tag.

## Running the tests

There are two test suites, and neither one needs real Google Cloud credentials.

App tests spin up the actual `python3 app.py` process, the same command the Docker image runs, and send it real HTTP requests:

```bash
cd app
python3 -m unittest discover -s tests -v
```

Terraform tests use Terraform's own built in test framework (`terraform test`, needs Terraform 1.7 or newer) with a mocked Google provider. It checks that the configuration would create the right resources, the dedicated service account, the right image, the right invoker bindings, and that `allUsers` gets rejected, without ever calling a real Google API or needing credentials.

```bash
cd Terraform
terraform init -backend=false
terraform test
```

Both suites also run automatically on every push and pull request through GitHub Actions (`.github/workflows/ci.yml`), and neither job needs secrets configured in GitHub, since the Terraform tests run against a mock.

## Deploying for real

`Terraform/terraform.tfvars` already holds the deploy values (`project_id`, `region`, `image`, `invoker_members`). Edit that file directly if any of them need to change, then:

```bash
gcloud auth application-default login

cd Terraform
terraform init
terraform apply
```

## Tradeoffs, and what I'd do differently with more time

Image registry: Docker Hub was the simplest way to satisfy "any public registry Cloud Run can pull from." Given more time I'd use Google Artifact Registry with Cloud Build instead, so the image gets vulnerability scanned and never has to be public.

State: local Terraform state is fine solo, but it doesn't scale to a team. A real project would use a remote backend (a GCS bucket) with locking, so two people can't apply at the same time.

Testing depth: the Terraform tests check the plan, what Terraform would create, rather than a real deployment, since that needs no credentials or live project. With more time I'd add a separate, optional CI job that actually deploys to a throwaway project and tears it down again, to catch anything the mocked tests can't see.

Health checks: the service only has the one `/` endpoint the assignment asked for. A real service would probably split that into a `/healthz` for infrastructure checks and a separate endpoint for actual traffic.

CI/CD credentials: if this pipeline ever needed to actually deploy from GitHub Actions, I'd set up Workload Identity Federation rather than storing a long lived GCP key as a GitHub secret.

Multiple environments: right now there's one Terraform configuration for whatever project you point it at. A real setup would probably separate dev, staging, and prod, either as separate directories or Terraform workspaces.
