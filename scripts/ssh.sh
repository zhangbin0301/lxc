#!/bin/bash
# by https://github.com/spiritLHLS/lxc

REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'")
RELEASE=("debian" "ubuntu" "centos" "centos")
PACKAGE_UPDATE=("apt -y update" "apt -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove")
temp_file_apt_fix="/tmp/apt_fix.txt"
[[ $EUID -ne 0 ]] && exit 1
CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")
for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done
for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

apt-get update -y
if [ $? -ne 0 ]; then
   dpkg --configure -a
   apt-get update -y
fi
if [ $? -ne 0 ]; then
   apt-get install gnupg -y
fi
apt_update_output=$(apt-get update 2>&1)
echo "$apt_update_output" > "$temp_file_apt_fix"
if grep -q 'NO_PUBKEY' "$temp_file_apt_fix"; then
    public_keys=$(grep -oE 'NO_PUBKEY [0-9A-F]+' "$temp_file_apt_fix" | awk '{ print $2 }')
    joined_keys=$(echo "$public_keys" | paste -sd " ")
    echo "No Public Keys: ${joined_keys}"
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys ${joined_keys}
    apt-get update
    if [ $? -eq 0 ]; then
        echo "Fixed"
    fi
fi
rm "$temp_file_apt_fix"

install_required_modules() {
    modules=("dos2unix" "wget" "sudo" "sshpass" "openssh-server")
    for module in "${modules[@]}"
    do
        if dpkg -s $module > /dev/null 2>&1 ; then
            echo "$module 已经安装！"
        else
            apt-get install -y $module
	    if [ $? -ne 0 ]; then
	        apt-get install -y $module --fix-missing
	    fi
            echo "$module 已尝试过安装！"
        fi
    done
}

[[ -z $SYSTEM ]] && exit 1
install_required_modules
sshport=22
sudo service iptables stop 2> /dev/null ; chkconfig iptables off 2> /dev/null ;
sudo sed -i.bak '/^SELINUX=/cSELINUX=disabled' /etc/sysconfig/selinux;
sudo sed -i.bak '/^SELINUX=/cSELINUX=disabled' /etc/selinux/config;
sudo setenforce 0;
echo root:"$1" |sudo chpasswd root;
sudo sed -i "s/^#\?Port.*/Port $sshport/g" /etc/ssh/sshd_config;
sudo sed -i "s/^#\?PermitRootLogin.*/PermitRootLogin yes/g" /etc/ssh/sshd_config;
sudo sed -i "s/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g" /etc/ssh/sshd_config;
sudo sed -i 's/#ListenAddress 0.0.0.0/ListenAddress 0.0.0.0/' /etc/ssh/sshd_config
sudo sed -i 's/#ListenAddress ::/ListenAddress ::/' /etc/ssh/sshd_config
sudo sed -i 's/#AddressFamily any/AddressFamily any/' /etc/ssh/sshd_config
sudo service ssh restart
sudo service sshd restart
rm -rf "$0"
