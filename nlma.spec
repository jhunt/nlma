%define modulename NLMA

Name:      nlma
Version:   2.13
Release:   1
Vendor:    Synacor
Summary:   NLMA Local Monitoring Agent
License:   GPLv3+
Group:     System Environment/Daemons
URL:       http://github.com/filefrog/nlma
BuildRoot: %{_tmppath}/%{name}-root
Source:    %{modulename}-%{version}.tar.gz
BuildArch: noarch
Requires:  nsca-send

%description
NLMA is a host-side monitoring agent that schedules and runs check plugins
on the local host, translates their output and exit codes, and then reports
this information up to one or more Nagios parent servers via NSCA.  It
features a high-resolution clock for both scheduling and tracking plugin
runs, and also implements retry logic similar to what Nagios uses for its
active checks.


%prep
%setup -q -n %{modulename}-%{version}


%build
CFLAGS="$RPM_OPT_FLAGS" perl Makefile.PL INSTALLDIRS=vendor INSTALL_BASE=''
make

%check
make test


%clean
rm -rf $RPM_BUILD_ROOT


%install
rm -rf $RPM_BUILD_ROOT
make install DESTDIR=$RPM_BUILD_ROOT

if [ -f rpm_files/etc/nlma.yml.dist ]; then mv rpm_files/etc/nlma.yml.dist rpm_files/etc/nlma.yml; fi
if [ -d rpm_files ]; then cp -r rpm_files/* $RPM_BUILD_ROOT; fi

[ -x /usr/lib/rpm/brp-compress ] && /usr/lib/rpm/brp-compress

find $RPM_BUILD_ROOT -name .packlist     -print0 | xargs -0 /bin/rm -f
find $RPM_BUILD_ROOT -name perllocal.pod -print0 | xargs -0 /bin/rm -f
find $RPM_BUILD_ROOT -name rpm_files     -print0 | xargs -0 /bin/rm -fr

find $RPM_BUILD_ROOT -type f -print | \
    sed "s@^$RPM_BUILD_ROOT@@g" | \
    grep -v perllocal.pod | \
    grep -v "\\.packlist" > %{modulename}-%{version}-filelist

if [ "$(cat %{modulename}-%{version}-filelist)X" = "X" ] ; then
    echo "ERROR: EMPTY FILE LIST"
    exit -1
fi


%pre


%preun


%post


%postun


%files -f %{modulename}-%{version}-filelist
%defattr(-,root,root)
%config /etc/sysconfig/nlma
%config /etc/nlma.yml
