# Renovate 38.109  | Updated 2024-09-10
# https://hub.docker.com/r/renovate/renovate/tags
docker run --rm \
  --volume "./config.js:/usr/src/app/config.js" \
  --env RENOVATE_TOKEN="$GITHUB_TOKEN" \
  --env LOG_LEVEL=debug \
  renovate/renovate@sha256:09510b1f2c32697a83e15c5626b064173a254bc759c75a3d151d680ef93966b2
