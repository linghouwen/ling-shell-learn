#!/bin/bash

#check the status of iptables
confire_iptables_running() {
  /sbin/service iptables status 1>/dev/null 2>&1
  if [ $? -ne 0 ]; then
  firewall_status=”stopped”
  /sbin/service iptables start
  fi
}

#check the port in the range :0~65535
is_port_in_range() {
  local port=$1
  if [ $port -gt 0 ] && [ $port -le 65535 ]
  then
       return 0
  else
       exit 2
  fi
}


#check the protocol type:tcp,udp,icmp
is_protocol_support() {
  local protocol=$1
  if [ $protocol == "tcp" ] || [ $protocol == "udp" ]
  then
       return 0
  else
       exit 2
  fi
}


#set the iptables rule
set_rules() {
  local op=$1
  local type=$2
  local port=$3
  local is_serial_ports=$4
  
  if [ "$is_serial_ports" == "No" ]
  then
 
    check_result=$(iptables -nvL|grep dpt:$port[^0-9]|awk -F' ' '{print $3}')
    if [ "$check_result" == "ACCEPT" ] && [ "$op" == "-I" ] 
    then
      return 0;
    fi
  fi
  if [ "$is_serial_ports" == "Yes" ]
  then
    check_result_ports=$(iptables -nvL|grep dpts:$port[^0-9]|awk -F' ' '{print $3}')
    if [ "$check_result_ports" == "ACCEPT" ] && [ "$op" == "-I" ]
    then
      return 0;
    fi
  fi

  iptables $op INPUT -p $type -m state --state NEW -m $type --dport $port -j ACCEPT
  result=$?
  if [ $result -ne 0 ]
  then
    exit $result
  fi
}


op=""
pflag=
mflag=
sflag=

while getopts 'ADp:m:l:t:h' OPTION
do
  case $OPTION in
  A) Aflag=1
    op="-I"
    ;;
  D) Dflag=1
    op="-D"
    ;;
  p) pflag=1 
    port="$OPTARG"
    ;;
  m) mflag=1
    multi_ports="$OPTARG"
    ;;
  l) sflag=1
    serial_ports="$OPTARG"
    ;;
  t) protocol_type="$OPTARG"
    ;;
  h) echo $"Usage : $0 {-A|-D|-p:single port|-m multi_ports example:port1,port2,port3|-l serial_ports example:start_port:end_port|-t protocol type|-h help}"
    exit 2
    ;;
  ?) echo $"Usage : $0 {-A|-D|-p:single port|-m multi_ports example:port1,port2,port3|-l serial_ports example:start_port:end_port|-t protocol type|-h help}" 
     exit 2
    ;;
  esac
done

if [ "$Aflag$Dflag" != "1" ]
then
    exit 2
fi

if [ "$pflag$mflag$sflag" != "1" ]
then
    exit 2
fi

confire_iptables_running
is_protocol_support $protocol_type

if [ "$Aflag$Dflag$pflag" == "11" ]
then
    is_port_in_range $port
    is_serial_ports="No"
    set_rules $op $protocol_type $port $is_serial_ports
    if [ $? -ne 0 ]
    then
        exit $?
    fi
fi

if [ "$Aflag$Dflag$mflag" == "11" ]
then
    ports_list=$(echo $multi_ports | cut -d, -f1- --output-delimiter=" ")

    for p in $ports_list
    do
      is_port_in_range $p
      is_serial_ports="No"
      set_rules $op $protocol_type $p $is_serial_ports
      if [ $? -ne 0 ]
      then
        exit $?
      fi
    done
fi

if [ "$Aflag$Dflag$sflag" == "11" ]
then
    start_end_port=$(echo $serial_ports | cut -d: -f1- --output-delimiter=" ")
    start_flag=0
    for p in $start_end_port
    do
      is_port_in_range $p
    done
    is_serial_ports="Yes"
    set_rules $op $protocol_type $serial_ports $is_serial_ports
    if [ $? -ne 0 ]
    then
      exit $?
    fi
fi

#save the rule to iptables file.
/sbin/service iptables save
exit 0
