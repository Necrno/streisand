#!/bin/bash

# Abort on any error.
set -e

# Usage: util/venv-dependencies.sh NEW-DIRECTORY
#
# See the usage function below.

quiet=
# pip makes a lot of noise when installing. Uncomment the following
# line to make it a little quieter.
# quiet=--quiet

#### Options end here.

usage () {
       echo "
Usage: $0 new-directory

This script installs Streisand builder dependencies into an isolated
Python virtualenv. A virtualenv is one of the most reliable ways of
avoiding version clashes, and is especially recommended for people
having problems with initial Streisand installs.

Note that this script is not guaranteed to work for localhost
deployments. This will be fixed in a later release.

It depends on Python 2.7, and on a pip command functional enough to
install virtualenv.  If this is a system running Debian or Ubuntu,
this script will also check for other packages needed to install.

This script can install virtualenv for you, but on Linux, this
requires sudo/root access.

'new-directory' must be somewhere you can write to. A good place may be
$HOME/streisand-deps. If it already exists,
please delete the directory, or use a different name.
"
}

is_root=""
if [ "$(id -u)" == "0" ]; then
    is_root=1
fi

sudo_command="sudo"
sudo_for_pip_install="sudo -H"

# If we're root, get rid of sudo--it may not be there...
if [ -n "$is_root" ]; then
    sudo_command=""
    sudo_for_pip_install=""
fi

invocation_problems=
if [ "$#" -ne 1 ]; then
   usage
   invocation_problems=1
fi

echo "Checking for pip2..."

if ! pip2 --version >/dev/null 2>&1; then
   echo "
You need a working 'pip2' command. pip2 is the standard name for using
pip with Python 2.x. To get one:

On Debian, Ubuntu, and WSL:
   $sudo_command apt-get install python-pip

On macOS:
   # If you haven't, install homebrew from https://brew.sh/
   brew install python

On other systems: please see your OS documentation on how to install
pip.

"
   invocation_problems=1
fi

if [ -n "$invocation_problems" ]; then
    exit 1
fi

hard_detect_dpkg () {
    dpkg-query --status "$1" 2>/dev/null | grep '^Status:.* installed' >/dev/null
}

check_deb_dependencies () {
    critical="$(cat <<EOF
build-essential
libffi-dev
python-dev
python-pip
libssl-dev
libcurl4-openssl-dev
EOF
)"

    packages_not_found=""
    for pkg in $critical; do
	if ! hard_detect_dpkg "$pkg"; then
	    echo "*** Missing package: $pkg"
	    packages_not_found+=" $pkg"
	else
	    echo "Found: $pkg"
	fi
    done

    if [ -n "$packages_not_found" ]; then
	echo "-------"
	echo "Setup will fail without these packages. To install them:"
	echo ""
	echo -n "$sudo_command apt-get install "
	# explicitly want word-spliting here
	# shellcheck disable=SC2086
	echo $packages_not_found
	echo
	exit 1
    else
	echo
	echo "Found all critical packages."
	echo
    fi
}

if [ -f /etc/debian_version ]; then
    echo
    echo "This system appears to be running Ubuntu or Debian. Checking"
    echo "for critical packages."
    echo
    check_deb_dependencies
fi

die () {
    echo "$@"
    exit 1
}

dn="$(dirname "$1")"

if [ ! -d "$dn" ]; then
    die "
The parent directory of $1 ($dn) does not exist. Please specify a
parent directory you can write to. $HOME/streisand-deps
may be a good choice.

"
fi

if [ ! -w "$dn" ]; then
    die "
The parent directory of $1 ($dn) is not writable. Please specify a
parent directory you can write to. $HOME/streisand-deps
may be a good choice.

"
fi

if [ -e "$1" ]; then
    die "
$1 already exists. Please specify a place for a
new directory to be created. $HOME/streisand-deps
is a good choice if it doesn't exist.

"
fi

sudo_pip () {
    # pip complains loudly about directory permissions when sudo without -H.
    $sudo_for_pip_install pip2 $quiet "$@"
}

our_pip () {
    pip2 $quiet "$@"
}

our_pip_install () {
    our_pip install "$@"
}

# What to do, what to do. Homebrew Python jams the site library into
# virtualenvs. But --no-site-packages is deprecated.
virtualenv_no_site=

# An easy way to see if Homebrew is installed.
if brew command command >/dev/null 2>&1; then
    # If it is, we get our virtualenv as a regular user
    our_pip_install virtualenv
    virtualenv_no_site="--no-site-packages"
else
    # We may not need this installed as root; we just need it on
    # $PATH somewhere. But do root for now.
    sudo_pip install virtualenv
fi

# In case we have a new virtualenv executable.
hash -r

if ! virtualenv --python=python2 $virtualenv_no_site "$1"; then
    echo "
virtualenv failed to create directory '$1'
using 'virtualenv --python=python2 $1'. Note that $1 must not exist, but
its parent ($dn) must exist.

The first argument, 'new-directory', must be somewhere you can write
to. A good place may be $HOME/streisand-deps. If it already exists,
please delete the directory, or use a different name.

"
    exit 1
fi

[ -d "$1" ] || die "Missing venv directory $1! Something badly wrong."

# This mucks around with our environment variables. We know where it
# is at shellcheck time.

# shellcheck disable=SC1090
source "$1/bin/activate"

# Below this line, we are only installing into the virtualenv at "$1"

our_pip_install --upgrade pip

# The pip we want should be in our path now. Make sure we use it.
hash -r

# Now we can install all the Python modules.
our_pip_install -r requirements.txt

echo "
*************

All dependencies installed into $1. To use this environment, run this
in your shell:

    source \"$1/bin/activate\"

You need to do this once in every terminal window you plan to run the
command './streisand' in.

After you've run that, you're ready to run ./streisand.
"
