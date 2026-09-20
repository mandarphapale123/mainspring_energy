project_id = "mainspring-energy"
region     = "us-central1"
image      = "mandarphapale1234/mainspring:v3"

# The invoking identity's value, supplied at deploy time. Leave as an empty
# list to keep the service invokable by nobody via this binding.
invoker_members = [
  "user:mphapale06@gmail.com",
  # "serviceAccount:some-sa@your-gcp-project-id.iam.gserviceaccount.com",
]