#/bin/bash

# Copyright (C) 2012-2014 Red Hat, Inc.
#
# This file is part of csmock.
#
# csmock is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# csmock is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with csmock.  If not, see <http://www.gnu.org/licenses/>.

SELF="$0"

PKG="csmock"

die() {
    echo "$SELF: error: $1" >&2
    exit 1
}

match() {
    grep "$@" > /dev/null
}

DST="`readlink -f "$PWD"`"

REPO="`git rev-parse --show-toplevel`"
test -d "$REPO" || die "not in a git repo"

NV="`git describe --tags`"
echo "$NV" | match "^$PKG-" || die "release tag not found"

VER="`echo "$NV" | sed "s/^$PKG-//"`"

TIMESTAMP="`git log --pretty="%cd" --date=iso -1 \
    | tr -d ':-' | tr ' ' . | cut -d. -f 1,2`"

VER="`echo "$VER" | sed "s/-.*-/.$TIMESTAMP./"`"

BRANCH="`git rev-parse --abbrev-ref HEAD`"
test -n "$BRANCH" || die "failed to get current branch name"
test master = "${BRANCH}" || VER="${VER}.${BRANCH}"
test -z "`git diff HEAD`" || VER="${VER}.dirty"

NV="${PKG}-${VER}"
printf "%s: preparing a release of \033[1;32m%s\033[0m\n" "$SELF" "$NV"

TMP="`mktemp -d`"
trap "echo --- $SELF: removing $TMP... 2>&1; rm -rf '$TMP'" EXIT
test -d "$TMP" || die "mktemp failed"

SRC_TAR="${NV}.tar"
SRC="${SRC_TAR}.xz"
git archive --prefix="$NV/" --format="tar" HEAD -- . > "${TMP}/${SRC_TAR}" \
                                        || die "failed to export sources"
cd "$TMP" >/dev/null                    || die "mktemp failed"
xz -c "$SRC_TAR" > "$SRC"               || die "failed to compress sources"

SPEC="$TMP/$PKG.spec"
cat > "$SPEC" << EOF
Name:       $PKG
Version:    $VER
Release:    1%{?dist}
Summary:    A mock wrapper for Static Analysis tools

Group:      Development/Tools
License:    GPLv3+
URL:        https://git.fedorahosted.org/cgit/csmock.git
Source0:    https://git.fedorahosted.org/cgit/csmock.git/snapshot/$SRC
BuildRoot:  %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)

BuildRequires: help2man

Requires: cscppc
Requires: csdiff
Requires: cswrap
Requires: mock
Requires: rpm-build

BuildArch: noarch

%description
This package contains cov-mockbuild and cov-diffbuild tools that allow to scan
SRPMs by Static Analysis tools in a fully automated way.

%package -n csmock-ng
Summary: Preview of a new major version of the csmock package
Requires: csmock

%description -n csmock-ng
Hihgly experimental, currently suitable only for development of csmock itself.

%{!?python_sitearch: %define python_sitearch %(%{__python} -c "from distutils.sysconfig import get_python_lib; print get_python_lib(1)")}

%prep
%setup -q

%build
mkdir -p bin etc man sbin

# ebmed VERSION and PLUGIN_DIR version into the scripts
install -p -m0755 cov-{diff,mock}build bin/
sed -e 's/rpm -qf .SELF/echo %{version}/' -i bin/cov-{diff,mock}build
sed -e 's/@VERSION@/%{name}-%{version}-%{release}/' \\
    -e 's|@PLUGIN_DIR@|%{python_sitearch}/csmock/plugins|' \\
    -i py/csmock

help2man --no-info --section 1 --name \\
    "run static analysis of the given SRPM using mock" \\
    bin/cov-mockbuild > man/cov-mockbuild.1

help2man --no-info --section 1 --name \\
    "run static analysis of the given the patches in the given SRPM using cov-mockbuild" \\
    bin/cov-diffbuild > man/cov-diffbuild.1

help2man --no-info --section 1 --name \\
    "run static analysis of the given SRPM using mock" \\
    py/csmock > man/csmock.1

