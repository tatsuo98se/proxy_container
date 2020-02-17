#! /bin/bash
docker build -t proxy .
docker run -dit  --name proxy -p 8443:443 -v "$PWD"/logs/:/logs/ proxy 