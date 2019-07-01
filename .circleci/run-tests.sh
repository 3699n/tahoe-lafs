#!/bin/bash

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

# The filesystem location of the root of a virtualenv we can use to get/build
# wheels.
BOOTSTRAP_VENV="$1"
shift

# The filesystem location of the root of the project source.  We need this to
# know what wheels to get/build, of course.
PROJECT_ROOT="$1"
shift

# "yes" if the tox command may fail without causing this script to fail,
# anything else for normal behavior.  This is basically implementing the
# "expected failure" workflow - useful to, eg, add a new Python runtime to CI
# before the test suite completely passes on that runtime.
ALLOWED_FAILURE="$1"
shift

# The path to which test artifacts will be written so that they can be
# collected by some other tool.
ARTIFACTS=$1
shift

# The number of concurrent trial jobs to run (a value for the `--jobs` trial
# argument).  Empty string to disable this.
TRIAL_JOBS=$1
shift

TAHOE_LAFS_TOX_ENVIRONMENT=$1
shift

TAHOE_LAFS_TOX_ARGS=$1
shift || :

if [ -n "${ARTIFACTS}" ]; then
    # If given an artifacts path, prepare to have some artifacts created
    # there.  The integration tests don't produce any artifacts; that is the
    # case where we expect not to end up here.

    # Make sure we can actually write things to this directory.
    mkdir -p "${ARTIFACTS}"

    SUBUNIT2="${ARTIFACTS}"/results.subunit2

    # Use an intermediate directory here because CircleCI extracts some label
    # information from its name.
    JUNITXML="${ARTIFACTS}"/junit/unittests/results.xml
else
    SUBUNIT2=""
    JUNITXML=""
fi

# Run the test suite as a non-root user.  This is the expected usage some
# small areas of the test suite assume non-root privileges (such as unreadable
# files being unreadable).
#
# Also run with /tmp as a workdir because the non-root user won't be able to
# create the tox working filesystem state in the source checkout because it is
# owned by root.
#
# Send the output directly to a file because transporting the binary subunit2
# via tox and then scraping it out is hideous and failure prone.
export SUBUNITREPORTER_OUTPUT_PATH="${SUBUNIT2}"
export TAHOE_LAFS_TRIAL_ARGS="--reporter=subunitv2-file --rterrors ${TRIAL_JOBS:+--jobs ${TRIAL_JOBS}}"
export PIP_NO_INDEX="1"

if [ "${ALLOWED_FAILURE}" = "yes" ]; then
    alternative="true"
else
    alternative="false"
fi

${BOOTSTRAP_VENV}/bin/tox \
    -c ${PROJECT_ROOT}/tox.ini \
    --workdir /tmp/tahoe-lafs.tox \
    -e "${TAHOE_LAFS_TOX_ENVIRONMENT}" \
    ${TAHOE_LAFS_TOX_ARGS} || "${alternative}"

if [ -n "${ARTIFACTS}" ]; then
    # Create a junitxml results area.
    mkdir -p "$(dirname "${JUNITXML}")"
    ${BOOTSTRAP_VENV}/bin/subunit2junitxml < "${SUBUNIT2}" > "${JUNITXML}" || "${alternative}"
fi