printf '#!/bin/sh\\nstdbuf -o0 /usr/sbin/mock "\$@"\\n' > ./sbin/mock-unbuffered
printf 'USER=root\\nPROGRAM=/usr/sbin/mock-unbuffered\\nSESSION=false
FALLBACK=false\\nKEEP_ENV_VARS=COLUMNS,SSH_AUTH_SOCK\\n' > ./etc/mock-unbuffered

%clean
rm -rf "\$RPM_BUILD_ROOT"

%install
rm -rf "\$RPM_BUILD_ROOT"

install -m0755 -d \\
    "\$RPM_BUILD_ROOT%{_bindir}" \\
    "\$RPM_BUILD_ROOT%{_mandir}/man1" \\
    "\$RPM_BUILD_ROOT%{_sbindir}" \\
    "\$RPM_BUILD_ROOT%{_datadir}/csmock" \\
    "\$RPM_BUILD_ROOT%{_datadir}/csmock/bashrc" \\
    "\$RPM_BUILD_ROOT%{_datadir}/csmock/scripts" \\
    "\$RPM_BUILD_ROOT%{python_sitearch}/" \\
    "\$RPM_BUILD_ROOT%{python_sitearch}/csmock" \\
    "\$RPM_BUILD_ROOT%{python_sitearch}/csmock/plugins"

install -p -m0755 \\
    cov-{diff,mock}build cov-dump-err rpmbuild-rawbuild py/csmock \\
    "\$RPM_BUILD_ROOT%{_bindir}"

install -p -m0644 man/{csmock,cov-{diff,mock}build}.1 "\$RPM_BUILD_ROOT%{_mandir}/man1/"

install -p -m0644 build.bashrc        "\$RPM_BUILD_ROOT%{_datadir}/csmock/bashrc/build"
install -p -m0644 prep.bashrc         "\$RPM_BUILD_ROOT%{_datadir}/csmock/bashrc/prep"
install -p -m0644 cov_checker_map.txt "\$RPM_BUILD_ROOT%{_datadir}/csmock/cwe-map.csv"

install -p -m0644 py/plugins/gcc.py \\
    "\$RPM_BUILD_ROOT%{python_sitearch}/csmock/plugins"

install -p -m0755 scripts/patch-rawbuild.sh \\
    "\$RPM_BUILD_ROOT%{_datadir}/csmock/scripts"

install -m0755 -d \\
    "\$RPM_BUILD_ROOT%{_sysconfdir}/security/console.apps/" \\
    "\$RPM_BUILD_ROOT%{_sysconfdir}/pam.d/"

install -p -m0755 sbin/mock-unbuffered "\$RPM_BUILD_ROOT%{_sbindir}"

install -p -m0644 etc/mock-unbuffered \\
    "\$RPM_BUILD_ROOT%{_sysconfdir}/security/console.apps/"

ln -s mock "\$RPM_BUILD_ROOT%{_sysconfdir}/pam.d/mock-unbuffered"
ln -s consolehelper "\$RPM_BUILD_ROOT%{_bindir}/mock-unbuffered"

%files
%defattr(-,root,root,-)
%{_bindir}/cov-dump-err
%{_bindir}/cov-diffbuild
%{_bindir}/cov-mockbuild
%{_bindir}/rpmbuild-rawbuild
%{_mandir}/man1/cov-diffbuild.1*
%{_mandir}/man1/cov-mockbuild.1*
%{_datadir}/csmock
%{_bindir}/mock-unbuffered
%{_sbindir}/mock-unbuffered
%{_sysconfdir}/pam.d/mock-unbuffered
%config(noreplace) %{_sysconfdir}/security/console.apps/mock-unbuffered
%doc COPYING

%files -n csmock-ng
%defattr(-,root,root,-)
%{_bindir}/csmock
%{_datadir}/csmock/scripts
%{_mandir}/man1/csmock.1*
%{python_sitearch}/csmock/plugins/*"
EOF

rpmbuild -bs "$SPEC"                            \
    --define "_sourcedir $TMP"                  \
    --define "_specdir $TMP"                    \
    --define "_srcrpmdir $DST"                  \
    --define "_source_filedigest_algorithm md5" \
    --define "_binary_filedigest_algorithm md5"
