#!/bin/env bash
### script header #############################################################
#: NAME:         convert-redhat6-centos6.sh
#: SYNOPSIS:     convert-redhat6-centos6.sh CONVERT
#: DESCRIPTION:  convert RHEL v6 to latest CentOS 6.X
#: RETURN CODES: 0-SUCCESS, 1-FAILURE
#: RUN AS:       root
#: AUTHOR:       anjel- <andrei.jeleznov@gmail.com>
#: VERSION:      1.0-SNAPSHOT
#: URL:          https://github.com/anjel-/convert-redhat6-to-centos6.git
#: CHANGELOG:
#: DATE:       AUTHOR:          CHANGES:
#: 30.03.2017  anjel-           initial implementation
### external parameters #######################################################
set +x
declare _CHECK_FOR_RHEL=${_CHECK_FOR_RHEL:-1} #enforce the check for RHEL x86_64
declare _REMOVE_DOWNLOADED_FILES="${_REMOVE_DOWNLOADED_FILES:-0}"
declare WORKSPACE="${WORKSPACE-$PWD}" # working folder
declare target_version="6.8" # target Centos version
declare centos_key="RPM-GPG-KEY-CentOS-6"
declare centos_release_rpm="centos-release-6-8.el6.centos.12.3.x86_64.rpm"
declare centos_indexhtml_rpm="centos-indexhtml-6-2.el6.centos.noarch.rpm"
declare python_urlgrabber="python-urlgrabber-3.9.1-11.el6.noarch.rpm"
declare yum_rpm="yum-3.2.29-73.el6.centos.noarch.rpm"
declare yum_fastestmirror_rpm="yum-plugin-fastestmirror-1.1.30-37.el6.noarch.rpm"
declare yum_utils_rpm="yum-utils-1.1.30-37.el6.noarch.rpm"
declare usr_size=4 # size /usr in GB
### internal parameters #######################################################
readonly SUCCESS=0 FAILURE=1
readonly FALSE=0  TRUE=1
exitcode=$SUCCESS
### service parameters ########################################################
set +x
_TRACE="${_TRACE:-0}"       # 0-FALSE, 1-print traces
_DEBUG="${_DEBUG:-1}"       # 0-FALSE, 1-print debug messages
_FAILFAST="${_FAILFAST:-1}" # 0-run to the end, 1-stop at the first failure
_DRYRUN="${_DRYRUN:-0}"     # 0-FALSE, 1-send no changes to remote systems
_UNSET="${_UNSET:-0}"       # 0-FALSE, 1-treat unset parameters as an error
TIMEFORMAT='[TIME] %R sec %P%% util'
(( _DEBUG )) && echo "[DEBUG] _TRACE=\"$_TRACE\" _DEBUG=\"$_DEBUG\" _FAILFAST=\"$_FAILFAST\""
(( _DRYRUN )) && echo "[INFO] running in DRY RUN mode"||true
### initialized params ########################################################
  ostype="$(uname -o)"
  export _LOCAL_HOSTNAME=$(hostname -s);
  case $_OS_TYPE in
    "Cygwin")
      _SCRIPT_DIR="${0%\\*}"
      _SCRIPT_NAME="${0##*\\}"
    ;;
    *)
      declare tempvar="$(readlink -e "${BASH_SOURCE[0]}")"
      _SCRIPT_DIR="${tempvar%/*}"
      _SCRIPT_NAME="${tempvar##/*/}"
      unset tempvar
    ;;
  esac
