#!/usr/bin/env bash
# Breaks sample-service in one of sixteen ways, without saying which.
#   scripts/break.sh          a random break
#   scripts/break.sh 12       break number 12
#   scripts/break.sh reveal   say which break is active
#   scripts/break.sh reset    undo any break
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CTX=k3d-lab NS=sample DEPLOY=sample-service
URL=http://sample.127.0.0.1.sslip.io
REG=k3d-lab-registry.localhost
STATE="$ROOT/.break-state"
COUNT=16
NAMES=(""
  "OOMKilled. The app used more memory than its limit"
  "CrashLoopBackOff. A bad PORT value in the ConfigMap"
  "ImagePullBackOff. The image tag does not exist"
  "Never ready. The readiness probe checks a path that returns 404"
  "Pending. A nodeSelector no node matches"
  "Quota rejection. More pods than the namespace quota allows"
  "Restarts. The liveness probe checks a path that returns 404"
  "CreateContainerConfigError. The pod references a ConfigMap that does not exist"
  "CreateContainerConfigError. The container asks to run as root under runAsNonRoot"
  "503 from Traefik. The Service selector matches no pods"
  "502 or 504 from Traefik. The Service targetPort is wrong"
  "Timeouts. The NetworkPolicy allowing Traefik was deleted"
  "404 from Traefik. The Ingress host has a typo"
  "Pending. Every node has a taint the pod does not tolerate"
  "Stuck rollout. The Deployment is paused"
  "ErrImagePull. The registry is down")
k() { kubectl --context "$CTX" -n "$NS" "$@"; }
jp() { k patch "$1" "$2" --type=json -p "$3" >/dev/null; }

reset() {
  docker start "$REG" >/dev/null 2>&1 || true
  kubectl --context "$CTX" taint nodes --all lab-drill- >/dev/null 2>&1 || true
  k rollout resume deploy "$DEPLOY" >/dev/null 2>&1 || true
  k apply -f "$ROOT/deploy/k8s/app.yaml" -f "$ROOT/deploy/k8s/network.yaml" -f "$ROOT/deploy/k8s/netpol.yaml" >/dev/null
  k replace -f "$ROOT/deploy/k8s/app.yaml" >/dev/null
  [ -f "$STATE.image" ] && k set image deploy "$DEPLOY" app="$(cat "$STATE.image")" >/dev/null
  k set env deploy "$DEPLOY" DEBUG_ENDPOINTS=true >/dev/null
  if ! k rollout status deploy "$DEPLOY" --timeout=120s; then
    echo "Rollout did not finish. Pods and recent events:"
    k get pods
    k get events --sort-by=.lastTimestamp | tail -10
    exit 1
  fi
  rm -f "$STATE" "$STATE.image"
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
  echo "A break is already active. Fix it, then run: $0 reset"
  exit 1
fi
k get deploy "$DEPLOY" -o jsonpath='{.spec.template.spec.containers[0].image}' > "$STATE.image"

case $n in
  1) curl -s "$URL/debug/alloc?mb=80" >/dev/null || true ;;
  2) k patch configmap "$DEPLOY" -p '{"data":{"PORT":"abc"}}' >/dev/null
     k rollout restart deploy "$DEPLOY" >/dev/null ;;
  3) k set image deploy "$DEPLOY" app="$REG:5003/sample-service:doesnotexist" >/dev/null ;;
  4) jp deploy "$DEPLOY" '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/nope"}]' ;;
  5) k patch deploy "$DEPLOY" -p '{"spec":{"template":{"spec":{"nodeSelector":{"disktype":"ssd"}}}}}' >/dev/null ;;
  6) k scale deploy "$DEPLOY" --replicas=30 >/dev/null ;;
  7) jp deploy "$DEPLOY" '[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/path","value":"/nope"}]' ;;
  8) jp deploy "$DEPLOY" '[{"op":"add","path":"/spec/template/spec/containers/0/envFrom/-","value":{"configMapRef":{"name":"sample-service-extra"}}}]' ;;
  9) jp deploy "$DEPLOY" '[{"op":"add","path":"/spec/template/spec/containers/0/securityContext/runAsUser","value":0}]' ;;
  10) k patch svc "$DEPLOY" -p '{"spec":{"selector":{"app":"sample-svc"}}}' >/dev/null ;;
  11) jp svc "$DEPLOY" '[{"op":"replace","path":"/spec/ports/0/targetPort","value":9090}]' ;;
  12) k delete networkpolicy allow-from-traefik >/dev/null ;;
  13) jp ingress "$DEPLOY" '[{"op":"replace","path":"/spec/rules/0/host","value":"sampel.127.0.0.1.sslip.io"}]' ;;
  14) kubectl --context "$CTX" taint nodes --all lab-drill=true:NoSchedule >/dev/null
      k rollout restart deploy "$DEPLOY" >/dev/null ;;
  15) k rollout pause deploy "$DEPLOY" >/dev/null
      k set env deploy "$DEPLOY" DRILL=1 >/dev/null ;;
  16) docker stop "$REG" >/dev/null
      k set image deploy "$DEPLOY" app="$REG:5003/sample-service:drill" >/dev/null ;;
esac

echo "$n. ${NAMES[$n]}" > "$STATE"
echo "Something is broken. Find it with the symptom table."
echo "Stuck? Run: $0 reveal"
