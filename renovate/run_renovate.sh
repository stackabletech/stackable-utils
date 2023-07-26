docker run --rm \
  --volume "./config.js:/usr/src/app/config.js" \
  --env RENOVATE_TOKEN="$GITHUB_TOKEN" \
  --env LOG_LEVEL=debug \
  renovate/renovate@sha256:1df1b79cad9262c50d4537706716494301ee6437ab0176cc34ab960d8557c56d
