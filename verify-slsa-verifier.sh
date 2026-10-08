#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Carabiner Systems, Inc
# SPDX-License-Identifier: Apache-2.0
#
# Verify a Kubernetes image with the SLSA verifier.
#
# The image promoter attaches a SLSA Verification Summary Attestation (VSA)
# to every promoted image as an OCI referrer: a sigstore bundle whose
# statement says which verifier checked the image, against which policy,
# and which levels it reached. The verifier checks the bundle's signature
# against the expected signer and the summary's claims against what we
# demand of the image.
#
# The verifier binary is taken from $SLSA_VERIFIER, then the PATH, then
# built on the fly from its module.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/demo-lib.sh"

IMAGE="${1:-registry.k8s.io/security-profiles-operator/security-profiles-operator:v1.1.1}"
VERIFIER_VERSION="${VERIFIER_VERSION:-v0.1.0}"

# The verifier that issued the summary and the identity it signs with.
VERIFIER_ID="https://k8s.io/promo-tools/verifier/v1"
SUMMARIZER="sigstore::https://accounts.google.com::promoter-summaries@k8s-releng-prod.iam.gserviceaccount.com"

# What the summary has to say about the image.
LEVELS=(SLSA_BUILD_LEVEL_3 K8S_PROMOTION_MANIFEST_REVIEWED)

VSA_TYPE="https://slsa.dev/verification_summary/v1"

if [[ -n "${SLSA_VERIFIER:-}" ]]; then
  SLSA_VERIFIER_CMD=("$SLSA_VERIFIER")
elif command -v slsa-verifier >/dev/null; then
  SLSA_VERIFIER_CMD=(slsa-verifier)
else
  SLSA_VERIFIER_CMD=(go run "github.com/slsa-framework/verifier@${VERIFIER_VERSION}")
fi

step "Verifying $IMAGE with the SLSA verifier" \
  "The promoter attaches a verification summary (VSA) to every promoted image as an OCI referrer."

step "1. Resolving the image to its digest" \
  "The summary is about the manifest digest, not the tag."
DIGEST="$(run crane digest "$IMAGE")"
REPO="${IMAGE%%@*}"; REPO="${REPO%%:*}"
echo "    $REPO@$DIGEST"

step "2. Finding the verification summary among the image's referrers" \
  "The sigstore bundle is annotated with its predicate type, $VSA_TYPE."
VSA_MANIFEST="$(run oras discover --format json "$REPO@$DIGEST" \
  | jq -r --arg t "$VSA_TYPE" '.referrers[] | select(.annotations["dev.sigstore.bundle.predicateType"] == $t) | .digest' \
  | head -n1)"
[[ -n "$VSA_MANIFEST" ]] || fail "no $VSA_TYPE referrer attached to $REPO@$DIGEST"
echo "    referrer $VSA_MANIFEST"

step "3. Downloading the bundle" \
  "The referrer's single layer is the sigstore bundle."
LAYER="$(run oras manifest fetch "$REPO@$VSA_MANIFEST" | jq -r '.layers[0].digest')"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
run oras blob fetch "$REPO@$LAYER" --output "$WORK/vsa.sigstore.json"
echo "    bundle $LAYER"

step "4. Verifying the summary" \
  "Signed by the summaries account for verifier $VERIFIER_ID," \
  "about this image, and recording the levels ${LEVELS[*]}."
LEVEL_FLAGS=()
for level in "${LEVELS[@]}"; do LEVEL_FLAGS+=(--level "$level"); done
run "${SLSA_VERIFIER_CMD[@]}" vsa "$WORK/vsa.sigstore.json" \
  --subject "$DIGEST" \
  --resource "$REPO@$DIGEST" \
  --verifier "${VERIFIER_ID}=${SUMMARIZER}" \
  "${LEVEL_FLAGS[@]}"

ok "Verification summary accepted for $IMAGE"
