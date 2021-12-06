#!/usr/bin/env bash
#
# Run with `--help` for directions.
#

SCRIPTNAME="$(basename "$0")"
SCRIPTDIR="$(dirname "$0")"

# ==============================================================================
# ===  Settings
# ==============================================================================

#
# Local
#
:             ${Title:="DAQ VNC connection terminal"}
:         ${LocalPort:='8443'}
: ${DefaultWebBrowser:='vivaldi'}
:           ${PIDfile:="/var/run/user/${UID}/${SCRIPTNAME%.sh}.pid"}
:         ${LocalHost:="localhost"}

#
# Remote server
#
:      ${RemoteServer:='icarus-evb01.fnal.gov'}
:        ${RemotePort:='443'}

#
# Gateway
#
:           ${Gateway:='icarus-gateway01.fnal.gov'}
:       ${GatewayUser:='icarus'}


# ==============================================================================

function isFlagSet() { local VarName="$1" ; [[ -n "${!VarName//0}" ]] ; }

function FindConfig() {
  local -r ConfigName="$1"
  
  local CandidateDir
  for CandidateDir in "$(pwd)" "$SCRIPTDIR" ; do
    local Candidate="${CandidateDir:+"${CandidateDir%/}/"}${ConfigName}"
    [[ -e "$Candidate" ]] || continue
    echo "$Candidate"
    return 0
  done
  return 1
} # FindConfig()


function NOpenProcesses() {
  local -r PIDfile="$1"
  [[ -r "$PIDfile" ]] || return 1
  grep -cv -E '^[[:blank:]]*(#|$)' "$PIDfile"
  return 0
} # NOpenProcesses()


