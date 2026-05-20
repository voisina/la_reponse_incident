#!/bin/bash

if [ "$EUID" -ne "0" ]; then
  echo "Le script doit être exécuté comme utilisateur root" >&2
  exit 1
fi

scrap() {
  category="$1"

  shift

  for file in "$@"; do
    [ ! -e "$file" ] && continue
    [ ! -d "$file" ] && dir="${file%/*}" || dir="$file"

    dest="$dest_dir/$category/$dir"
    mkdir -p "$dest" && cp -a "$file" "$dest"
  done
}


# +---------------+
# |  Préparation  |
# +---------------+

#  Récupération du nom d'hôte
# ----------------------------
echo "Récupération du nom d'hôte"
hostname=""
if which hostname &> /dev/null; then
  hostname=$(hostname)
elif (which hostnamectl && which grep && which sed) &> /dev/null; then
  hostname=$(hostnamectl | grep hostname | sed 's/.*: \(.*\)/\1/')
elif [ -r /proc/sys/kernel/hostname ] && which cat &> /dev/null; then
  hostname=$(cat /proc/sys/kernel/hostname)
elif [ -r /etc/hostname ] && which cat &> /dev/null; then
  hostname=$(cat /etc/hostname)
fi

[ -z "$hostname" ] && hostname="unknown" && echo "Impossible d'obtenir le nom de la machine. Utilisation de unknown"

#  Création de l'arborescence
# ----------------------------
echo "Création de l'arborescence"
tmp_dir="$(mktemp -d)"
dest_dir="${tmp_dir}/$hostname"
for dir in logs network processus services shells crons root_access ssh modules binaries; do
  mkdir -p "${dest_dir}/${dir}"
done

# +-------------------------+
# |  Récupération des logs  |
# +-------------------------+
echo "Copie des fichiers de logs"
scrap logs /var/log
scrap logs /etc/rsyslog.conf /etc/rsyslog.d
scrap logs /etc/syslog.conf
scrap logs /etc/syslog-ng
scrap logs /etc/systemd/journald.conf
scrap logs /etc/logrotate.conf /etc/logrotate.d

# +----------------------------------------+
# |  Récupération des informations réseau  |
# +----------------------------------------+
echo "Récupération des connexions réseau"

#  Connexions réseau
# -------------------
which lsof &> /dev/null && lsof -i &> "${dest_dir}/network/lsof-i"
which ss &> /dev/null && {
  ss --summary &> "${dest_dir}/ss-summary"
  ss -put &> "${dest_dir}/network/ss-put"
  ss -px &> "${dest_dir}/network/ss-px"
}
which netstat &> /dev/null && {
  netstat -put &> "${dest_dir}/network/netstat-pute"
  netstat -px &> "${dest_dir}/network/netstat-px"
}
scrap network /proc/net/{tcp,tcp6,udp,udp6,unix}

#  ACL Pare-feu
# --------------
which iptables &> /dev/null && iptables -L -v -n &> "${dest_dir}/network/iptables"
which nft &> /dev/null && nft list ruleset &> "${dest_dir}/network/nft"
which firewall-cmd &> /dev/null && {
  systemctl status firewalld &> "${dest_dir}/network/firewalld-status"
  firewall-cmd --list-all-zones &> "${dest_dir}/network/firewall-cmd-list-all-zones"
}

#  Informations  interfaces
# --------------------------
which ip &> /dev/null && {
  ip a &> "${dest_dir}/network/ip-a"
  ip route show &> "${dest_dir}/network/ip-route-show"
}
which ifconfig &> /dev/null && ifconfig -a &> "${dest_dir}/network/ifconfig-a"
which route &> /dev/null && route &> "${dest_dir}/network/route"

scrap network /etc/resolv.conf

# +------------------------------+
# |  Récupération des processus  |
# +------------------------------+
echo "Récupération des processus"
which ps &> /dev/null && ps axjf &> "${dest_dir}/processus/ps-axjf"
for process in /proc/[0-9]*; do
  scrap processus "$process/cmdline" "$process/status"
