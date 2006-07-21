package PAR::Dist::FromCPAN;

use 5.006;
use strict;
use warnings;

use CPAN;
use PAR::Dist;
use File::Copy;
use Cwd qw/cwd abs_path/;
use File::Spec;
use File::Path;

require Exporter;

our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 'all' => [ qw(
	cpan_to_par
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	cpan_to_par
);

our $VERSION = '0.03';

sub cpan_to_par {
	die "Uneven number of arguments to 'cpan_to_par'." if @_ % 2;
	my %args = @_;
	if (not defined $args{pattern}) {
		die "You need to specify a module pattern.";
	}
	my $pattern = $args{pattern};
	my $skip_ary = $args{skip} || [];

	my $outdir = abs_path(defined($args{out}) ? $args{out} : '.');
	die "Output path not a directory." if not -d $outdir;

	print "Expanding module pattern.\n" if $args{verbose};

	my @mod = grep {
		_skip_this($skip_ary, $_->id) ? () : $_
	} CPAN::Shell->expand('Module', $pattern);
	
	my %seen;
	my @failed;

	my @par_files;
	
	foreach my $mod (@mod) {
		my $file = $mod->cpan_file();
		if ($seen{$file}) {
			print("Skipping previously processed module:\n".$mod->as_glimpse()."\n") if $args{verbose};
			next;
		}
		$seen{$file}++;
		print "Processing next module:\n".$mod->as_glimpse()."\n" if $args{verbose};

		# This branch isn't entered because $mod->make() doesn't
		# indicate an error if it occurred...
		if (not $mod->make() and 0) {
			print "Something went wrong making the following module:\n"
			.$mod->as_glimpse()
			."\nWe will try to continue. A summary of all failed modules "
			."will be given\nat the end of the script execution in order "
			."of appearance.\n";
			push @failed, $mod;
		}

		# recursive dependency solving?
		if ($args{follow}) {
			print "Checking dependencies.\n" if $args{verbose};
			my $dist = $mod->distribution;
			my $pre_req = $dist->prereq_pm;
			next if not defined $pre_req;
			my @modules =
				grep {
					_skip_this($skip_ary, $_->id) ? () : $_
				}
				map {CPAN::Shell->expand('Module', $_)}
				keys %$pre_req;
			my %this_seen;
			@modules =
				grep { $seen{$_->cpan_file}||$this_seen{$_->cpan_file}++ ? 0 : 1 }
				@modules;
			print "Recursively adding dependencies: \n"
				. join("\n", map {$_->cpan_file} @modules) . "\n";
			push @mod, @modules;
		}

		# Run tests?
		if ($args{test}) {
			print "Running tests.\n" if $args{verbose};
			$mod->test();
		}

		# create PAR distro
		my $dir = $mod->distribution->dir;
		print "Module was built in '$dir'.\n" if $args{verbose};

		chdir($dir);
		my $par_file = blib_to_par();
		die "Could not find PAR distribution file '$par_file'."
			if not -f $par_file;
		print "Generated PAR distribution as file '$par_file'\n"
			if $args{verbose};
		print "Moving distribution file to output directory '$outdir'.\n"
			if $args{verbose};
		unless(File::Copy::move($par_file, $outdir)) {
			die "Could not move file '$par_file' to directory "
			."'$outdir'. Reason: $!";
		}
		$par_file = File::Spec->catfile($outdir, $par_file);
		push @par_files, $par_file if -f $par_file;
	}

	if (@failed) {
		print "There were modules that failed to build. "
		."These are in order of appearance:\n";
		foreach (@failed) {
			print $_->as_glimpse()."\n";
		}
	}

	# Merge deps
	if ($args{merge}) {
		print "Merging PAR distributions into one.\n"
		  if $args{verbose};
		merge_par(
			@par_files
		);
		foreach my $file (@par_files[1..@par_files-1]) {
			File::Path::rmtree($file);
		}
		@par_files = ($par_files[0]);
	}

	# strip docs
	if ($args{strip_docs}) {
		print "Removing documentation from the PAR distribution(s).\n"
		  if $args{verbose};
		remove_man($_) for @par_files;
	}
	
	return(1);
}

sub _skip_this {
	my $ary = shift;
	my $string = shift;
	study($string) if @$ary > 2;
#	print $string.":\n";
	for (@$ary) {
#		print "--> $_\n";
#		warn("MATCHES: $string"), sleep(5), return(1) if $string =~ /$_/;
		return(1) if $string =~ /$_/;
	}
	return 0;
}

1;
__END__

=head1 NAME

PAR::Dist::FromCPAN - Create PAR distributions from CPAN

=head1 SYNOPSIS

  use PAR::Dist::FromCPAN;
  
  # Creates a .par distribution of the Math::Symbolic module in the
  # current directory.
  cpan_to_par(pattern => '^Math::Symbolic$');
  
  # The same, but also create .par distributions for Math::Symbolic's
  # dependencies and run all tests.
  cpan_to_par(pattern => '^Math::Symbolic$', follow => 1, test => 1);
  
  # Create distributions for all modules below the 'Math::Symbolic'
  # namespace in the 'par-dist/' subdirectory and be verbose about it.
  cpan_to_par(
    pattern => '^Math::Symbolic',
    out     => 'par-dist/',
    verbose => 1,
  );

=head1 DESCRIPTION

This module creates PAR distributions from any number of modules
from CPAN. It exports the cpan_to_par subroutine for this task.

=head2 EXPORT

By default, the C<cpan_to_par> subroutine is exported to the callers
namespace.

=head1 SUBROUTINES

This is a list of all public subroutines in the module.

=head2 cpan_to_par

The only mandatory parameter is a pattern matching the
modules you wish to create PAR distributions from.This works the
same way as, for example C<cpan install MODULEPATTERN>.

Arguments:

  pattern    => 'patternstring'
  out        => 'directory'  (write distribution files to this directory)
  verbose    => 1/0 (verbose mode on/off)
  test       => 1/0 (run module tests on/off)
  follow     => 1/0 (also create distributions for dependencies on/off)
  merge      => 1/0 (merge everything into one .par archive)
  strip_docs => 1/0 (strip all man* and html documentation)
  skip       => \@ary (skip all modules that match any of the regulat
                       expressions in @ary)

=head1 SEE ALSO

The L<PAR::Dist> module is used to create .par distributions from an
unpacked CPAN distribution. The L<CPAN> module is used to fetch the
distributions from the CPAN.

PAR has a mailing list, <par@perl.org>, that you can write to; send an empty mail to <par-subscribe@perl.org> to join the list and participate in the discussion.

Please send bug reports to <bug-par-dist-fromcpan@rt.cpan.org>.

The official PAR website may be of help, too: http://par.perl.org

=head1 AUTHOR

Steffen Mueller, E<lt>smueller at cpan dot orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 by Steffen Mueller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.6 or,
at your option, any later version of Perl 5 you may have available.

=cut
