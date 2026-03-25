#!/bin/bash
set -e

if [ "$PRIMARY_REGION" == "$FLY_REGION" ]; then
  /app/bin/migrate
fi

/app/bin/hivemind /app/Procfile
