#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use MaatkitTest;
use Sandbox;
require "$trunk/bin/pt-table-sync";

my $output;
my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}
else {
   plan tests => 2;
}

$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
$sb->create_dbs($master_dbh, [qw(test)]);

# #############################################################################
# Issue 560: mk-table-sync generates impossible WHERE
# #############################################################################
diag(`/tmp/12345/use < $trunk/t/pt-table-sync/samples/issue_560.sql`);
sleep 1;

# Make slave differ.
$slave_dbh->do('UPDATE issue_560.buddy_list SET buddy_id=0 WHERE player_id IN (333,334)');
$slave_dbh->do('UPDATE issue_560.buddy_list SET buddy_id=0 WHERE player_id=486');

diag(`$trunk/bin/pt-table-checksum --replicate issue_560.checksum h=127.1,P=12345,u=msandbox,p=msandbox  -d issue_560 --chunk-size 50 > /dev/null`);
sleep 1;
$output = `$trunk/bin/pt-table-checksum --replicate issue_560.checksum h=127.1,P=12345,u=msandbox,p=msandbox  -d issue_560 --replicate-check 1 --chunk-size 50`;
$output =~ s/\d\d:\d\d:\d\d/00:00:00/g;
ok(
   no_diff(
      $output,
      "t/pt-table-sync/samples/issue_560_output_1.txt",
      cmd_output => 1,
   ),
   'Found checksum differences (issue 560)'
);

$output = output(
   sub { pt_table_sync::main('--sync-to-master', 'h=127.1,P=12346,u=msandbox,p=msandbox', qw(-d issue_560 --print -v -v  --chunk-size 50 --replicate issue_560.checksum)) },
   trf => \&remove_traces,
);
$output =~ s/\d\d:\d\d:\d\d/00:00:00/g;
ok(
   no_diff(
      $output,
      "t/pt-table-sync/samples/issue_560_output_2.txt",
      cmd_output => 1,
   ),
   'Sync only --replicate chunks'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
exit;