#!/bin/bash
#andrew ling  2016/09/26

#tool function
netmask_to_subnet() {
  #netmask=255.255.255.0
  netmask=$1
  netmask_list=$(echo $netmask|cut -d. -f1- --output-delimiter=" ")
  sum=0
  for mask in $netmask_list
  do
    if [[ $mask == 0 ]]
    then
      sum=$[$sum+0]
    elif [[ $mask == 128 ]]
    then
      sum=$[$sum+1]
    elif [[ $mask == 192 ]]
    then
      sum=$[$sum+2]
    elif [[ $mask == 224 ]]
    then
      sum=$[$sum+3]
    elif [[ $mask == 240 ]]
    then
      sum=$[$sum+4]
    elif [[ $mask == 248 ]]
    then
      sum=$[$sum+5]
    elif [[ $mask == 252 ]]
    then
      sum=$[$sum+6]
    elif [[ $mask == 254 ]]
    then
      sum=$[$sum+7]
    elif [[ $mask == 255 ]]
    then
      sum=$[$sum+8]
    fi
  done
  return $sum
}

#get the network information, it include:ipaddress,netmask,board cast,gateway
list_network_info() {
  local op=$1
  local nic_name=
  local nics_info=
  local table_name=
  if [ "$op" == "L" ]; then
    #找到所有的网卡设备
    nics_list=$(ls /sys/class/net/)
    for nic in $nics_list; do
      if [ "$nic" == "lo" ] || [ "$nic" == "bonding_masters" ]; then
        continue
      fi
      slave_info=$(ip addr show $nic|grep SLAVE)
      if [ "$slave_info" != "" ]; then
        continue
      fi
      master_info=$(ip addr show $nic|grep MASTER)
      is_master=
      if [ "$master_info" != "" ]; then
        is_master=0
        slaves=$(cat /proc/net/bonding/$nic|grep 'Slave Interface:'|awk -F' ' '{print $3}')
        nics_info=${nics_info}"interface "${nic}", type MASTER, slaves "${slaves}", "
      fi

      table_name=net_${nic}
      ipaddress=$(ip addr show $nic |grep inet[^0-9]|awk -F' ' '{print $2}'|awk -F'/' '{print $1}')
      if [ "$ipaddress" != "" ]; then
        gateway=$(ip route show table $table_name |grep default|awk -F' ' '{print $3}')
      fi
    
      if [ -f /etc/sysconfig/network-scripts/ifcfg-${nic} ]; then
        netmask=$(tail /etc/sysconfig/network-scripts/ifcfg-${nic} |grep NETMASK|awk -F'=' '{print $2}')
      fi
      if [ "$is_master" == "0" ]; then
        nics_info=${nics_info}"ipaddress "${ipaddress}", gateway "${gateway}", netmask "${netmask}";"
      else
        nics_info=${nics_info}"interface "${nic}", ipaddress "${ipaddress}", gateway "${gateway}", netmask "${netmask}";"
      fi
      
    done
    echo $nics_info

  elif [ "$op" == "l" ]; then
    nic_name=$2
    table_name=net_${nic_name}

    ipaddress=$(ip addr show $nic_name |grep inet[^0-9]|awk -F' ' '{print $2}'|awk -F'/' '{print $1}')
    if [ "$ipaddress" != "" ]; then
      gateway=$(ip route show table $table_name |grep default|awk -F' ' '{print $3}')
    fi
    
    if [ -f /etc/sysconfig/network-scripts/ifcfg-${nic_name} ]; then
      netmask=$(tail /etc/sysconfig/network-scripts/ifcfg-${nic_name} |grep NETMASK|awk -F'=' '{print $2}')
    fi

    master_info=$(ip addr show $nic_name|grep MASTER)
    is_master=
    if [ "$master_info" != "" ]; then
      is_master=0
      slaves=$(cat /proc/net/bonding/$nic_name|grep 'Slave Interface:'|awk -F' ' '{print $3}')
      nics_info="interface "${nic_name}", type MASTER, slaves "${slaves}", ipaddress "${ipaddress}", gateway "${gateway}", netmask "${netmask}
    else
      nics_info="interface "${nic_name}", type SLAVE, ipaddress "${ipaddress}", gateway "${gateway}", netmask "${netmask}
    fi
    echo $nics_info
  fi

}

