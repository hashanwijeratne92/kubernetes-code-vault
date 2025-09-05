#!/usr/bin/env bash

# -------------------------configurations --------------------------------------------------- #
# --- (NS - namespace, SA - Service Account, PA - ProjectAdmin, AD - AppDev, AU - Auditor) -- #
# ------------------------------------------------------------------------------------------- # 

PA_NS="kube-system"
PA_SA="sa-platformadmin"
AD_NS="team-a"
AD_SA="sa-appdev"
AU_NS="default"
AU_SA="sa-auditor"
TEST_NS="team-c"
APP_URL="../app/nginx.yaml"

# -------------------------------------- Counters ------------------------------------------- #

PASS=0
FAIL=0

SAY() { printf "\n\n=== %s ===\n\n" "$*"; }
ok()  { printf "PASS %s\n" "$*"; PASS=$((PASS+1)); }
no()  { printf "FAIL %s\n" "$*"; FAIL=$((FAIL+1)); }

# -------------------------------------- Subjects ------------------------------------------- #

SUBJ_PA=(--as=system:serviceaccount:${PA_NS}:${PA_SA})
SUBJ_AD=(--as=system:serviceaccount:${AD_NS}:${AD_SA})
SUBJ_AU=(--as=system:serviceaccount:${AU_NS}:${AU_SA})

# -------------------------------------- check RBAC permission ------------------------------ #

can_i (){
	local expect="$1"; shift
	local desc="$1"; shift
	local out
	out=$(sudo kubectl auth can-i "$@" 2>/dev/null)
	[ "$out" = "$expect" ] && ok "$desc" || { echo " --> got: "$out"; no "$desc""; }
}

# -------------------------------------- run command - succeed ------------------------------ #

cmd_ok (){
	local desc="$1"; shift
	if "$@" ; then ok "$desc"; else no "$desc"; fi
}

# -------------------------------------- run command - fail --------------------------------- #

cmd_fail (){
	local desc="$1"; shift
	if "$@" ; then no "$desc"; else ok "$desc"; fi
}

# -------------------------------------- PlatformAdmin -------------------------------------- #

SAY "PlatformAdmin: can manage cluster, but cannot read secrets"
can_i yes "PA can create namespace"             create namespace "${SUBJ_PA[@]}"
cmd_ok    "PA creates namespace ${TEST_NS}"     sudo kubectl create ns "${TEST_NS}" "${SUBJ_PA[@]}"
cmd_ok    "PA deletes namespace ${TEST_NS}"     sudo kubectl delete ns "${TEST_NS}" --wait=false "${SUBJ_PA[@]}"
can_i no  "PA cannot read any secrets"          get secrets -A "${SUBJ_PA[@]}"

# -------------------------------------- AppDev --------------------------------------------- #

SAY "AppDev: can modify Deployments in team-a, but cannot access secrets or resources in
other namespaces."

#deploy nginx 
if sudo kubectl apply -n "${AD_NS}" -f "${APP_URL}" "${SUBJ_AD[@]}" >/dev/null 2>&1; then
	ok "AD deployed nginx in ${AD_NS}"
else
	#check deployment again, may be it is failed due to any other issue except rbac
	if sudo kubectl create deployment rbac-verify --image=nginx -n "${AD_NS}" "${SUBJ_AD[@]}">/dev/null 2>&1; then
		ok "AD created fallback nginx Deplyment in ${AD_NS}"
	else
		no "AD failed to create fallback deployment in ${AD_NS}"
	fi
fi

can_i yes "AD can patch deplyment in ${AD_NS}"       patch deployments.app -n "${AD_NS}" "${SUBJ_AD[@]}"
can_i no  "AD cannot read secrets in ${AD_NS}"       get secrets -n "${AD_NS}" "${SUBJ_AD[@]}"
can_i no  "AD cannot create deployments in default"  create deployments.app -n default "${SUBJ_AD[@]}"
can_i no  "AD cannot get pods in default"            get pods -n default "${SUBJ_AD[@]}"

# -------------------------------------- Auditor -------------------------------------------- #

SAY "Auditor: can list Pods accross all namespaces, but cannot create or delete resources"

can_i yes "AU can get pods across all namespaces"    get pods -A "${SUBJ_AU[@]}"
can_i no  "AU cannot create pods in default"         create pods -n default "${SUBJ_AU[@]}"
can_i no  "AU cannot delete services in ${AD_NS}"    delete services -n "${AD_NS}" "${SUBJ_AU[@]}"
can_i no  "AU cannot create pods/exec in ${AD_NS}"   create pods/exec -n "${AD_NS}" "${SUBJ_AU[@]}"

# -------------------------------------- Summary -------------------------------------------- #

SAY "Summary"
printf "Passed: %d  Failed: %d\n" "$PASS" "$FAIL"
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)


