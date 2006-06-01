#!/usr/bin/env perl

use inc::Module::Install;
name        ('PAR-Dist-FromCPAN');
author      ('Steffen Mueller (smueller@cpan.org)');
abstract    ('Create PAR distributions from CPAN');
version_from('lib/PAR/Dist/FromCPAN.pm');
license     ('perl');

&WriteAll   ( sign => 1 );