# set shellopts ###############################################################
(( _TRACE )) && set -x || set +x
(( _FAILFAST )) && { set -o pipefail; } || true
(( _UNSET )) && set -u || set +u
### functions #################################################################
###
function die { #@ print ERR message and exit
	local fail_color=$'\033[31;1m'
	local no_color=$'\033[0m'
	(( _FAILFAST )) && printf "%b[ERR]%b %s\n" "$fail_color" "$no_color" "$@" >&2 \
  || printf "%b[WARN]%b %s\n" "$fail_color" "$no_color" "$@" >&2
	(( _FAILFAST )) && exit $FAILURE || { exitcode=$FAILURE; true; }
} #die
###
function print { #@ print qualified message
  (( _DRYRUN )) && local level="DRY+"||local level=""
  (( _DEBUG )) && level="${level}DEBUG" ||level="${level}INFO"
  printf "[$level] %s\n" "$@"
} #print
###
function is_valid_name { #@ USAGE: is_valid_name [name]
	(( $_DEBUG )) && echo "[DEBUG] aim to check if the name is valid"
	[[ ${1^^} =~ ^[A-Z_][A-Z0-9_]*$ ]]
} #is_valid_name
###
function get_distibution { #@ USAGE:
	(( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
  local var=$1;shift
  local tmp_var
  if grep -q "Red\ Hat\ Enterprise\ Linux" /etc/redhat-release
  then tmp_var="rhel"
  elif grep -q "grep CentOS"  /etc/redhat-release
  then tmp_var="centos"
  else tmp_var="unsupported"
  fi
  if is_valid_name "$var"
  then  printf -v "$var" "%s" "$tmp_var"
  else  printf "%s\n" "$tmp_var"
  fi
} #get_distibution
###
function get_release { #@ USAGE: get_release [VAR]
  (( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
  local var=$1;shift
  local tmp_var
  tmp_var="$(egrep -o 'release\ [0-9]' /etc/redhat-release)"
  if is_valid_name "$var"
  then  printf -v "$var" "%s" "$tmp_var"
  else  printf "%s\n" "$tmp_var"
  fi
} #get_release
###
function initialize { #@ initialization of the script
  (( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
	(( _DEBUG )) && print "initializing the variables"
  arch=$(uname -m)
  get_distibution distibution
  get_release release
  print "found \"$arch\" \"$distibution\" \"$release\""
  [[ ! -d $WORKSPACE ]] && mkdir -p $WORKSPACE
  (( _DEBUG )) && print "WORKSPACE=\"$WORKSPACE\""||true
} #initialize
###
function checkPreconditions { #@ prerequisites for the whole script
  (( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
	(( _DEBUG )) && print "checking the preconditions for the whole script"
  case "$(uname -s)" in
  "CYGWIN_NT-6.1")
    [[ $(id -un) != andrei.jeleznov ]]&& die "please, run the script a root"||:
   ;;
  "Linux")
    [[ $(id -un) != root ]]&& die "please, run the script a root"||:
   ;;
  *) die "unsupported system  \"$CMD\" ";;
  esac
  if (( _CHECK_FOR_RHEL ));then
    [[ ! -f /etc/redhat-release ]] && die "this system belongs not to a redhat family"||:

    [[ $arch != "x86_64" ]] && die "found an unsupported architecture" ||:

    if [[ "$distibution" != "rhel" ]] || [[ "$release" != "release 6" ]]; then
    	die "this script can convert  only RHEL v6"
    fi
  fi
} #checkPreconditions
###
function extend_part { #@ USAGE: 
  (( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
	(( _DEBUG )) && print "extending the /usr filesystem"
	local part size
	if findmnt -no SOURCE /usr >/dev/null
	then 
		part=$(findmnt -no SOURCE /usr)
		size=$(df -P -B1G /usr|tail -1|tr -s " "|cut -d " " -f2)
		(( $_DEBUG )) && echo "[DEBUG] size of \"$part\" is already $size GB"
	fi
	if (( ! _DRYRUN )) &&  (( $size < $usr_size )); then
		if ! lvresize -r -L +1GB $part
		then die "during extending $part"
		fi
	fi
} #extend_part
###
function download_centos_rpm { #@ USAGE: 
	(( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
  (( _DEBUG )) && print "downloading the CentOS rpms"
#
  if [[ ! -f ./$centos_key ]]; then
    (( ! _DRYRUN )) && wget http://mirror.centos.org/centos/$target_version/os/$arch/$centos_key || true
  fi
  [[ ! -f ./$centos_key ]] && die "could not download $centos_key"||print "$centos_key downloaded"
#
  if [[ ! -f ./$python_urlgrabber ]];then
    (( ! _DRYRUN )) &&  wget http://mirror.centos.org/centos/$target_version/os/$arch/Packages/$python_urlgrabber||true
  fi
  [[ ! -f ./$python_urlgrabber ]] && die "could not download $python_urlgrabber"||print "$python_urlgrabber downloaded"
#
  if [[ ! -f ./$centos_release_rpm ]]; then
    (( ! _DRYRUN )) && wget http://mirror.centos.org/centos/$target_version/os/$arch/Packages/$centos_release_rpm ||true
  fi
#
  [[ ! -f ./$centos_release_rpm ]] && die "could not download $centos_release_rpm"||print "$centos_release_rpm downloaded"
#
  if [[ ! -f ./$centos_indexhtml_rpm ]]; then
    (( ! _DRYRUN )) && wget http://mirror.centos.org/centos/$target_version/os/$arch/Packages/$centos_indexhtml_rpm||true
  fi
  [[ ! -f ./$centos_indexhtml_rpm ]] && die "could not download $centos_indexhtml_rpm"||print "$centos_indexhtml_rpm downloaded"
#
  if [[ ! -f ./$yum_rpm ]]; then
    (( ! _DRYRUN )) && wget http://mirror.centos.org/centos/$target_version/os/$arch/Packages/$yum_rpm||true
  fi
  [[ ! -f ./$yum_rpm ]] && die "could not download $yum_rpm"||print "$yum_rpm downloaded"
#
  if [[ ! -f ./$yum_fastestmirror_rpm ]]; then
    (( ! _DRYRUN )) && wget http://mirror.centos.org/centos/$target_version/os/$arch/Packages/$yum_fastestmirror_rpm||true
  fi
  [[ ! -f ./$yum_fastestmirror_rpm ]] && die "could not download $yum_fastestmirror_rpm"||print "$yum_fastestmirror_rpm downloaded"
#
  if [[ ! -f ./$yum_utils_rpm ]]; then
    (( ! _DRYRUN )) && wget http://mirror.centos.org/centos/$target_version/os/$arch/Packages/$yum_utils_rpm||true
  fi
  [[ ! -f ./$yum_utils_rpm ]] && die "could not download $yum_utils_rpm"||print "$yum_utils_rpm downloaded"
#
} #download_centos_rpm
###
function remove_rhel_packages { #@ USAGE: 
	(( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
  (( _DEBUG )) && print "removing RHEL packages"
  (( ! _DRYRUN )) && yum -y remove rhnlib abrt-plugin-bugzilla redhat-release-notes* || print "removing rhnlib abrt-plugin-bugzilla redhat-release-notes"
  (( ! _DRYRUN )) && rpm -e --nodeps redhat-release-server-6Server redhat-indexhtml  || print "removing redhat-release-server-6Server redhat-indexhtml"
  (( ! _DRYRUN )) && yum -y remove Red_Hat_Enterprise_Linux-Release_Notes-6-en-US.noarch||true
} #remove_rhel_packages
###
function remove_subscription_manager { #@ USAGE: 
	(( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
  (( _DEBUG )) && print "removing any left over RHEL subscription information and the subscription-manager"
  if type subscription-manager; then
  (( ! _DRYRUN )) && subscription-manager clean||true
  (( ! _DRYRUN )) && yum -y remove subscription-manager||true
  fi
  [[ -f /etc/pki/product/69.pem ]] && print "found certificate of the Red Hat Enterprise Linux system"||true
  [[ -f /etc/pki/product/70.pem ]] && print "found certificate of the RHEL Extended Update Support"||true
  [[ -f /etc/pki/product/150.pem ]] && print "found certificate of the Red Hat Enterprise Virtualization"||true
  [[ -f /etc/pki/product/201.pem ]] && print "found certificate of the  Red Hat Software Collections"||true
} #remove_subscription_manager
###
function install_centos_rpm { #@ USAGE: 
	(( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
  (( _DEBUG )) && print "installing the CentOS RPMs"||true
  (( ! _DRYRUN )) && rpm -Uvh --force *.rpm ||true
} #install_centos_rpm
###
function upgrade_packages { #@ USAGE: 
	(( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
  (( _DEBUG )) && print "cleaning up yum cached data and then upgrade"
  (( ! _DRYRUN )) && yum clean all ||true
  (( ! _DRYRUN )) && yum -y update glibc\* python\* rpm\* yum\* ||true
  (( ! _DRYRUN )) && yum -y update ||true
} #upgrade_packages
###
function remove_centos_rpm { #@ USAGE: 
	(( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
  (( _DEBUG )) && print "removing the downloaded rpm files"
  (( ! _DRYRUN )) && rm -f ./*.rpm ||true
  (( ! _DRYRUN )) && rm -f ./$centos_key ||true
} #remove_centos_rpm
###
function disable_other_repos { #@ USAGE:
	(( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
  (( _DEBUG )) && print "disabling the other yum repos"
  if (( ! _DRYRUN ));then
    local repo
    for repo in /etc/yum.repos.d/*; do
      [[ ${repo##*/} =~ ^CentOS ]] && continue||true
      if [[ -f $repo ]];then
      	sed -i -e 's/enabled=1/enabled=0/g' $repo
      fi
    done
  fi
} #disable_other_repos
#
function convert_rhel_to_centos { #@ USAGE: 
	(( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
  (( _DEBUG )) && print "converting to CentOS"
  pushd ${WORKSPACE} >/dev/null

  extend_part

  print "cleaning up the yum cache"
  (( ! _DRYRUN )) && yum clean all --enablerepo='*' ||print "cleaning yum cache"

  download_centos_rpm

  print "importing the GPG key \"$centos_key\""
  if ! rpm --import "$centos_key"
  then die "couldn\'t import key file $centos_key"
  fi

  remove_rhel_packages

  remove_subscription_manager

  install_centos_rpm

  upgrade_packages

  (( _REMOVE_DOWNLOADED_FILES )) && remove_centos_rpm||true

  disable_other_repos

  print "List of enabled repos:"
  yum repolist enabled
  print "finished at $(lsb_release -a)"

  popd>/dev/null
  print "please, reboot the server $(hostname)"
} #convert_rhel_to_centos
### function main #############################################################
function main {
  (( _DEBUG )) && echo "[DEBUG] enter $FUNCNAME"
  initialize
  #checkPreconditions "$CMD"
  case $CMD in
  CONVERT|convert) convert_rhel_to_centos ;;
  *) die "unknown command \"$CMD\" ";;
  esac
} #main

### call main #################################################################
(( $# < 1 )) && die "$(basename $0) needs a command to proceed"
declare CMD="$1" ;shift
set -- "$@"
declare distibution release arch
main "$@"
exit $exitcode