#set the network
set_network() {
  local nic_name=$1
  local ipaddress=$2
  local netmask=$3
  local gateway=$4
  local is_default_gw=$5

  #如果网卡存在，但配置文件不存在，即创建网卡配置文件，如果网卡不存在，即抛出
  is_nic_exist=$(ip addr show |grep ' '${nic_name}':')
  cd /etc/sysconfig/network-scripts
  if [ ! -f ifcfg-$nic_name ]; then
    if [ "$is_nic_exist" != "" ]; then
      cat > ifcfg-${nic_name} << EOF
DEVICE=${nic_name}
NAME=${nic_name}
TYPE=Ethernet
BOOTPROTO=none
ONBOOT=no
EOF
    else
      exit 3
    fi
  fi
  #删除旧ipaddress，然后再赋值新ipaddress
  #ip link set $nic_name down
  old_netmask=$(tail /etc/sysconfig/network-scripts/ifcfg-${nic_name} |grep NETMASK|awk -F'=' '{print $2}')
  if [ "$old_netmask" != "" ]; then
    netmask_to_subnet $old_netmask
    old_subnet=$?
    old_ipaddress=$(ip addr show $nic_name |grep inet[^0-9]|awk -F' ' '{print $2}'|awk -F'/' '{print $1}')
    ip addr del ${old_ipaddress}/${old_subnet} dev $nic_name
    #删除旧的route规则和rule规则
    table_name=net_${nic_name}
    ip route flush table $table_name
    ip rule del from $old_ipaddress table $table_name
  fi

  netmask_to_subnet $netmask
  new_subnet=$?
  ip addr add ${ipaddress}/${new_subnet} dev $nic_name

#将新的网络接口信息放到网络接口配置文件中
cat > ifcfg-$nic_name << EOF
TYPE=Ethernet
BOOTPROTO=static
DEFROUTE=yes
PEERDNS=yes
PEERROUTES=yes
IPV4_FAILURE_FATAL=no
IPV6INIT=yes
IPV6_AUTOCONF=yes
IPV6_DEFROUTE=yes
IPV6_PEERDNS=yes
IPV6_PEERROUTES=yes
IPV6_FAILURE_FATAL=no
ONBOOT=yes
NAME=${nic_name}
DEVICE=${nic_name}
IPADDR=${ipaddress}
NETMASK=${netmask}
EOF

  if [ "$is_default_gw" == "0" ]; then
cat >> ifcfg-$nic_name << EOF
GATEWAY=${gateway}
EOF
    #重启网络
    service network restart
    #先删除默认路由，然后再创建默认路由网关，考虑存在多个默认网卡的出错情况。
    default_gw_list=$(ip route show|grep default|grep -v 'default via '${gateway}' dev '${nic_name}|awk -F' ' '{print $3}')
    for gw in $default_gw_list
    do
      ip route del default
    done
    is_set_default_gw=$(ip route show|grep default|grep 'default via '${gateway}' dev '${nic_name}' ')
    if [[ "$is_set_default_gw" == "" ]]; then
      ip route add default via $gateway  dev $nic_name
    fi

  fi

  #启动网络 注意这里重启了全部的网络，是否仅启动设置的网卡即可呢？ip link set eth0 upi ？
  if [ "$is_default_gw" != "0" ]; then
    ip link set $nic_name up
    service network restart
  fi

  #设置路由和网关，由于网卡一次设置之后，网卡名称不会再变，所以不需要在重复设置同一个网卡时，继续修改rt_tables文件
  table_No=
  table_name=net_${nic_name}
  last_line=$(tail -n 1 /etc/iproute2/rt_tables |grep -v '#1')
  is_set_table=$(cat /etc/iproute2/rt_tables|grep ${table_name}'$')
  if [ "$last_line" == "" ]; then
    table_No=100
    echo "$table_No $table_name " >> /etc/iproute2/rt_tables
  elif [ "$is_set_table" == "" ]; then
    table_No_old=$(tail -n 1 /etc/iproute2/rt_tables |grep -v '#1'|awk -F' ' '{print $1}')
    table_No=$[$table_No_old+1]
    echo "$table_No $table_name" >> /etc/iproute2/rt_tables
  fi

  #清空net_192路由表
  #ip route flush table net_192
  # 添加一个路由规则到 net_192 表，这条规则是 net_192 这个路由表中数据包默认使用源 IP 172.31.192.201 通过 ens4f0 走网关 172.31.192.254
  #ip route add default via 172.31.192.254 dev ens4f0 src 172.31.192.201 table net_192
  #来自 172.31.192.201 的数据包，使用 net_192 路由表的路由规则
  #ip rule add from 172.31.192.201 table net_192

  ip route flush table $table_name
  ip route add default via $gateway dev $nic_name src $ipaddress table $table_name
  ip rule add from $ipaddress table $table_name

}
#set the bonds,support different mode.
#先检查bond功能，如果没有bond模块就返回信息提示，如果有bond模块，但是没有设置好初始化
#先设置bond的初始化功能，然后再设置bond。
init_before_bone() {
  systemctl stop NetworkManager
  #check the system is supported the bond or not
  local supported=$(modinfo bonding | grep filename|awk -F' ' '{print $2}')
  if [ "$supported" == "" ]; then
    exit 5
  fi
  return 0
}

