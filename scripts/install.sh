#!/bin/bash

# Remove old packages folder
if [ -d "src/Packages" ]; then
    rm -rf ./src/Packages
fi

# Install packages
wally install --project-path src

# Sourcemap generation
rojo sourcemap --output sourcemap.json

# Fix the types (why is this not native???)
wally-package-types --sourcemap sourcemap.json src/Packages/
