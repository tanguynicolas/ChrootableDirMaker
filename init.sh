#!/bin/bash -u
#
# Prerequisites: all commands in SHELL_TO_IMPORT + COMMANDS_TO_IMPORT + all commands used in bin_test()

# User variables
ENV="newroot"
USER_TO_IMPORT="tnya"
DIR_TO_IMPORT="to_import"
SHELL_TO_IMPORT=(/bin/bash /usr/bin/bash)
COMMANDS_TO_IMPORT=( id ls whoami hostname curl ps lighttpd uftpd nc ngircd dropbear )
SSH_PUBKEY_FILE=/home/tnya/.ssh/vm.pub # For Dropbear only
SSH_PRIVKEY_FILE=/home/tnya/.ssh/vm    # For Dropbear only

RED='\033[0;31m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
BOLD='\033[1m'
ITALIC='\e[3m'
NC='\033[0m'

[ "$EUID" -ne 0 ] && echo "Please run as root." && exit 1
[[ -z ${ENV} ]]                && echo "Please fill ENV var from $0."                && exit 1
[[ -z ${USER_TO_IMPORT} ]]     && echo "Please fill USER_TO_IMPORT var from $0."     && exit 1
[[ -z ${DIR_TO_IMPORT} ]]      && echo "Please fill DIR_TO_IMPORT var from $0."      && exit 1
[[ -z ${SHELL_TO_IMPORT} ]]    && echo "Please fill SHELL_TO_IMPORT var from $0."    && exit 1
[[ -z ${COMMANDS_TO_IMPORT} ]] && echo "Please fill COMMANDS_TO_IMPORT var from $0." && exit 1
[[ -z ${SSH_PUBKEY_FILE} ]]    && echo "Please fill USER_TO_IMPORT var from $0."     && exit 1
[[ -z ${SSH_PRIVKEY_FILE} ]]   && echo "Please fill USER_TO_IMPORT var from $0."     && exit 1

delete_env() {
    umount $ENV/dev/log --force 2> /dev/null
    umount $ENV/proc    --force 2> /dev/null
    umount $ENV/dev/pts --force 2> /dev/null
    rm -rf $ENV

    return 0
}

stop_daemons() {
    pkill dropbear
    pkill lighttpd
    pkill uftpd
    pkill ngircd

    return 0
}

display_result(){
    binary=$1
    result=$2

    if [ $result -eq 0 ]; then
        echo -e "\t${binary} ${GREEN}work${NC} fine."
    else
        echo -e "\t${binary} ${RED}doesn't work${NC}."
    fi

    return 0
}

bin_test() {
    case $1 in

        bash)
            chroot $ENV bash -c 'test 0' &>/dev/null
            display_result Bash $?
            ;;

        lighttpd)
            chroot $ENV bash -c 'lighttpd -f /etc/lighttpd/lighttpd.conf'
            sleep 1
            curl -s 127.0.0.1:8080/index.html &>/dev/null
            display_result Lighttpd $?
            pkill lighttpd
            ;;

        uftpd)
            chroot $ENV bash -c 'uftpd -o ftp=2121,tftp=0 /tmp'
            sleep 1
            lftp -u anonymous, -p 2121 -e "mkdir test-$RANDOM; quit" "127.0.0.1" &>/dev/null
            display_result Uftpd $?
            pkill uftpd
            ;;

        nc)
            chroot $ENV bash -c 'nc -l -p 1234' &>/dev/null &
            sleep 1
            echo "test" | nc -w 2 "127.0.0.1" "1234"
            display_result Nc $?
            ;;

        ngircd)
            rm -f $ENV/tmp/ngircd.log
            chroot $ENV bash -c 'ngircd -n >> /tmp/ngircd.log' &

            (
                sleep 6
                grep -i -E "User.*registered" $ENV/tmp/ngircd.log &>/dev/null
                display_result Ngircd $?
                pkill irssi
                pkill ngircd
            )&

            sleep 3
            irssi -c 127.0.0.1 &>/dev/null
            ;;

        dropbear)
            chroot $ENV bash -c 'dropbear -RE -p "2222" -W "65536"' &>/dev/null
            sleep 1
            rm -f /root/.ssh/known_hosts
            ssh -p 2222 -i "$SSH_PRIVKEY_FILE" $USER_TO_IMPORT@127.0.0.1 -o StrictHostKeyChecking=no "test 0" &>/dev/null
            display_result Dropbear $?
            pkill dropbear &>/dev/null
            ;;

        *)
            echo "Specified binary does not exist."
            exit 1
            ;;
    esac
}

