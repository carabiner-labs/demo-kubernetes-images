#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Carabiner Systems, Inc
# SPDX-License-Identifier: Apache-2.0
#
# Verify a Kubernetes image with AMPEL and the policy set in
# policies/kubernetes-image.policyset.json, which checks the four pieces of
# security material the image carries:
#
#   a) the tag signature made by the image promoter,
#   b) the SLSA verification summary (its verifier and the levels verified),
#   c) the promotion record, and
#   d) the origin signature made by the staging pipeline.
#
# AMPEL gathers them from the registry with two collectors: `oci` reads the
# sigstore bundles attached as OCI referrers and `coci` the classic cosign
# tag signature. Each policy pins the identity that has to have signed its
# attestation, so a signature by anyone else fails the policy outright.
#
# The ampel binary is taken from $AMPEL, then the PATH, then built on the
# fly from its module.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/demo-lib.sh"

IMAGE="${1:-registry.k8s.io/security-profiles-operator/security-profiles-operator:v1.1.1}"
AMPEL_VERSION="${AMPEL_VERSION:-latest}"
FORMAT="${FORMAT:-tty}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_SET="$HERE/policies/kubernetes-image.policyset.json"

if [[ -n "${AMPEL:-}" ]]; then
  AMPEL_CMD=("$AMPEL")
elif command -v ampel >/dev/null; then
  AMPEL_CMD=(ampel)
else
  AMPEL_CMD=(go run "github.com/policylabs/ampel/cmd/ampel@${AMPEL_VERSION}")
fi

step "Verifying $IMAGE with AMPEL" \
  "One policy set, four policies: tag signature, verification summary, promotion record, origin signature."

step "1. Resolving the image to its digest" \
  "The digest is the subject the policies are evaluated for."
DIGEST="$(run crane digest "$IMAGE")"
REPO="${IMAGE%%@*}"; REPO="${REPO%%:*}"
echo "    $REPO@$DIGEST"

step "2. Evaluating $(basename "$POLICY_SET")" \
  "The oci collector reads the bundles attached as referrers, coci the classic tag signature." \
  "Each policy pins the sigstore identity its attestation must be signed by."
run "${AMPEL_CMD[@]}" verify \
  --subject "$DIGEST" \
  --collector "oci:$IMAGE" \
  --collector "coci:$IMAGE" \
  --policy "$POLICY_SET" \
  --context "image:$REPO" \
  --format "$FORMAT"

ok "Policy set passed for $IMAGE"
