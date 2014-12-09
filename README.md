NLMA
====

NLMA is a host-side monitoring daemon that schedules and runs check
plugins locally and submits check results to one or more Nagios/Icinga
parent servers via NSCA.

INSTALLATION
============

To install this module, run the following commands:

    perl Makefile.PL
    make
    make test
    make install

SUPPORT AND DOCUMENTATION
=========================

After installing, you can find documentation for this module with the
perldoc command.

    perldoc NLMA

There is a man page for the nlma utility as well.

    man nlma

COPYRIGHT AND LICENCE
=====================

Copyright (C) 2012-2014 Synacor, Inc.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
