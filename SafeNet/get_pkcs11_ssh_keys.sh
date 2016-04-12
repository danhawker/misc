#!/bin/bash

##################################################################
# Name:         get_pkcs11_ssh_keys.sh
# Author:       Lex van Roon <r3boot@r3blog.nl>
# Purpose:      Read ssh key from eToken Pro and import it in ssh-agent
# Bugs:         On every 3rd insert of the token, it does not get detected.
#               This is a limitation in pscsd, reinsert the eToken as a
#               workaround.
# Usage under Debian/Ubuntu:
# - Comment the line 'use-ssh-agent' in /etc/X11/Xsession.options
# - Add this script to your WM startup scripts and add a quickstart icon
# - Add '. ${HOME}/.ssh/agent.vars' to your .profile or .bashrc
# - Insert your eToken and restart your WM session
# - Enter your pin
# - Enjoy

## Sleep while gnome-keyring-prompt is running, and wait for 2 seconds to allow
## gnome-keyring to startup during login
sleep 2
while [ x"`ps ax | grep [g]nome-keyring-prompt | awk '{print $1}'`" != x"" ]; do
	sleep 1
done

## Sleep while gnome-screensaver is active
while [ "`gnome-screensaver-command -q | grep -c 'inactive'`" -ne 1 ]; do
	sleep 1
done

## Then, restart ssh-agent
AGENT_VARS="${HOME}/.ssh/agent.vars"
[ `ps ax | grep -c [s]sh-agent` -eq 1 ] && killall ssh-agent
eval `ssh-agent`
[ -f ${AGENT_VARS} ] && rm -f ${AGENT_VARS}
echo "export SSH_AGENT_PID=\"${SSH_AGENT_PID}\"" > ${AGENT_VARS}
echo "export SSH_AUTH_SOCK=\"${SSH_AUTH_SOCK}\"" >> ${AGENT_VARS}

## And finally, import all keys off the token
ssh-add -s /usr/lib/libeToken.so
