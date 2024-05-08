# Renovate 37.351 - slim | Updated 2024-05-08
# https://hub.docker.com/r/renovate/renovate/tags
docker run --rm \
  --volume "./config.js:/usr/src/app/config.js" \
  --env RENOVATE_TOKEN="$GITHUB_TOKEN" \
  --env LOG_LEVEL=debug \
  renovate/renovate@sha256:3286096674fc3e5d5d3e74698c144113930ffbc4f900ddc9f99d6c81c682f448