import_cmd_and_libs() {
    libs=$(for cmd in $(which "$@"); do
        ! [ -x "$cmd" ] && echo "$cmd is not an executable file" >&2 && exit 1
        
        # Import the command
        mkdir -p "$ENV/$(dirname "$cmd")"
        cp "$cmd" "$ENV/$cmd"

        # Display libs used by command
        ldd -v "$cmd" \
            | grep '=>' \
	        | sed 's/^.*=> \(.*\)$/\1/' \
	        | sed 's/ ( *0x[0-9a-f][0-9a-f]*)$//' \
	        | sort -u
    done | sort -u)

    # Import the shared libs
    for lib in $libs; do
        mkdir -p "$ENV/$(dirname "$lib")"
        cp "$lib" "$ENV/$lib"
    done
}

# === PARAMETERS ? ===

if [ "${1:-none}" = "delete" ]; then
    stop_daemons
    delete_env && echo -e "🧨 ${RED}WARNING:${NC} Environment deleted."
    exit 0
elif [ "${1:-none}" = "test" ]; then
    stop_daemons
    echo -e "🧪 ${BOLD}Start environment tests:${NC}"
    bin_test bash
    bin_test lighttpd
    bin_test uftpd
    bin_test nc
    bin_test dropbear
    bin_test ngircd
    echo
    exit 0
elif [ "${1:-none}" = "start" ]; then
    stop_daemons
    echo -e "🧰 ${BOLD}Start daemons...${NC}"
    sleep 1
    chroot $ENV bash -c 'dropbear -RE -p "2222" -W "65536"'       2>/dev/null
    chroot $ENV bash -c 'lighttpd -f /etc/lighttpd/lighttpd.conf' 2>/dev/null
    chroot $ENV bash -c 'uftpd -o ftp=2121,tftp=0 /tmp'           2>/dev/null
    chroot $ENV bash -c 'ngircd'                                  2>/dev/null
    echo -e "Done.\n"
    exit 0
elif [ "${1:-none}" = "stop" ]; then
    echo -e "📛 ${BOLD}Stop daemons...${NC}"
    stop_daemons
    echo -e "Done.\n"
    exit 0
elif [ "${1:-none}" = "init" ]; then
    stop_daemons
    # continue
else
    echo -e "📑 ${BOLD}Usage${NC}\n"
    echo -e "⚙️  Initialize new root environment, ready to chroot.\n\t${ITALIC}$0 init${NC}\n"
    echo -e "🧰 Start daemons, ready to use.\n\t${ITALIC}$0 start${NC}\n"
    echo -e "📛 Stop daemons.\n\t${ITALIC}$0 stop${NC}\n"
    echo -e "🧪 Test programs (daemons & others).\n\t${ITALIC}$0 test${NC}\n"
    echo -e "🧨 Delete new root environment.\n\t${ITALIC}$0 init${NC}"
    echo -e "______________________________________\n"
    echo -e "SSH on your environment: ${ITALIC}ssh -p 2222 $USER_TO_IMPORT@127.0.0.1${NC}"
    echo -e "Query website: ${ITALIC}curl 127.0.0.1:8080${NC}"
    echo -e "Transfert files: ${ITALIC}lftp -u anonymous, -p 2121${NC}"
    echo -e "Chat: ${ITALIC}irssi -c 127.0.0.1 THEN \"/join #bienvenue\"${NC}"
    echo -e "\n${ITALIC}Program made by Simon & Tanguy for University of Picardie (UPJV), France.${NC}\n"
    exit 0