set_bond() {
  local dir_path=/etc/sysconfig/network-scripts/
  local bond_name=$1
  local nics_name=$2
  local mode=$3
  local ipaddress=$4
  local netmask=$5
  local gateway=$6
  local is_default_gw=$7

  bond_info=$(ip addr show |grep ' '${bond_name}':')
  if [ "$bond_info" != "" ]; then
    #判断bond是被配置好的，还是遗留下来的垃圾没有删除干净
    slaves_list=$(cat /proc/net/bonding/$bond_name|grep 'Slave Interface:'|awk -F' ' '{print $3}')
    if [ "$slaves_list" == "" ]; then
      echo -${bond_name} > /sys/class/net/bonding_masters
    else
      exit 4
    fi
  fi
  #cd $dir_path
  local nics_list=$(echo $nics_name | cut -d, -f1- --output-delimiter=" ")
  for nic_name in $nics_list
  do
    is_nic_exist=$(ip addr show |grep ' '${nic_name}':')
    if [ ! -f ${dir_path}ifcfg-${nic_name} ] && [ "$is_nic_exist" == "" ]; then
      exit 3
    fi

cat > ${dir_path}ifcfg-${nic_name} << EOF
DEVICE=${nic_name}
NAME=${nic_name}
TYPE=Ethernet
BOOTPROTO=none
ONBOOT=yes
MASTER=${bond_name}
SLAVE=yes
EOF
  done

cat > ${dir_path}ifcfg-${bond_name} << EOF
DEVICE=${bond_name}
NAME=${bond_name}
TYPE=Bond
BONDING_MASTER=yes
IPADDR=${ipaddress}
NETMASK=${netmask}
PEERDNS=yes
ONBOOT=yes
BOOTPROTO=static
BONDING_OPTS="mode=${mode} miimon=100"
EOF

  if [ "$is_default_gw" == "0" ]; then
cat >> ${dir_path}ifcfg-${bond_name} << EOF
GATEWAY=${gateway}
EOF
    #重启网络
    service network restart
    #先删除默认路由，然后再创建默认路由网关，考虑存在多个默认网卡的出错情况。
    default_gw_list=$(ip route show|grep default|grep -v 'default via '${gateway}' dev '${bond_name}|awk -F' ' '{print $3}')
    for gw in $default_gw_list
    do
      ip route del default
    done

    is_set_default_gw=$(ip route show|grep default|grep 'default via '${gateway}' dev '${bond_name}' ')
    if [[ "$is_set_default_gw" == "" ]]; then
      ip route add default via $gateway  dev $bond_name
    fi
  fi

  if [ "$is_default_gw" != "0" ]; then
    service network restart
  fi
  #设置路由和网关
  table_No=
  table_name=net_${bond_name}
  last_line=$(tail -n 1 /etc/iproute2/rt_tables |grep -v '#1')
  is_set_table=$(cat /etc/iproute2/rt_tables|grep ${table_name}'$')
  if [ "$last_line" == "" ]; then
    table_No=100
    echo "$table_No $table_name" >> /etc/iproute2/rt_tables
  elif [ "$is_set_table" == "" ]; then
    table_No_old=$(tail -n 1 /etc/iproute2/rt_tables |grep -v '#1'|awk -F' ' '{print $1}')
    table_No=$[$table_No_old+1]
    echo "$table_No $table_name" >> /etc/iproute2/rt_tables
  fi

  ip route flush table $table_name
  ip route add default via $gateway dev $bond_name src $ipaddress table $table_name
  ip rule add from $ipaddress table $table_name

  #设置相关的配置文件，以防重启，网络还可以正常使用
  #/etc/rc.d/rc.local和/etc/modprobe.d/dist.conf文件
  chmod +x /etc/rc.d/rc.local
  is_set_rc_profile=$(cat /etc/rc.d/rc.local|grep 'ifenslave '${bond_name}' ')
  if [ "$is_set_rc_profile" == "" ]; then
    echo "ifenslave ${bond_name} ${nics_list}" >> /etc/rc.d/rc.local
  else
    sed -e "/${bond_name} /d"  /etc/rc.d/rc.local > /etc/rc.d/rc.local.tmp
    mv -f /etc/rc.d/rc.local.tmp /etc/rc.d/rc.local
    echo "ifenslave ${bond_name} ${nics_list}" >> /etc/rc.d/rc.local
    chomd +x /etc/rc.d/rc.local
  fi

  if [ ! -f /etc/modprobe.d/dist.conf ]; then
    echo "install ${bond_name} /sbin/modprobe bonding -o ${bond_name} miimon=100 mode=${mode}" >> /etc/modprobe.d/dist.conf
  else
    is_set_dist_profile=$(cat /etc/modprobe.d/dist.conf|grep ${bond_name}' ')
    if [ "$is_set_dist_profile" == "" ]; then
      echo "install ${bond_name} /sbin/modprobe bonding -o ${bond_name} miimon=100 mode=${mode}" >> /etc/modprobe.d/dist.conf
    else
      sed -e "/${bond_name} /d"  /etc/modprobe.d/dist.conf > /etc/modprobe.d/dist.conf.tmp
      mv -f /etc/modprobe.d/dist.conf.tmp /etc/modprobe.d/dist.conf
      echo "install ${bond_name} /sbin/modprobe bonding -o ${bond_name} miimon=100 mode=${mode}" >> /etc/modprobe.d/dist.conf
    fi
  fi

}

