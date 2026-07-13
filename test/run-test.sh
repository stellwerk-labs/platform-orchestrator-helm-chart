export PROJECT_ID=$(terraform output -raw project_id)
export ENVIRONMENT_ID=$(terraform output -raw environment_id)

octl deploy ${PROJECT_ID} ${ENVIRONMENT_ID} manifest.yaml