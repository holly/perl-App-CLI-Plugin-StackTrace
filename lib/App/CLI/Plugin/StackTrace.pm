package App::CLI::Plugin::StackTrace;

use strict;
use warnings;
use Devel::StackTrace;
use Fcntl qw(:DEFAULT :flock);

our $CONTEXT_LINE   = 5;
our @IGNORE_PACKAGE = ( __PACKAGE__, "Carp" );
our $VERSION        = '1.0';

sub setup {

	my($self, @argv) = @_;

    my $stacktrace = (exists $self->config->{stacktrace}) ? $self->config->{stacktrace} : undef;

	if ( (exists $stacktrace->{enable} && $stacktrace->{enable} != 0)                   ||
		 (exists $ENV{APPCLI_STACKTRACE_ENABLE} && $ENV{APPCLI_STACKTRACE_ENABLE} != 0) ||
		 (exists $self->{stacktrace} && defined $self->{stacktrace} && $self->{stacktrace} != 0)
	) {
		$self->_build_override_die_subroutine;
	}

	$self->maybe::next::method(@argv);
}

sub _build_override_die_subroutine {

	my $self = shift;

	$SIG{__DIE__} = sub {

		my $message = shift;
		my @frames;
		my $pkg   = ref $self;
		my $trace = Devel::StackTrace->new( ignore_package => \@IGNORE_PACKAGE );
		my $stacktrace_message = <<STACKTRACE_MESSAGE;
$pkg

  $message

----------
STACKTRACE_MESSAGE

		chomp $message;

		LOOP_OF_FRAMES:
		while ( my $frame = $trace->next_frame ) {

			my $start_line = $frame->line - $CONTEXT_LINE;
			my $end_line   = $frame->line + $CONTEXT_LINE;
			if ($start_line < 1) {
				$start_line = 1;
			}

			my @lines;
			open my $fh, "<", $frame->filename or die sprintf("can not open %s. %s", $frame->filename, $!);
			flock $fh, LOCK_EX                 or die sprintf("can not flock %s. %s", $frame->filename, $!);
			while ( my $line = <$fh> ) {

				chomp $line;
				my $current_line = $.;
				if ($current_line < $start_line || $current_line > $end_line) {
					next;
				}
				my $mark = ($current_line == $frame->line) ? "*" : " ";
				push @lines, sprintf("   %s %05d: %s", $mark, $current_line, $line);
			}
			close $fh or die sprintf("can not close %s. %s", $frame->filename, $!);

			my $package  = $frame->package;
			my $filename = $frame->filename;
			my $line     = $frame->line;
			my $lines    = join "\n", @lines;
			$stacktrace_message .= <<STACKTRACE_MESSAGE;
  $package at $filename line $line.

$lines

  ==========
STACKTRACE_MESSAGE

		} # end of LOOP_OF_FRAMES

		$stacktrace_message .= <<STACKTRACE_MESSAGE;
----------

STACKTRACE_MESSAGE

		# rethrow
		die $stacktrace_message;
	};

}

1;

__END__

=head1 NAME

App::CLI::Plugin::StackTrace - for App::CLI::Extension error stacktrace module

