#!/usr/bin/env bash
# Mock bd CLI that always fails — for error path testing.
echo "Error: something went wrong" >&2
exit 1
