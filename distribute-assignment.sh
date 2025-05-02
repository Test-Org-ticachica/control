#!/bin/bash
# distribute-assignment.sh
#
# Usage:
#   ./distribute-assignment.sh -c /path/to/classroom-control -a assignment1.yaml [-t target_org]
#
# This script reads the assignment config from the control repo's assignments folder and the students.yaml file,
# then for each student creates a new repository (from the template in the assignment config) and adds the student.
#
# Requirements:
#   - gh CLI must be installed and authenticated.
#   - yq (https://github.com/mikefarah/yq) to parse YAML files.

set -e

function usage() {
  echo "Usage: $0 -c <control_repo_path> -a <assignment_config_file> [-t target_org]"
  exit 1
}

while getopts "c:a:t:" opt; do
  case "$opt" in
    c) CONTROL_REPO="$OPTARG" ;;
    a) ASSIGNMENT_CONFIG="$OPTARG" ;;
    t) TARGET_ORG="$OPTARG" ;;
    *) usage ;;
  esac
done

[ -z "$CONTROL_REPO" ] && usage
[ -z "$ASSIGNMENT_CONFIG" ] && usage

# Read assignment configuration from assignments folder
ASSIGNMENT_FILE="$CONTROL_REPO/assignments/$ASSIGNMENT_CONFIG"
if [ ! -f "$ASSIGNMENT_FILE" ]; then
  echo "Assignment config file not found: $ASSIGNMENT_FILE"
  exit 1
fi

ASSIGNMENT_NAME=$(yq eval '.assignment_name' "$ASSIGNMENT_FILE")
TEMPLATE_REPO=$(yq eval '.template_repo' "$ASSIGNMENT_FILE")
ORG=$(yq eval '.org' "$ASSIGNMENT_FILE")
PRIVATE=$(yq eval '.private' "$ASSIGNMENT_FILE")
DEADLINE=$(yq eval '.deadline' "$ASSIGNMENT_FILE")

# Allow target org override
if [ -n "$TARGET_ORG" ]; then
  ORG="$TARGET_ORG"
fi

echo "Distributing assignment '$ASSIGNMENT_NAME' from template '$TEMPLATE_REPO' into org '$ORG'"
echo "Deadline: $DEADLINE"

# Read students file from control repo (assumed at control_repo/students.yaml)
STUDENTS_FILE="$CONTROL_REPO/students.yaml"
if [ ! -f "$STUDENTS_FILE" ]; then
  echo "Students file not found: $STUDENTS_FILE"
  exit 1
fi

NUM_CREATED=0
# Loop over each student (requires yq version 4+)
for student in $(yq eval '.students[].github' "$STUDENTS_FILE"); do
  # Construct repo name. For example: assignment1-johnsmith.
  REPO_NAME="${ASSIGNMENT_NAME}-${student}"
  FULL_REPO="${ORG}/${REPO_NAME}"
  echo "Creating repository $FULL_REPO for student $student …"
  
  # Create the repo (using the template feature)
  gh repo create "$FULL_REPO" \
    --template "$TEMPLATE_REPO" \
    $( [ "$PRIVATE" == "true" ] && echo "--private" || echo "--public" ) \
    --confirm

  # Add the student as a collaborator with write access.
  gh api -X PUT "repos/${ORG}/${REPO_NAME}/collaborators/${student}" \
    -f permission=push
  
  ((NUM_CREATED++))
done

echo "Created assignment repositories for $NUM_CREATED students."