=head1 SYNOPSIS

  # MyApp.pm
  package MyApp;
  
  use strict;
  use base qw(App::CLI::Extension);
  
  # extension method
  __PACKAGE__->load_plugins(qw(StackTrace));

  __PACKAGE__->config(stacktrace => { enable => 1 });
  
  1;
  
  # MyApp/Hello.pm
  package MyApp::Hello;
  use strict;
  use feature ":5.10.0";
  use base qw(App::CLI::Command);
  
  sub run {
  
      my($self, @args) = @_;
	  my $x = 1;
	  my $y = 0;
	  my $res = $x / $y;
  }
  
  sub fail {
  
      my($self, @args) = @_;
	  print $self->errstr;
	  $self->exit_value(1);
  }
  
  # myapp
  #!/usr/bin/perl
  
  use strict;
  use MyApp;
  
  MyApp->dispatch;
  
  # execute
  [kurt@localhost ~] ./myapp hello
  MyApp::Hello
  
    Illegal division by zero at /root/perl-work/lib/MyApp/Hello.pm line 12.
  
  
  ----------
    MyApp::Hello at /root/perl-work/lib/MyApp/Hello.pm line 12.
  
      00007: sub run {
      00008: 
      00009: 	my($self, @argv) = @_;
      00010: 	my $x = 1;
      00011: 	my $y = 0;
    * 00012: 	my $res = $x / $y;
      00013: }
      00014: 
      00015: sub fail {
      00016: 
      00017: 	my($self, @argv) = @_;
  
    ==========
    App::CLI::Extension::Component::RunCommand at /usr/lib/perl5/site_perl/5.8.8/App/CLI/Extension/Component/RunCommand.pm line 32.
  
      00027: 	my($self, @argv) = @_;
      00028: 
      00029: 	eval {
      00030: 		$self->setup(@argv);
      00031: 		$self->prerun(@argv);
    * 00032: 		$self->run(@argv);
      00033: 		$self->postrun(@argv);
      00034: 	};
      00035: 	if ($@) {
      00036: 		chomp(my $message = $@);
      00037: 		$self->errstr($message);
  
    ==========
    App::CLI::Extension::Component::RunCommand at /usr/lib/perl5/site_perl/5.8.8/App/CLI/Extension/Component/RunCommand.pm line 29.
  
      00024: 
      00025: sub run_command {
      00026: 
      00027: 	my($self, @argv) = @_;
      00028: 
    * 00029: 	eval {
      00030: 		$self->setup(@argv);
      00031: 		$self->prerun(@argv);
      00032: 		$self->run(@argv);
      00033: 		$self->postrun(@argv);
      00034: 	};
  
    ==========
    App::CLI::Extension at /usr/lib/perl5/site_perl/5.8.8/App/CLI/Extension.pm line 175.
  
      00170: 		unshift @{"$pkg\::ISA"}, @{$class->_components};
      00171: 		unshift @{"$pkg\::ISA"}, @{$class->_plugins};
      00172: 		$cmd->config($class->_config);
      00173: 		$cmd->orig_argv($class->_orig_argv);
      00174: 	}
    * 00175: 	$cmd->run_command(@ARGV);
      00176: }
      00177: 
      00178: ## I really does not want....
      00179: sub error_cmd {
      00180: 	"Command not recognized, try $0 help.\n";
  
    ==========
    main at myapp.pl line 6.
  
      00001: #!/usr/bin/perl
      00002: 
      00003: use strict;
      00004: use MyApp;
      00005: 
    * 00006: MyApp->dispatch;
    
    ==========
  ----------

=head1 DESCRIPTION

App::CLI::Extension stacktrace plugin module

=head1 TIPS

How to display the stacktrace

=head2 CONFIG

If one is to enable the stacktrace is displayed when an error occurs. If enable is 0 is a normal error message appears when an error occurs

Example:

  # MyApp.pm
  __PACKAGE__->config(stacktrace => { enable => 1 });

=head2 ENVIRON VARIABLE

APPCLI_STACKTRACE_ENABLE environ variable setup. 1: stacktrace  0: normal error message

Example:

  export APPCLI_STACKTRACE_ENABLE=1
  ./myapp hello

=head2 OPTION

stacktrace option allows you to specify at runtime, stacktrace can view

Example:

  # MyApp/Hello.pm
  sub options {
      return(stacktrace => "stacktrace");
  }

  # MyApp
  ./myapp --stacktrace hello

=head1 AUTHOR

Akira Horimoto

=head1 SEE ALSO

L<App::CLI::Extension>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

Copyright (C) 2010 Akira Horimoto

=cut

