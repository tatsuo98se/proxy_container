#! /bin/bash
set -e
docker build -t proxy .
docker run -ita STDOUT --rm -p 9443:443 -v $PWD/data/:/data/ --name proxy proxy
