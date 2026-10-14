#!/usr/bin/env bash
# Breaks the whole local cluster in one of three ways. Affects every namespace.
#   scripts/break-cluster.sh [1-3|random|reveal|reset]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CTX=k3d-lab
STATE="$ROOT/.break-cluster-state"
COUNT=3
NAMES=(""
  "A worker node is down"
  "A node drain is blocked by a PodDisruptionBudget"
  "Cluster DNS is down")
kc() { kubectl --context "$CTX" "$@"; }

reset() {
  docker start $(docker ps -aq --filter name=k3d-lab-agent) >/dev/null
  kc wait --for=condition=Ready nodes --all --timeout=120s >/dev/null
  for node in $(kc get nodes -o name); do kc uncordon "$node" >/dev/null; done
  kc -n kube-system scale deploy coredns --replicas=1 >/dev/null
  kc -n sample scale deploy sample-service --replicas=2 >/dev/null
  rm -f "$STATE"
  echo "Reset complete."
}

case "${1:-random}" in
  reveal) cat "$STATE" 2>/dev/null || echo "Nothing is broken."; exit 0 ;;
  reset) reset; exit 0 ;;
  random) n=$(( RANDOM % COUNT + 1 )) ;;
  *) n=$1 ;;
esac
if ! [[ "$n" =~ ^[0-9]+$ ]] || (( n < 1 || n > COUNT )); then
  echo "usage: $0 [1-$COUNT|random|reveal|reset]"
  exit 1
fi
if [ -f "$STATE" ]; then
  echo "A cluster break is already active. Fix it, then run: $0 reset"
  exit 1
fi

case $n in
  1) docker stop k3d-lab-agent-1 >/dev/null ;;
  2) kc -n sample scale deploy sample-service --replicas=1 >/dev/null
     kc -n sample rollout status deploy sample-service --timeout=60s >/dev/null
     node=$(kc -n sample get pods -l app=sample-service -o jsonpath='{.items[0].spec.nodeName}')
     kc drain "$node" --ignore-daemonsets --delete-emptydir-data --timeout=30s || true ;;
  3) kc -n kube-system scale deploy coredns --replicas=0 >/dev/null ;;
esac

echo "$n. ${NAMES[$n]}" > "$STATE"
echo "Something in the cluster is broken. Find it with the symptom table."
echo "Stuck? Run: $0 reveal"