done

# +-----------------------------+
# |  Récupération des services  |
# +-----------------------------+

#  Fichiers globaux
# ------------------
echo "Récupération des fichiers de services"
scrap services /etc/init.d /etc/rc.d
scrap services /usr/lib/systemd/system /usr/lib/systemd/user /run/systemd/system /run/systemd/users /etc/systemd/user

if which systemctl &> /dev/null; then
  systemctl &> "${dest_dir}/services/systemctl"
  systemctl list-unit-files --type=service --state=enabled &> "${dest_dir}/services/systemctl-list-unit-files"
  systemctl list-timers --all &> "${dest_dir}/services/systemctl-list-timers"
fi

#  Fichiers utilisateurs
# -----------------------
echo "Récupération des services utilisateurs"
while read -r home; do
  scrap services "$home/.config/systemd/user"
done < <(cut -d':' -f6 /etc/passwd)

# +----------------------------------+
# |  Récupération des fichiers cron  |
# +----------------------------------+
echo "Récupération des tâches planifiées"
scrap crons /etc/cron.d /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly /etc/cron.yearly /var/spool/cron/ /etc/cron.allow /etc/cron.deny
scrap crons /var/spool/anacron
scrap crons /etc/atd.allow /etc/atd.deny /var/spool/at

# +------------------------------------+
# |  Récupération des fichiers shells  |
# +------------------------------------+

#  Fichiers globaux
# ------------------
echo "Récupération des fichiers globaux pour Bash et Zsh"
for file in /etc/bash.bashrc /etc/profile /etc/zsh /etc/skel; do
  [ -e "$file" ] && scrap shells "$file"
done

#  Fichiers utilisateurs
# -----------------------
echo "Récupération des configuration Bash et Zsh des utilisateurs"
while read -r home; do
  scrap shells .bashrc .profile .bash_profile .bash_login .bash_history
  scrap shells .zshrc .zshenv .zsh_history
done < <(cut -d':' -f6 /etc/passwd)

# +-----------------------------------+
# |  Recherche des accès privilégiés  |
# +-----------------------------------+
echo "Obtention des utilisateurs dans les groupes privilégiés"
getent group sudo &> "${dest_dir}/root_access/sudo_group"
getent group wheel &> "${dest_dir}/root_access/wheel_group"
if which grep &> /dev/null; then
  grep '^\([^:]*:\)\{2\}0:.*' /etc/passwd &> "${dest_dir}/root_access/users_with_uid_0"
else
  cp -a /etc/passwd "${dest_dir}/root_access/passwd"
fi

# +-----------------------------------------+
# |  Récupération des configs et accès ssh  |
# +-----------------------------------------+
echo "Récupération des configurations SSH"
[ -d /etc/ssh ] && scrap ssh /etc/ssh
while read -r home; do
  scrap ssh .ssh/authorized_keys .ssh/known_hosts
done < <(cut -d':' -f6 /etc/passwd)

# +-----------------+
# |  Modules noyau  |
# +-----------------+
echo "Obtention de la liste des modules noyau"
scrap modules /etc/modules /etc/modprobe.d /etc/modules-load.d

lsmod &> "${dest_dir}/modules/list_of_modules"

# +--------------------------------------------------------+
# |  Récupération des binaires avec permissions spéciales  |
# +--------------------------------------------------------+
echo "Recherche des binaires avec permissions spéciales"
if which find &> /dev/null; then
  #  SetUID
  # --------
  find / -perm -4000 -type f &> "${dest_dir}/binaries/suid"

  #  SetGID
  # --------
  find / -perm -2000 -type f &> "${dest_dir}/binaries/sgid"
fi

# +-------------------------+
# |  Création de l'archive  |
# +-------------------------+
echo "Compression des résultats"
tar -C "$tmp_dir" --atime-preserve --same-owner --same-permissions -czf /tmp/computer_info.tar.gz "$hostname"
chmod +r /tmp/computer_info.tar.gz
rm -r "$dest_dir"