function PrintHelp() {
  
  local NProcesses
  NProcesses="$(NOpenProcesses "$PIDfile")"
  [[ $? == 0 ]] || NProcesses='none'
  
  cat <<EOH
Opens a connection for: ${Title}.
It also starts a web browser pointing to the local side of the connection.

Usage:  ${SCRIPTNAME}  [options]  ConfigurationFile

Parameters:
  Remote server:   ${RemoteServer} port ${RemotePort}
  Local server:    ${LocalHost} port ${LocalPort}
  Gateway:         ${Gateway} (user: ${GatewayUser})

Options:
--browser=BROSWERNAME ['${DefaultWebBrowser}']
    uses BROWSERNAME as web browser; it can be the full path to the browser
    executable or just the name of the application (if the OS can use it)
--closefirst , -c
    closes all the processes previously open, as listed in '$PIDfile'
    (currently ${NProcesses}), before opening a new one
--closeall , -C
    closes all the processes previously open, as listed in '$PIDfile'
    (currently ${NProcesses}) and exits
--list , -l
    just lists the tracked processes that would be closed with \`--closeall\`
--help , -h , -?
    prints this help message

EOH
} # PrintHelp()


function listAllProcesses() {
  
  local -r PIDfile="$1"

  local NProcesses
  NProcesses="$(NOpenProcesses "$PIDfile")"
  if [[ $? != 0 ]] || [[ "$NProcesses" == 0 ]]; then
    echo "No tunnel processes are currently tracked in '${PIDfile}'."
    return 0
  fi
  
  echo "The following ${NProcesses} tunnel processes are currently tracked in '${PIDfile}':"
  # another useful option: "u"
  local PID
  while read PID ; do ps --no-header "$PID" 2> /dev/null || echo "Process ID=${PID} not avaialble." ; done < "$PIDfile" | cat -n

} # listAllProcesses()


function closeAllProcesses() {
  
  local -r PIDfile="$1"
  
  local NProcesses
  NProcesses="$(NOpenProcesses "$PIDfile")"
  if [[ $? != 0 ]] || [[ "$NProcesses" == 0 ]]; then
    echo "No tunnel processes are currently tracked in '${PIDfile}'."
    return 0
  fi
  
  listAllProcesses "$PIDfile"
  echo "Now we close them."
  local PID
  while read PID ; do [[ "$PID" == 0 ]] && continue ; kill -HUP "$PID" ; done < "$PIDfile" || exit $?
  rm -f "$PIDfile"
  
} # closeAllProcesses()


function openTunnel() {
  #
  # SSH options:
  # 
  # -f   go into background
  # -N   don't execute any command in the remote host (forwarding ports is enough)
  # -K   enable GSSAPI (Kerberos) authentication
  # -L   the forwarding
  #
  #
  local -a Cmd=( ssh -fNK -L "${LocalHost}:${LocalPort}:${RemoteServer}:${RemotePort}" "${GatewayUser}@${Gateway}" )
  
  echo "CMD> ${Cmd[@]}"
  "${Cmd[@]}"
  
  local -i PID
  PID="$(pgrep --uid "$USER" --full -- "${Cmd[*]}" | sort -u)"
  
  if [[ $? != 0 ]]; then
    echo "Failed to find the process ID of the connection just spawned."
  else
    
    echo "$PID" >> "$PIDfile"
    local -i Code="$?"
    if [[ "$Code" == 0 ]]; then
      cat <<EOM

  Process ID of the connection (PID=${PID}) stored in '${PIDfile}'.
  To close all the processes listed in there ($(NOpenProcesses "$PIDfile") as of now), run \`${SCRIPTNAME} --closeall\`.

EOM
    else
      cat <<EOM >& 2

Error while recording the process just opened (PID=${PID}) into '${PIDfile}'.
To stop that process, you'll have to manually run:

kill -HUP ${PID}

EOM
    
    fi
  fi
  
} # openTunnel()

# ==============================================================================
# ===  script starts here
# ==============================================================================

#
# parameter parsing
#
declare ExitCode
declare -i CloseProcesses=0 OpenProcesses=1 ListProcesses=0
declare WebBrowserName="$DefaultWebBrowser"
declare -i NoMoreOptions=0
declare -a Arguments
for (( iParam = 1 ; $iParam <= $# ; ++iParam )); do
  Param="${!iParam}"
  if isFlagSet NoMoreOptions || [[ "${Param:0:1}" != '-' ]]; then
    Arguments+=( "$Param" )
  else
    case "$Param" in
      ( '-noweb' | '--noweb' )   WebBrowserName='' ;;
      ( '--browser='* )          WebBrowserName="${Param#--*=}" ;;
      ( '--closefirst' | '-c' )  CloseProcesses=1 ; OpenProcesses=1 ;;
      ( '--closeall' | '-C' )    CloseProcesses=1 ; OpenProcesses=0 ;;
      ( '--list' | '-l' )        CloseProcesses=0 ; OpenProcesses=0 ; ListProcesses=1 ;;
      ( '--help' | '-h' | '-?' ) DoHelp=1 ;;
      ( * )
        echo "Option #${iParam} not supported ('${Param}')." >&2
        ExitCode=1
        ;;
    esac
  fi
done

case "${#Arguments[@]}" in
  ( 0 )
    if ! isFlagSet DoHelp ; then
      echo "FATAL: required argument is missing." >&2
      echo ""
      DoHelp=1
      ExitCode=1
    fi
    ;;
  ( 1 )
    ;;
  ( * )
    if ! isFlagSet DoHelp ; then
      echo "FATAL: too many arguments" >&2
      echo ""
      DoHelp=1
      ExitCode=1
    fi
    ;;
esac
ConfigurationFile="${Arguments[0]}"

ConfigurationFilePath="$(FindConfig "$ConfigurationFile")"
[[ -r "$ConfigurationFilePath" ]] && source "$ConfigurationFilePath"

isFlagSet DoHelp && ExitCode=0 && PrintHelp

[[ -n "$ExitCode" ]] && exit "$ExitCode"

if [[ ! -r "$ConfigurationFilePath" ]]; then
  echo "FATAL: configuration file '${ConfigurationFile}' not found."
  exit 1
fi

# ------------------------------------------------------------------------------
cat <<EOT
================================================================================

   ${Title}

================================================================================


EOT

if isFlagSet ListProcesses ; then

  listAllProcesses "$PIDfile"
  
fi

isFlagSet CloseProcesses && closeAllProcesses "$PIDfile"

if isFlagSet OpenProcesses ; then


  declare -r OSName="$(uname -s)"

  openTunnel
  res=$?


  cat <<EOM
A connection on ${LocalHost} port ${LocalPort} has been opened server '${RemoteServer}' port ${RemotePort}.

  "${LocalPort}:${RemoteServer}:${RemotePort}" "${GatewayUser}@${Gateway}"

EOM

  if [[ -n "$WebBrowser" ]] ; then
    cat <<EOM
You have passed the option to not open a web browswer.
Once the tunnel is made, you will have to open up a web browser and navigate to

  https://${LocalHost}:${LocalPort}

EOM
    exit $res
  fi

  declare -r LocalURL="https://${LocalHost}:${LocalPort}"

  # we have been asked to open the browser...
  echo "[${OSName}] Starting '${WebBrowserName}' on ${LocalURL}..."
  case "$OSName" in
    ( 'Darwin' )
      
      open -a "$WebBrowserName" "$LocalURL"
      
      ;;
    ( 'Linux' )
      
      "$WebBrowserName" "$LocalURL"
      
      ;;
    ( * )
      cat <<EOM

Unfortunately I don't know how to start ${Browser} in OS '${OSName}'.
The aforementioned connection is still open.

EOM
      ;;
  esac

fi

