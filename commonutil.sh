#!/bin/bash
#export ANSIBLE_SSH_ARGS="-o StrictHostKeyChecking=no"
export ANSIBLE_SSH_ARGS="-o StrictHostKeyChecking=no -o ServerAliveInterval=30"
export  ANSIBLE_INVENTORY_IGNORE="~, .orig, .bak, .ini, .cfg, .retry, .pyc, .pyo, .yml, .md, .sh, images, .log, .service,Vagrantfile, .out, .tf, .tfstate, .backup, .tfvars"
export ANSIBLE_LOG_PATH="./ansible-`date +%Y%m%d%H%M%S`.log"
export ANSIBLE_SSH_PIPELINING=True


parse_yaml(){
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

eval $(parse_yaml common_vars.yml)
eval $(parse_yaml $VIRT_TYPE/vars.yml)


common_execansible(){
			starttime=`date`
   ansible-playbook -f 64 -T 600 -i $VIRT_TYPE $*
   echo "###START $starttime END `date` ###"
}

common_runall(){
	common_runonly $*
	common_execansible rac.yml
}

common_jdbcrunner(){
	common_runall $*
	common_execansible rac.yml --tags jdbcrunner --extra-vars "jdbcrunner=on"
}

common_jdbcrunner_only(){
	common_execansible rac.yml --tags jdbcrunner --extra-vars "jdbcrunner=on"
}

common_cvu(){
	common_runonly $*
	common_execansible rac.yml --skip-tags installdbca --extra-vars "cvu=on"
}

common_cvu_only(){
	common_execansible rac.yml --skip-tags installdbca --extra-vars "cvu=on"
}

common_iperf(){
	common_runonly 1
	if [ "$1" = "vxlan0" ]; then
 		common_execansible rac.yml --tags ssh,misc,vxlan_conf
	else
		common_execansible rac.yml --tags ssh,misc
	fi
	common_execansible rac.yml --tags iperf --extra-vars "IPERF_DEV=$1"
}

common_iperf_only(){
	if [ "$1" = "vxlan0" ]; then
 		common_execansible rac.yml --tags ssh,misc,vxlan_conf
	else
		common_execansible rac.yml --tags ssh,misc
	fi
	common_execansible rac.yml --tags iperf --extra-vars "IPERF_DEV=$1"
}

common_preinstall(){
	common_runonly $*
	common_execansible rac.yml --skip-tags installdbca
}

common_preinstall_with_vnc(){
	common_runonly $*
	common_execansible rac.yml --skip-tags installdbca --extra-vars "vnc=on"
	common_execansible rac.yml --tags download
}

common_after_runonly(){
	common_execansible rac.yml
}

common_install_dbca(){
	common_execansible rac.yml --tags installdbca
}

common_gridrootsh(){
	common_execansible rac.yml --tags installdbca --skip-tags runinstallergrid
}

common_deleteall(){
        export TF_VAR_db_servers=0
	export TF_VAR_client=0
	cd $VIRT_TYPE

	terraform destroy -auto-approve
	cd ../
 
 	rm -rf $VIRT_TYPE/*.inventory
	rm -rf $VIRT_TYPE/group_vars
	rm -rf $VIRT_TYPE/host_vars
 
}

common_heatrun(){
LOG="`date "+%Y%m%d-%H%M%S"`_$VIRT_TYPE.log"
echo "ALLSTART `date "+%Y%m%d-%H%M%S"`" >>$LOG
for i in `seq 1 $2`
do
    common_deleteall >>$LOG  2>&1
    STARTTIME=`date "+%Y%m%d-%H%M%S"`
    common_runall $1 >>$LOG  2>&1
    common_execansible rac.yml --tags reboot_and_crsctl,jdbcrunner --extra-vars '{"jdbcrunner":"on","reboot_and_crsctl":"on"}'    
    echo "START $STARTTIME" >>$LOG
    echo "END `date "+%Y%m%d-%H%M%S"`" >>$LOG
done
common_deleteall >>$LOG  2>&1
echo "ALLEND `date "+%Y%m%d-%H%M%S"`" >>$LOG
}

common_all_replaceinventory(){
	for FILE in $VIRT_TYPE/host_vars/*
	do
		INSTANCE_ID=`echo $FILE | awk -F '/' '{print $3}'`
		External_IP=`get_External_IP $INSTANCE_ID`
		common_replaceinventory $INSTANCE_ID $External_IP
	done
}

common_runonly(){

	if [  ! -e ${ansible_ssh_private_key_file} ] ; then
		ssh-keygen -t rsa -P "" -f $ansible_ssh_private_key_file
		chmod 600 ${ansible_ssh_private_key_file}*
	fi
 	
	if [ "$1" = "" ]; then
		nodecount=3
	else
		nodecount=$1
	fi

	export TF_VAR_db_servers=$nodecount
	export TF_VAR_client_servers=0
	export TF_VAR_public_key=`cat ${ansible_ssh_private_key_file}.pub`
	cd $VIRT_TYPE
	
	terraform init
	terraform apply -auto-approve

 	
	if [ $? != 0 ]; then 
		exit 255 
	fi

	cd ../
	
	STORAGEIntIP=`get_Internal_IP storage`
	STORAGEExtIP=`get_External_IP storage`
	common_update_all_yml "STORAGE_SERVER: $STORAGEIntIP"

	common_update_ansible_inventory storage $STORAGEExtIP storage 0 storage
	for i in `seq 1 $nodecount`;
	do
		NODENAME="$NODEPREFIX"`printf "%.3d" $i`
		External_IP=`get_External_IP $NODENAME`
		common_update_ansible_inventory $NODENAME $External_IP $NODENAME $i dbserver
	done
 	
	


	
#	sleep 60s
#	CLIENTNUM=70
#	NUM=`expr $BASE_IP + $CLIENTNUM`
#	CLIENTIP="${SEGMENT}$NUM"	
#	run "client01" $CLIENTIP $CLIENTNUM "client"
	
}

common_addClient(){
	export TF_VAR_db_servers=`ls $VIRT_TYPE/host_vars/$NODEPREFIX* | wc -l`
	export TF_VAR_client_servers=1
	export TF_VAR_public_key=`cat ${ansible_ssh_private_key_file}.pub`
	cd $VIRT_TYPE
	
	terraform apply -auto-approve
	
	ClientExtIP=`get_External_IP client`
	common_update_ansible_inventory client $ClientExtIP client 70 client
}

#$NODENAME $IP $INSTANCE_ID $nodenumber $hostgroup
common_update_ansible_inventory(){
hostgroup=$5
if [ ! -e $VIRT_TYPE/${hostgroup}.inventory ]; then
  mkdir -p $VIRT_TYPE/host_vars
  cat > $VIRT_TYPE/${hostgroup}.inventory <<EOF
[$hostgroup]
EOF
fi

NODEIP=`expr $BASE_IP + $4`
VIPIP=`expr $NODEIP + 100`
vxlan0_IP="`echo $vxlan0_NETWORK | grep -Po '\d{1,3}\.\d{1,3}\.\d{1,3}\.'`$NODEIP"
vxlan1_IP="`echo $vxlan1_NETWORK | grep -Po '\d{1,3}\.\d{1,3}\.\d{1,3}\.'`$NODEIP"
vxlan2_IP="`echo $vxlan2_NETWORK | grep -Po '\d{1,3}\.\d{1,3}\.\d{1,3}\.'`$NODEIP"
vip_IP="`echo $vxlan0_NETWORK | grep -Po '\d{1,3}\.\d{1,3}\.\d{1,3}\.'`$VIPIP"
    	

ansible_ssh_host=`echo $2 | awk -F ':' '{print $1}'`
ansible_ssh_port=`echo $2 | awk -F ':' '{print $2}'`

if [ "$ansible_ssh_port" = "" ]; then
	echo "$1 ansible_ssh_host=$2" >> $VIRT_TYPE/${hostgroup}.inventory
else
	echo "$1 ansible_ssh_host=$ansible_ssh_host ansible_ssh_port=$ansible_ssh_port" >> $VIRT_TYPE/${hostgroup}.inventory
fi




cat > $VIRT_TYPE/host_vars/$1 <<EOF
NODENAME: $1
vxlan0_IP: $vxlan0_IP
vxlan1_IP: $vxlan1_IP
vxlan2_IP: $vxlan2_IP
public_IP: $vxlan0_IP
vip_IP: $vip_IP
INSTANCE_ID: $3
EOF
}

#$1 addtional all.yml var
common_update_all_yml(){
SCAN0=`expr $BASE_IP - 20`
SCAN1=`expr $BASE_IP - 20 + 1`
SCAN2=`expr $BASE_IP - 20 + 2`
scan0_IP="`echo $vxlan0_NETWORK | grep -Po '\d{1,3}\.\d{1,3}\.\d{1,3}\.'`$SCAN0"
scan1_IP="`echo $vxlan0_NETWORK | grep -Po '\d{1,3}\.\d{1,3}\.\d{1,3}\.'`$SCAN1"
scan2_IP="`echo $vxlan0_NETWORK | grep -Po '\d{1,3}\.\d{1,3}\.\d{1,3}\.'`$SCAN2"	
	
if [ ! -e $VIRT_TYPE/group_vars/all.yml ]; then
	mkdir -p $VIRT_TYPE/group_vars
	cp common_vars.yml $VIRT_TYPE/group_vars/all.yml
	cat $VIRT_TYPE/vars.yml >> $VIRT_TYPE/group_vars/all.yml
	
		cat >> $VIRT_TYPE/group_vars/all.yml <<EOF
scan0_IP: $scan0_IP
scan1_IP: $scan1_IP
scan2_IP: $scan2_IP
EOF
	
fi

if [ "$1" != "" ]; then
	echo "$1" >> $VIRT_TYPE/group_vars/all.yml
fi

}


#$1 instance_name $2 external_IP
common_replaceinventory(){
	sed -i -e "s/$1 ansible_ssh_host=.*\$/$1 ansible_ssh_host=${2}/g" $VIRT_TYPE/*.inventory
}

common_crsctl(){
	common_execansible rac.yml --tags crsctl
}
common_ssh(){
	

if [ "$2" != "" ]; then
	if [ "$3" != "" ]; then
		if [ "$4" != "" ]; then
			ssh -o StrictHostKeyChecking=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -g -L $2:$3:$4 -i $ansible_ssh_private_key_file $ansible_ssh_user@`get_External_IP $1` 
		else
			ssh -o StrictHostKeyChecking=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -g -L $2:127.0.0.1:$3 -i $ansible_ssh_private_key_file $ansible_ssh_user@`get_External_IP $1`	
		fi
	else
		ssh -o StrictHostKeyChecking=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -g -L $2:127.0.0.1:$2 -i $ansible_ssh_private_key_file $ansible_ssh_user@`get_External_IP $1`
	fi
else
	ssh -o StrictHostKeyChecking=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -g -L $FOWARD_PORT:127.0.0.1:8080 -i $ansible_ssh_private_key_file $ansible_ssh_user@`get_External_IP $1`
fi

}


common_get_ssh_port(){
	echo "22"`printf "%.3d" $1` 
}

#$1 ""
#$2 "$NODENAME,$IP,$INSTANCE_ID,$NODENUMBER,$HOSTGROUP $NODENAME,$IP,$INSTANCE_ID,$NODENUMBER,$HOSTGROUP"
common_create_inventry(){
	common_update_all_yml "$1"
	nodelist=$2
	for node in $nodelist;
	do
		NF=`echo $node | awk -F ',' '{print NF}' `
		if [ "$NF" != "5" ]; then
			NODENAME=`echo $node | awk -F ',' '{print $1}' `
			IP=`echo $node | awk -F ',' '{print $2}' `
			NODENUMBER=`echo $node | awk -F ',' '{print $3}' `
			HOSTGROUP=`echo $node | awk -F ',' '{print $4}' `
			INSTANCE_ID=$NODENAME
			common_update_ansible_inventory $NODENAME $IP $INSTANCE_ID $NODENUMBER $HOSTGROUP
		else
			cargs=`echo $node | sed 's/,/ /g'`
			common_update_ansible_inventory $cargs
		fi
	done	
}

