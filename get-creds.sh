#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154,SC2317,SC1091,SC2155
# ------------------------------------------------------------------------------
#  PURPOSE: Get cluster credentials for NON-creators. Access has already been
#           granted. Now, you simply need to retriev the credentials.
#           REF: https://repost.aws/knowledge-center/amazon-eks-cluster-access
# ------------------------------------------------------------------------------
#  PREREQS: a) The clusters need to be up, running and available to you.
#           b)
# ------------------------------------------------------------------------------
#  EXECUTE: ./get-creds.sh
# ------------------------------------------------------------------------------
#     TODO: 1)
# ------------------------------------------------------------------------------
#   AUTHOR: Todd E Thomas (todd-dsm@github)
# ------------------------------------------------------------------------------
set -x


###-----------------------------------------------------------------------------
### VARIABLES
###-----------------------------------------------------------------------------
# Terraform Stuff
myProject="$(terraform output -raw reproduction-project)"
myRegion="$(terraform output -raw reproduction-region)"
awsAcctNo="$(terraform output -raw reproduction-account)"
awsPart="$(terraform output -raw reproduction-part)"


# ENV Stuff
KUBECONFIG_DIR="${HOME}/.kube"
targetCluster="${myProject}"


###-----------------------------------------------------------------------------
### FUNCTIONS
###-----------------------------------------------------------------------------
function pMsg() {
    theMessage="$1"
    printf '%s\n' "$theMessage"
}

function pMsgS() {
    theMessage="$1"
    printf '\n%s\n\n' "$theMessage"
}

###---
### Select the new cluster
###---
function activateCluster() {
    source "${HOME}/.ktx"
    source "$HOME/.ktx-completion.sh"
    ktx "${targetCluster}.ktx"
    kubectl config get-contexts
}

# rename cloud-defaults, they're way too long
function renameCreds() {
    bsName="$1"
    niceName="$2"
    pMsg "Changing that obnoxious name..."
    kubectl config rename-context "$bsName" "$niceName"
    activateCluster
}

# grab the kubeconfig for the current cluster
function getKubeConfig() {
    eksRegion=$1
    eksCluster=$2
    aws eks update-kubeconfig --region "$eksRegion" --name "$eksCluster"
}


###-----------------------------------------------------------------------------
### MAIN PROGRAM
###-----------------------------------------------------------------------------
### list all clusters and create a kubectl file for the targetCluster
###---
#set -x
while IFS=$'\t' read -r junk foundCluster; do
    # verify a context of the same name isn't already configured
    [[ $foundCluster != "$targetCluster" ]] && continue
    export foundCluster="$foundCluster"
    ktxFile="${KUBECONFIG_DIR}/${foundCluster}.ktx"
    export KUBECONFIG="$ktxFile"
    if [[ -e "$ktxFile" ]]; then
        rm -f "$ktxFile"
        getKubeConfig "$myRegion" "$foundCluster"
    else
        getKubeConfig "$myRegion" "$foundCluster"
    fi
    # Change those obnoxious names
    renameCreds \
        "arn:${awsPart}:eks:${myRegion}:${awsAcctNo}:cluster/${foundCluster}" \
            "$foundCluster"
done < <(aws eks list-clusters --output text)
#set +x


###---
### Make the announcement
###---
if ! kubectl cluster-info; then
    pMsgS "uh-o, better see whats wrong"
else
    pMsgS "its Alive!"
fi


###---
### fin~
###---
exit 0