fi

# === TRAITEMENTS GÉNÉRAUX ===

echo -e "⚙️  Adding Commands & Shared Libs..."

## Create FHS-like
mkdir -p $ENV
(
    cd $ENV && mkdir -p \
        etc/default \
        proc \
        boot \
        sys \
        dev \
        run \
        var/tmp /var/log \
        home/$USER_TO_IMPORT root \
        lib lib64 \
        usr/bin usr/sbin usr/lib usr/lib64 \
        bin sbin \
        tmp \
        srv
)
chmod 1777 $ENV/tmp

## Import des fichiers de configuration de base
sed 's/systemd//g' /etc/nsswitch.conf > $ENV/etc/nsswitch.conf
grep -E "^$USER_TO_IMPORT|^root" /etc/passwd > $ENV/etc/passwd && sed -i 's|/usr/bin/zsh|/usr/bin/bash|g' $ENV/etc/passwd
grep -E "^$USER_TO_IMPORT|^root" /etc/group > $ENV/etc/group
grep -E "^$USER_TO_IMPORT|^root" /etc/shadow > $ENV/etc/shadow
grep -E "^$(which "${SHELL_TO_IMPORT[@]}")|#" /etc/shells > $ENV/etc/shells

## Import des binaires et de leur librairies
import_cmd_and_libs "${SHELL_TO_IMPORT[@]}" # required
import_cmd_and_libs "${COMMANDS_TO_IMPORT[@]}"
echo -e "🚀 ${CYAN}Commands & Shared Libs successfully added!${NC}\n"

# === TRAITEMENTS SPÉCIFIQUES ===

echo -e "⚙️  Adding specific files for certain commands..."

## Commande ps
mountpoint -q "$ENV/proc" || mount -t proc /proc $ENV/proc

## Commande lighttpd
mkdir -p $ENV/etc/lighttpd $ENV/var/www/html
cp $DIR_TO_IMPORT/lighttpd/lighttpd.conf $ENV/etc/lighttpd
cp $DIR_TO_IMPORT/lighttpd/index.html $ENV/var/www/html
mknod $ENV/dev/null c 1 3 2>/dev/null && chmod go+w $ENV/dev/null

## Commande uftpd
### nothing special...

## Commande nc
### nothing special...

## Commande ngircd
mkdir -p $ENV/etc/ngircd
cp $DIR_TO_IMPORT/ngircd/ngircd.conf $ENV/etc/ngircd/ngircd.conf
grep -E "^irc" /etc/passwd >> $ENV/etc/passwd
grep -E "^irc" /etc/group >> $ENV/etc/group
grep -E "^irc" /etc/shadow >> $ENV/etc/shadow
mkdir -p $ENV/var/run/ngircd && chown irc:irc $ENV/var/run/ngircd
mkdir -p $ENV/usr/share/doc/ngircd/ && cp /usr/share/doc/ngircd/Commands.txt $ENV/usr/share/doc/ngircd

## Commande dropbear
mkdir -p $ENV/etc/dropbear
mknod $ENV/dev/ptmx c 5 2 2>/dev/null && chmod go+w $ENV/dev/ptmx
mkdir -p $ENV/dev/pts/
mountpoint -q "$ENV/dev/pts/" || mount -o bind /dev/pts $ENV/dev/pts/
mkdir -p $ENV/home/$USER_TO_IMPORT/.ssh && cat $SSH_PUBKEY_FILE > $ENV/home/$USER_TO_IMPORT/.ssh/authorized_keys

echo -e "🚀 ${CYAN}Specific files for certain commands successfully added!${NC}\n"

exit 0
