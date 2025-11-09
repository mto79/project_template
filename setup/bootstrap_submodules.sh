#!/usr/bin/env bash
# bootstrap_submodules.sh
# Usage: ./bootstrap_submodules_snakecase.sh <github-username-or-org>
# Make sure GITHUB_TOKEN is set in your environment with repo creation permissions

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <github-username-or-org>"
  exit 1
fi

GITHUB_USER="$1"

# Determine main project name from current directory
MAIN_PROJECT_NAME=$(basename "$(pwd)")
echo "Main project: $MAIN_PROJECT_NAME"

# Ensure .gitmodules exists
if [ ! -f .gitmodules ]; then
  echo "No .gitmodules file found. Nothing to do."
  exit 0
fi

# Function to create a new GitHub repository
create_github_repo() {
  local repo_name="$1"
  echo "Creating GitHub repo: $repo_name"
  response=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -d "{\"name\":\"$repo_name\",\"private\":false}" \
    https://api.github.com/user/repos)
  if [ "$response" -ne 201 ] && [ "$response" -ne 422 ]; then
    echo "Failed to create repository $repo_name. HTTP code $response"
    exit 1
  fi
}

# Convert a string to snake_case
to_snake_case() {
  echo "$1" | sed -E 's/([A-Z])/_\L\1/g' | sed -E 's/[^a-z0-9]+/_/g' | sed -E 's/^_+|_+$//g'
}

# Parse submodules from .gitmodules
mapfile -t submodules < <(git config -f .gitmodules --get-regexp path | awk '{print $2}')

for path in "${submodules[@]}"; do
  template_url=$(git config -f .gitmodules --get submodule."$path".url)

  # Generate new repo name in snake_case
  new_repo_name="$(to_snake_case "${MAIN_PROJECT_NAME}_${path}")"

  echo "Processing submodule template $path -> new repo $new_repo_name"

  # Clone template submodule temporarily
  git clone --depth 1 "$template_url" "$path-temp"

  # Create new GitHub repo
  create_github_repo "$new_repo_name"

  # Push template content to new repo using HTTPS
  cd "$path-temp"
  git remote remove origin
  git remote add origin "https://github.com/$GITHUB_USER/$new_repo_name.git"
  git push -u origin main
  cd ..

  # Remove old submodule entry (if any)
  git submodule deinit -f "$path" 2>/dev/null || true
  rm -rf "$path"

  # Add the new repo as a submodule in main project (HTTPS)
  git submodule add "https://github.com/$GITHUB_USER/$new_repo_name.git" "$path"
  rm -rf "$path-temp"
done

# Initialize and update all submodules
git submodule update --init --recursive

git add .gitmodules
git commit -m "Initialize submodules as new repositories for project $MAIN_PROJECT_NAME"
echo "✅ All submodules are now new independent repositories (HTTPS, snake_case names)."
