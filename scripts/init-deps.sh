#!/bin/sh
# Initialize native codec submodules and apply the local patches.
# Run once after cloning, and again whenever deps/*.patch changes.
set -e

cd "$(dirname "$0")/.."

git submodule update --init --recursive --force

for name in libheif-sys libde265 libheif jpegxl-rs; do
  echo "==> patching deps/$name"
  (
    cd "deps/$name"
    git reset --hard
    git apply "../$name.patch"
  )
done

echo "done."
