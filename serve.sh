#!/bin/sh
docker run --rm -it -p 4000:4000 -v `pwd`:/site madduci/docker-github-pages serve --config "./_config.yml,./_config.dev.yml" --watch --force_polling --host 0.0.0.0
