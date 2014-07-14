#/usr/bin/perl
push(@INC, ".");
use Data::Dumper;
use Time::Local;
use IO::File;
use DBI;
#getMqDepth();
#exit;
#unitTestTime();
#unitTestgetDetailInfo();
$ENV{"NLS_LANG"} = 'AMERICAN_AMERICA.zhs16cgb231280';
my $insert_db_flag=1;

print "----------------mq depth monitor thread start!----------------------------\n";
my $debug_flag =1 ;
my ($db_handler);
my $MY_HOME = "./log";
my $MAXLOGSIZE = 8388608;
my $DefaultLOGNAME = $MY_HOME."/caiji_mq_depth.csv";
my $LogFileIndex = 0;
my ($logFile, $LOGNAME);
setLogName();
$logFile=IO::File->new($LOGNAME, "w+");
my $scan_mq_list="mq_list";
my $monitor_time=""; 
my $last_time_str=0;
my $monitor_time_epoch="";
while(1){
	open(FH, '<', $scan_mq_list) or die $!;
	if($insert_db_flag){
		initDB();
	}
	while(<FH>){
		my $line=$_;
		chomp($line);
		my $cur_max=getMqDepth("WNMS4_QM","$line");
		if($cur_max =~/null/){
		}
		else{	
			my @array=split ("_",$cur_max);
			my $curdepth=$array[0];
			my $maxdepth=$array[1];
			my $time_str = getTimeString(time);
			if($insert_db_flag){
				my $insert_sql = qq{INSERT INTO caiji_mq_depth ( qmgr_name, queue_name, current_depth, max_depth, record_time ) VALUES( ?,?,?,?,?)};  
				my $sth = $db_handler->prepare($insert_sql);  
				$sth->execute("WNMS4.QM",$line, $curdepth, $maxdepth,$time_str);  
			}
		}	
	}
	$last_time_str=$monitor_time_epoch;
	close(FH);
	$db_handler->disconnect();
	sleep (60*5);
}
###########################################################
# PROCEDURE: getTimeString
# PURPOSE:  convert file modify time to readable format 2014-06-13 17:05:19
###########################################################
sub getTimeString{
	my $time_str=shift;
	my  ($sec,$min,$hour,$mday,$mon,$year) = (localtime($time_str))[0..5];
	($sec,$min,$hour,$mday,$mon,$year) = (
		sprintf("%02d", $sec),
		sprintf("%02d", $min),
		sprintf("%02d", $hour),
		sprintf("%02d", $mday),
		sprintf("%02d", $mon + 1),
		$year + 1900
	);
	my $time_string=$year.'-'.$mon.'-'.$mday.' '.$hour.':'.$min.':'.$sec;
	return "$time_string";
}

sub unitTestTime{
	my $time=time;
	my $time_str=getTimeString($time);
	my $time2=convertTime2Epoch($time_str);
	my $cha=($time2-$time)/86400;
	print "$time  $time_str $time2 ($cha)\n";
}

sub setLogName {
	my $time_str=getTimeString(time);
	$time_str=~s/( .*)//;
	$time_str=~s/( .*)//;
	print "time_str: $time_str\n" if (1== $debug_flag);
	$LOGNAME = $DefaultLOGNAME.$time_str.$$.$LogFileIndex;
	print "LOGNAME: $LOGNAME\n" if (1== $debug_flag);
	++$LogFileIndex;
	$LogFileIndex = 0 if $LogFileIndex > 10;
}

sub writeLog{
	my $content = shift;
	my $fs;
	$logFile=IO::File->new($LOGNAME,"w+") unless -e $LOGNAME ;
	if ($fs=stat($LOGNAME))
	{
		close($logFile);
		$logFile=IO::File->new($LOGNAME,"a+");
		$fs = stat($LOGNAME);
	}
	if (@$fs[7] >= $MAXLOGSIZE) {               # size of file
		close($logFile);
		setLogName();
		$logFile = IO::File->new($LOGNAME, "w+");
	}
	my $now = getTimeString(time);
	#$content = $now.": ".$content;
	print $logFile "$content\n";
	print "$content\n";
	close $logFile;
}

sub initDB() {
	my $user_id='nmosdb';
	my $passwd='nmosoptr';
	$db_handler= DBI->connect("dbi:Oracle:host=10.0.2.193;sid=wnms;port=1521",
		$user_id,
		$passwd
	) || die "can NOT connect";
}

sub convertTime2Epoch{
	my $time_str=shift;
	if($time_str=~/(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/){
		my $s=$6;
		my $m=$5;
		my $h=$4;
		my $day=$3;
		my $month=$2;
		my $year=$1;
		my $time = Time::Local::timelocal($s, $m, $h, $day, $month, $year);
		return $time;
	}else{
		return "";
	}
}

###########################################################
# PROCEDURE: Usage
# PURPOSE: Prints Usage of the command.
###########################################################
sub Usage {
	print <<USAGE;
caiji_gaia_monitor.pl usage
	perl caiji_gaia_perform.pl gaia_perform_log_path 
Example
	perl caiji_gaia_perform.pl /opt/BOCO.MQ/GAIA/log/perform.log
USAGE
}

sub unitTestgetDetailInfo{
	my $test_str="[DEBUG] [2014-07-03 14:32:21,179] [AlarmFilter] [perform:25] - [AlarmFilterAdapter-SPD1{cost=[18 ms],messageCount=[1000 record],speed=[55555.55555555556 records/s]}]";
	my $ret=getDetailInfo($test_str);
	print "$ret\n";
}

sub getDetailInfo{
	# time_str,module_name, sub_filter_name,speed
	my $raw_info=shift;
	if($raw_info=~/\[(\d\d\d\d-.*),\d+\] \[(\S+)\].*- \[(\S+){.*speed=\[(\S+) /){
		my $time_str=$1;
		my $module_name=$2;
		my $sub_filter_name=$3;
		my $speed =$4;
		my $trim_speed = sprintf("%.2f",$speed);
		if($module_name=~/filter/i){
			return "$time_str,$sub_filter_name,$trim_speed";
		}else{
			return "$time_str,$module_name,$trim_speed";
		}
		print "$time_str $module_name $sub_filter_name  $speed $trim_speed\n";
	}
	else{
		return "";}
}


sub getMqDepth{
	my $qmanager_name=shift;
	my $mq_name=shift;
	my ($curdepth, $maxdepth) = ("null","null");
	my $cmd="echo \"dis ql($mq_name) curdepth maxdepth\"  | runmqsc $qmanager_name";
	(1 eq $debug_flag ) && print "cmd: $cmd\n" ;
	my $output=`$cmd  2>&1`;
	print "$cmd\n$output";	
	if ($output=~/curdepth\((\d+)\)/i){
		$curdepth=$1;
	}
	if ($output=~/maxdepth\((\d+)\)/i){
		$maxdepth=$1;
	}
	return $curdepth."_".$maxdepth;
}
