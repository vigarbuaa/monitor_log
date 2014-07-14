#/usr/bin/perl
push(@INC, ".");
use Data::Dumper;
use Time::Local;
use IO::File;
use DBI;
# 指定所监控perform.log,写配置文件
# 此脚本只支持gaia2.0版本的perform.log (还没想出如何识别gaia2.0,暂将此信息打在屏幕上)
# 结果保存成csv文件，利于后期数据导入(done)
# 扫描文本要有记录，去掉本次扫描与上次扫描的重复部分(done)
# 加log以利于后期排错(done)
# 将最新log日志记在临时文件中，防止重启造成日志混乱
# program_name,module_name,current_depth,timestamp,insert_db_time,record_time,maxdepth,instance_name
# 默认不做入库操作，入库配置会有一个选项+配置文件(目前写在perl中)
# 建表, 定义建表脚本 (done)
#unitTestTime();
#unitTestgetDetailInfo();
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
my $insert_db_flag=1;
if( !-e $scan_file_name){
	print "$scan_file_name does not exist! Please check!\n";
	exit;
}

if($scan_file_name!~/perform/){
	print "----------------此程序只支持对GAIA2.0版本的perform.log进行监控! $scan_file_name无法监控!----------------------------\n";
	exit;
}
print "----------------此程序只支持对GAIA2.0版本的perform.log进行监控!----------------------------\n";
my $debug_flag =1 ;
my ($db_handler);
my $MY_HOME = "./log";
my $MAXLOGSIZE = 8388608;
my $DefaultLOGNAME = $MY_HOME."/caiji_gaia_perform.csv";
my $LogFileIndex = 0;
my ($logFile, $LOGNAME);
setLogName();
$logFile=IO::File->new($LOGNAME, "w+");

my $monitor_time=""; 
my $last_time_str=0;
my $monitor_time_epoch="";
while(1){
	open(FH, '<', $scan_file_name) or die $!;
	if($insert_db_flag){
		initDB();
	}
	while(<FH>){
		my $line=$_;
		if (0==$pattern_flag){
			if ($line=~/speed/){
				my $detail_info=getDetailInfo($line);
				if($detail_info eq ""){
				}else{
					#2014-07-03 14:32:21:AlarmFilterAdapter-SPD1:55555.56
					my @info_array = split (",",$detail_info);
					my $time_str=$info_array[0];
					my $module_name=$info_array[1];
					my $speed=$info_array[2];
					$monitor_time_epoch=convertTime2Epoch($time_str); 
					if($monitor_time_epoch ge $last_time_str){
						writeLog("GAIA,$module_name,$speed,$time_str");
						# insert into db

						if($insert_db_flag){
							my $insert_sql = qq{INSERT INTO caiji_gaia_perform( program_name, module_name, current_speed,  record_time ) VALUES( ?,?,?,?)};  
							my $sth = $db_handler->prepare($insert_sql);  
							$sth->execute("GAIA",$module_name, $speed, $time_str);  
						}	
					}	
				}
			}else{
			}
		}
	}
	$last_time_str=$monitor_time_epoch;
	close(FH);
	$db_handler->disconnect();
	sleep (15);
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



#		if(1==$pattern_flag){
#			if($line =~/^\| (\d+)\s+\|\s+(\S+)/){
#				my $depth=$1;
#				my $channel=$2;
#				print "$channel  $depth\n" if (1==$debug_flag);
#				$monitor_time_epoch=convertTime2Epoch($monitor_time);
#				if($monitor_time_epoch ge $last_time_str){
#					writeLog ( "GAIA,$channel,$depth,null,$monitor_time,3000,instance");
#
#				my $insert_sql = qq{INSERT INTO caiji_gaia_monitor( program_name, module_name, current_depth,  record_time, max_depth) VALUES( ?,?,?,?,?)};  
#				my $sth = $db_handler->prepare($insert_sql);  
#				$sth->execute("GAIA",$channel, $depth, $monitor_time, 3000);  
#
#			}
#
#		}elsif($line=~/^\]$/){
#			print "---change back--\n";
#			$pattern_flag=0;
#		}else{
#		}