disable_bond() {
  bond_name=$1
  table_name=net_${bond_name}
  slaves_list=$(cat /proc/net/bonding/$bond_name|grep 'Slave Interface:'|awk -F' ' '{print $3}')
  ipaddress=$(ip addr show $bond_name|grep inet[^0-9]|awk -F' ' '{print $2}'|awk -F'/' '{print $1}')
  for slave in $slaves_list; do
    #清空网络接口配置文件
cat > /etc/sysconfig/network-scripts/ifcfg-${slave} << EOF
DEVICE=${slave}
NAME=${slave}
TYPE=Ethernet
BOOTPROTO=none
ONBOOT=no
EOF
  done
  rm -f /etc/sysconfig/network-scripts/ifcfg-${bond_name}
  ip route flush table $table_name
  ip rule del from $ipaddress table $table_name
  sed -e "/${table_name}$/d"  /etc/iproute2/rt_tables > /etc/iproute2/rt_tables.tmp
  mv -f /etc/iproute2/rt_tables.tmp /etc/iproute2/rt_tables
  echo -${bond_name} > /sys/class/net/bonding_masters

  #清除相关的配置文件
  #/etc/rc.d/rc.local和/etc/modprobe.d/dist.conf文件
  sed -e "/${bond_name} /d"  /etc/rc.d/rc.local > /etc/rc.d/rc.local.tmp
  mv -f /etc/rc.d/rc.local.tmp /etc/rc.d/rc.local
  chmod +x /etc/rc.d/rc.local
  sed -e "/${bond_name} /d"  /etc/modprobe.d/dist.conf > /etc/modprobe.d/dist.conf.tmp
  mv -f /etc/modprobe.d/dist.conf.tmp /etc/modprobe.d/dist.conf

}

op=

while getopts 'Ll:SADn:i:I:m:g:fd:b:' OPTION
do
  case $OPTION in
    L) Lflag=1
      op="L"
      ;;
    l) nic_name="$OPTARG"
      lflag=1
      op="l"
      ;;
    S) Sflag=1
      ;;
    A) Aflag=1
      ;;
    D) Dflag=1
      ;;
    n) dev="$OPTARG"
      ;;
    i) ipaddress="$OPTARG"
      ;;
    I) nics_name="$OPTARG"
      ;;
    m) netmask="$OPTARG"
      ;;
    g) gateway="$OPTARG"
      ;;
    f) is_default_gw=0
      ;;
    b) bond_name="$OPTARG"
      ;;
    d) mode="$OPTARG"
      ;;
    ?) echo $"Usage : The parameters input error"
      exit 2
      ;;
  esac
done

if [ "$Lflag$lflag$Sflag$Aflag$Dflag" != "1" ]
then
    exit 2
fi

if [ "$Lflag" == "1" ]
then
  #list the nic info
  network_info=$(list_network_info $op)
  echo $network_info && exit 0
fi

if [ "$lflag" == "1" ]
then
  #list the nic info
  network_info=$(list_network_info $op $nic_name)
  echo $network_info && exit 0
fi

if [ "$Sflag" == "1" ]
then
  #set the network
  set_network $dev $ipaddress $netmask $gateway $is_default_gw
  exit $?
fi

if [ "$Aflag" == "1" ]
then
  init_before_bone
  set_bond $bond_name $nics_name $mode $ipaddress $netmask $gateway $is_default_gw
  exit $?
fi

if [ "$Dflag" == "1" ]
then
  disable_bond $bond_name
  exit $?
fi
exit 0