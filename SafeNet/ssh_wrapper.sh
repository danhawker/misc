#!/bin/bash
[ -f ${HOME}/.ssh/agent.vars ] && . ${HOME}/.ssh/agent.vars
exec /usr/bin/ssh ${@}
