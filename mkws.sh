#!/bin/bash
#
# Copyright (C) 2020 Chris McClelland
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software
# and associated documentation files (the "Software"), to deal in the Software without
# restriction, including without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright  notice and this permission notice  shall be included in all copies or
# substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
# BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
# DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

# Global settings
BOLD=$(tput bold; tput setaf 1)
NORM=$(tput sgr0)
WS_TOOLS=$(dirname $0)

# Need at least one argument
if [ $# -lt 1 ]; then
    echo "Synopsis: $0 [-t] [-r] [-u library=url ...] <ws-name> [<library:component> ...]"
    echo "  -t: Run tests for the components"
    echo "  -r: Generate a test report (ignored if -t not given)"
    echo "  -u library=url: Specify the clone URL for a library of components"
    exit 1
fi

# Initialise library map (i.e mapping of each library to its associated clone URL). Sadly this is
# the reason why this script needs /bin/bash - other shells don't have associative arrays.
typeset -A URL
. ${WS_TOOLS}/urls.sh

# Parse options
URLSET=""
RUNTEST=0
GENREPORT=0
while getopts tru: OPT; do
    case "${OPT}" in
        u)
            URLSET="${URLSET} ${OPTARG}"
            ;;
        t)
            RUNTEST=1
            ;;
        r)
            GENREPORT=1
            ;;
    esac
done
shift "$(($OPTIND-1))"
WS=$1
shift
COMPONENTS=$*

# Parse all the library=url options
for i in ${URLSET}; do
    OLDIFS=${IFS}
    IFS='='
    set -- $i
    IFS=${OLDIFS}
    if [ "$#" -ne "2" ]; then
        echo "Try something like:"
        echo "  -u foobar=git@github.com:foobar"
        echo "  -u foobar=https://github.com/foobar"
        exit 1
    fi
    LIBRARY=$1
    NEW_URL=$2
    OLD_URL=${URL[$LIBRARY]}
    if [ ! -z "${OLD_URL}" ]; then
        echo "A repository URL for ${LIBRARY} already exists: ${OLD_URL}"
        exit 1
    fi
    echo "Setting ${LIBRARY} to ${NEW_URL}"
    URL[$LIBRARY]=${NEW_URL}
done

# Check if the workspace already exists
if [ -e ${WS} ]; then
    echo "Workspace ${WS} already exists!"
    exit 2
fi

# Create the workspace
mkdir ${WS}
cd ${WS}
echo "${BOLD}Creating top-level git repository...${NORM}"
git init .
if [ "${OS}" = "Windows_NT" ]; then
    export PROJ_HOME=$(pwd | sed 's#^/\([a-zA-Z]\)/#\1:/#g')
else
    export PROJ_HOME=$(pwd)
fi
cat > README.md <<EOF
## ${WS}
Skeleton project.

These git commands were executed during setup:
  export PROJ_HOME=${PROJ_HOME}
  cd \${PROJ_HOME}
  git init .
EOF

# Submodule the hdl-tools repository (needed for everything)
echo "${BOLD}Cloning makestuff/hdl-tools...${NORM}"
git submodule add ${URL[makestuff]}/hdl-tools.git
echo "  git submodule add ${URL[makestuff]}/hdl-tools.git" >> README.md
echo
mkdir ip

# Git submodule each of the components requested by the user
printf "SUBDIRS :=" > ip/Makefile
for i in ${COMPONENTS}; do
    OLDIFS=${IFS}
    IFS=':'
    set -- $i
    IFS=${OLDIFS}
    if [ "$#" -lt "2" -o "$#" -gt "3" ]; then
        echo "Components need to be specified as \"library:component\" or \"library:component:branch\""
        exit 1
    fi
    LIBRARY=$1
    COMPONENT=$2
    LIBRARY_URL=${URL[$LIBRARY]}
    if [ -z "${LIBRARY_URL}" ]; then
        echo "You must declare a repository URL for ${LIBRARY}"
        exit 1
    fi
    if [ "$#" -eq "2" ]; then
        echo "${BOLD}Making a git submodule of ${LIBRARY}:${COMPONENT}...${NORM}"
        git submodule add ${LIBRARY_URL}/${COMPONENT}.git ip/${LIBRARY}/${COMPONENT}
        echo "  git submodule add ${LIBRARY_URL}/${COMPONENT}.git ip/${LIBRARY}/${COMPONENT}" >> README.md
    else
        BRANCH=$3
        echo "${BOLD}Making a git submodule of ${LIBRARY}:${COMPONENT}:${BRANCH}...${NORM}"
        git submodule add ${LIBRARY_URL}/${COMPONENT}.git ip/${LIBRARY}/${COMPONENT}
        cd ip/${LIBRARY}/${COMPONENT}
        git checkout --detach ${BRANCH}
        cd ../../..
        echo "  git submodule add ${LIBRARY_URL}/${COMPONENT}.git ip/${LIBRARY}/${COMPONENT}" >> README.md
        echo "  cd ip/${LIBRARY}/${COMPONENT}; git checkout --detach ${BRANCH}; cd ../../.." >> README.md
    fi
    printf " \\\\\n\t${LIBRARY}/${COMPONENT}" >> ip/Makefile
    echo
done
cat >> ip/Makefile <<EOF


include \$(PROJ_HOME)/hdl-tools/common.mk

clean::
	rm -rf sim-libs
EOF
echo "  git add README.md" >> README.md
echo "  git add ip/Makefile" >> README.md
git add README.md
git add ip/Makefile

# Maybe run the tests, maybe generate a report
if [ "${RUNTEST}" -eq "1" ]; then
    echo "${BOLD}Running tests...${NORM}"
    if [ "${GENREPORT}" -eq "1" ]; then
        make -C ip CONTINUE_ON_FAILURE=1 test
        echo
    
        echo "${BOLD}Generating test report...${NORM}"
        . ${WS_TOOLS}/mkrp.sh
    else
        make -C ip test
    fi
    echo
fi

# Final reminder
echo "${BOLD}Remember to set PROJ_HOME:${NORM}"
echo "export PROJ_HOME=${PROJ_HOME}"
echo
