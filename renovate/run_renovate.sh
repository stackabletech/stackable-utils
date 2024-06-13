# Renovate 37.406 - slim | Updated 2024-06-13
# https://hub.docker.com/r/renovate/renovate/tags
docker run --rm \
  --volume "./config.js:/usr/src/app/config.js" \
  --env RENOVATE_TOKEN="$GITHUB_TOKEN" \
  --env LOG_LEVEL=debug \
  renovate/renovate@sha256:ffb9bfd36ce4cf477fe8883ebc1dab79503f9032956026f837d3628d4ed8fb53
