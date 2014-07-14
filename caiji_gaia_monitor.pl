#/usr/bin/perl
push(@INC, ".");
use Data::Dumper;
use Time::Local;
use IO::File;
use DBI;
# 指定所监控monitor.log,写配置文件
# 此脚本只支持gaia2.0版本的monitor.log (还没想出如何识别gaia2.0,暂将此信息打在屏幕上)
# 结果保存成csv文件，利于后期数据导入(done)
# 扫描文本要有记录，去掉本次扫描与上次扫描的重复部分(done)
# 加log以利于后期排错(done)
# 将最新log日志记在临时文件中，防止重启造成日志混乱
# program_name,module_name,current_depth,timestamp,insert_db_time,record_time,maxdepth,instance_name
# 默认不做入库操作，入库配置会有一个选项+配置文件(目前写在perl中)
# 建表, 定义建表脚本 (done)
#unitTestTime();

$ENV{"NLS_LANG"} = 'AMERICAN_AMERICA.zhs16cgb231280';
my $scan_file_name="";
if(@ARGV==1){
	print "@ARGV\n";
	$scan_file_name=$ARGV[0];
}else{
	Usage();
	print "\n--------------arguments error, please assign a log ----------------\n";
	exit;
}

if( !-e $scan_file_name){
	print "$scan_file_name does not exist! Please check!\n";
	exit;
}
if($file_name!~/monitor.log/){
	print "----------------此程序只支持对GAIA2.0版本的monitor.log进行监控! $file_name无法监控----------------------------\n";
	exit;
}
print "----------------此程序只支持对GAIA2.0版本的monitor.log进行监控!----------------------------\n";

my $debug_flag =1 ;
my ($db_handler);
my $MY_HOME = "./log";
my $MAXLOGSIZE = 8388608;
my $DefaultLOGNAME = $MY_HOME."/caiji_gaia_monitor.csv";
my $LogFileIndex = 0;
my ($logFile, $LOGNAME);
setLogName();
$logFile=IO::File->new($LOGNAME, "w+");

my $pattern_flag=0; # 0 to get 采集机通道状态, 1 to get channel
my $monitor_time=""; 
my $last_time_str=0;
my $monitor_time_epoch="";
while(1){
	open(FH, '<', $scan_file_name) or die $!;
	initDB();
	while(<FH>){
		my $line=$_;
		if (0==$pattern_flag){
			if ($line=~/(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d),.*ThreadMonitor:105/){
				$monitor_time=$1;
				print "--change time: $monitor_time--\n";
				$pattern_flag=1;
			}else{
			}
		}

		if(1==$pattern_flag){
			if($line =~/^\| (\d+)\s+\|\s+(\S+)/){
				my $depth=$1;
				my $channel=$2;
				print "$channel  $depth\n" if (1==$debug_flag);
				$monitor_time_epoch=convertTime2Epoch($monitor_time);
				if($monitor_time_epoch ge $last_time_str){
					writeLog ( "GAIA,$channel,$depth,null,$monitor_time,3000,instance");

				my $insert_sql = qq{INSERT INTO caiji_gaia_monitor( program_name, module_name, current_depth,  record_time, max_depth) VALUES( ?,?,?,?,?)};  
				my $sth = $db_handler->prepare($insert_sql);  
				$sth->execute("GAIA",$channel, $depth, $monitor_time, 3000);  

			}

		}elsif($line=~/^\]$/){
			print "---change back--\n";
			$pattern_flag=0;
			#print Dumper(\%channel_hash);
		}else{
		}
	}
}
$last_time_str=$monitor_time_epoch;
close(FH);
$db_handler->disconnect();
sleep (5);
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
	perl caiji_gaia_monitor.pl gaia_monitor_log_path 
Example
	perl caiji_gaia_monitor.pl /opt/BOCO.MQ/GAIA/log/monitor.log
USAGE
}
