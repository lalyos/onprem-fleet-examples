#!/bin/bash

debug() {
    if ((DEBUG)); then
       echo "===> [${FUNCNAME[1]}] $*" 1>&2
    fi
}

get-kctl() {
    declare hostname=$1
    : ${hostname:? required}

    ssh -l ubuntu \
      ${hostname} -- \
      "sudo sh -c 'cat /etc/rancher/k3s/k3s.yaml || cat /etc/rancher/rke2/rke2.yaml'" \
      | sed 's/certificate-authority-data:.*/insecure-skip-tls-verify: true/' \
      | sed "s/127.0.0.1/${hostname}/" \
      | sed "s/default/${hostname%%.*}/g"
}


distribute() {
  for h in alpha beta gamma; do
    debug distribute to: $h
    scp -o User=ubuntu .tokens $h.k3z.eu:/tmp/ &
    scp -o User=ubuntu hack.sh $h.k3z.eu:/tmp/ &
  done
}

litestream-replicate() {
  command litestream version 2> /dev/null || curl -sL https://github.com/benbjohnson/litestream/releases/download/v0.3.6/litestream-v0.3.6-linux-amd64.tar.gz|tar -xzC  /usr/local/bin
  debug replication starting
  litestream replicate -trace litestream.log  /var/lib/rancher/k3s/server/db/state.db s3://rancher-backups-lly/onprem
}

litestream-restore() {
  command litestream version 2> /dev/null || curl -sL https://github.com/benbjohnson/litestream/releases/download/v0.3.6/litestream-v0.3.6-linux-amd64.tar.gz|tar -xzC  /usr/local/bin
  debug restore ${DBDIR:=/var/lib/rancher/k3s/server/db}
  rm -rf ${DBDIR}/state.db; litestream restore -v -o ${DBDIR}state.db  s3://rancher-backups-lly/$HOSTNAME
}

alpine() {
  kubectl get clusterrolebinding x &>/dev/null || kubectl create clusterrolebinding x \
    --clusterrole cluster-admin \
    --serviceaccount default:default

  kubectl delete po x --force &> /dev/null

  kubectl run -i --tty --rm x --image alpine -- \
    sh -c 'apk add --no-cache -X http://dl-cdn.alpinelinux.org/alpine/edge/testing helm kubectl k9s bash bash-completion; kubectl completion bash |sed "/complete -o default -F/ a \    complete -o default -F __start_kubectl k" >/.k; echo -e alias k=kubectl\\n. /usr/share/bash-completion/bash_completion\\n. /.k\\n>~/.bashrc ;bash'
}

main() {
  # if last arg is -d sets DEBUG
  [[ ${@:$#} =~ -d ]] && { set -- "${@:1:$(($#-1))}" ; DEBUG=1 ; } || :

  if [[ $1 =~ :: ]]; then
    debug DIRECT-COMMAND  ...
    command=${1#::}
    shift
    $command "$@"
  else
    debug default-command
    #get-kctl "$@"
    echo ok
  fi
}

alias r=". $BASH_SOURCE"
[[ "$0" == "$BASH_SOURCE" ]] && main "$@" || true
