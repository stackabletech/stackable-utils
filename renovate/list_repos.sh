function get_all_repos {
    page=1
    repos=()
    while true; do
        response=$(curl -s -u "$USERNAME:$TOKEN" "https://api.github.com/orgs/stackabletech/repos?per_page=100&page=$page")
        if [[ -z "$response" ]]; then
            break
        fi
        page=$((page + 1))
        repo_names=$(echo "$response" | jq -r '.[] | select(.archived == false and .fork == false) | .name' | tr -d '"')
        if [[ -z "$repo_names" ]]; then
            break
        fi
        repos+=($repo_names)
    done
    echo "${repos[@]}"
}

function main {
  projects="$(get_all_repos)"

  if [[ -z "$projects" ]]; then
    echo "No repositories found."
    exit 1
  fi

  echo "repositories: ["
  for repo in ${projects[@]}; do
      echo "    \"$repo\","
  done
  echo "]"
}

main
