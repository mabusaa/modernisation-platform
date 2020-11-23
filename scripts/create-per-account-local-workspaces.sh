#!/bin/bash

run_terraform () {
  echo "Running terraform init for $called_function"
  output=$(terraform init -input=false 2>&1) || (echo "$output" && false)
}

get_all_local_application_definitions () {
  cat environments/*.json | jq -r '. | .name' > tmp/local-applications.tmp
}

get_all_local_environment_definitions_split_by_application () {
  for file in environments/*.json
  do
    filename=$(basename $file .json)
    cat $file | jq -r '. | .name + "-" + .environments[]' > tmp/$filename-local.tmp
  done
}

create_local_workspaces () {
  cd terraform/environments
  while read -r line; do
    called_function="create_local_workspaces for application $line"
    mkdir -p $line
    cp ../templates/backend.tf $line/backend.tf
    cp ../templates/secrets.tf $line/secrets.tf
    cd $line
    run_terraform
    terraform workspace list > ../../../tmp/$line-remote.tmp
    cd ..
    cat ../../tmp/$line-remote.tmp | grep "\S" | grep -v "default" | tr -d "* " | tee ../../tmp/$line-remote.tmp
  done < ../../tmp/local-applications.tmp
  cd ../..
}

compare_local_and_remote_definitions () {
  for file in tmp/*; do
    sort $file -o $file
  done
  while read -r line; do
    if [ -s tmp/$line-remote.tmp ]; then
      grep -xvFf tmp/$line-remote.tmp tmp/$line-local.tmp > tmp/$line-remote-missing.tmp
    else
      cp tmp/$line-local.tmp tmp/$line-remote-missing.tmp
    fi
  done < tmp/local-applications.tmp
}

create_remote_workspaces () {
  cd terraform/environments
  while read -r line; do
    cd $line
    while read -r workspace; do
      called_function="create_remote_workspaces: $workspace for application $line"
      run_terraform
      output=$(terraform workspace select default) || (echo "$output" && false)
      output=$(terraform workspace new "$workspace") || (echo "$output" && false)
      output=$(terraform workspace select "$workspace") || (echo "$output" && false)
    done < ../../../tmp/$line-remote-missing.tmp
    cd ..
  done < ../../tmp/local-applications.tmp
}

main () {
  mkdir -p tmp/
  get_all_local_application_definitions &&
  get_all_local_environment_definitions_split_by_application &&
  create_local_workspaces &&
  compare_local_and_remote_definitions &&
  create_remote_workspaces
  rm -r tmp/
}

main
