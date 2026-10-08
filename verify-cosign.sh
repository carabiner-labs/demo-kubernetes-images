#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Carabiner Systems, Inc
# SPDX-License-Identifier: Apache-2.0
#
# Verify a Kubernetes image with cosign.
#
# The image carries two kinds of sigstore material:
#
#   1. The classic tag signature (the "sha256-<digest>.sig" tag), made by
#      the image promoter when the image was promoted to registry.k8s.io.
#   2. Three sigstore bundles attached as OCI referrers: the promotion
#      record, the SLSA verification summary (VSA) and the signature the
#      staging pipeline made before promotion (the origin signature).
#
# cosign reads the tag signature with the old bundle format and the
# referrers with the new one, so the image is checked in two passes.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/demo-lib.sh"

IMAGE="${1:-registry.k8s.io/security-profiles-operator/security-profiles-operator:v1.1.1}"
ISSUER="https://accounts.google.com"

# Who signs what. The promoter and its summaries run in the k8s-releng-prod
# project; the origin signature comes from the staging project's account
# for the image.
PROMOTER="krel-trust@k8s-releng-prod.iam.gserviceaccount.com"
SUMMARIZER="promoter-summaries@k8s-releng-prod.iam.gserviceaccount.com"
ORIGIN_SIGNER="${ORIGIN_SIGNER:-sp-operator-sa@k8s-staging-images.iam.gserviceaccount.com}"

step "Verifying $IMAGE with cosign" \
  "The image has a classic tag signature and three sigstore bundles attached as OCI referrers."

step "1. Tag signature" \
  "The legacy .sig tag, in the old bundle format, must be signed by the image promoter."
run cosign verify --new-bundle-format=false \
  --certificate-oidc-issuer "$ISSUER" \
  --certificate-identity "$PROMOTER" \
  "$IMAGE" | jq -r '.[] | .critical.image["docker-manifest-digest"] as $d | "    signed digest: \($d)"'

step "2. Promotion record" \
  "An attestation attached as a referrer, signed by the promoter, saying where the image came from."
run cosign verify-attestation --new-bundle-format \
  --type https://k8s.io/promo-tools/promotion/v1 \
  --certificate-oidc-issuer "$ISSUER" \
  --certificate-identity "$PROMOTER" \
  "$IMAGE" | jq -r '.payload | @base64d | fromjson | .predicate
    | "    promoted \(.source.name)\n           to \(.destination.name)@\(.destination.digest.sha256)\n    by \(.builderId) in \(.job.name)"'

step "3. SLSA verification summary" \
  "The VSA the promoter's verifier issued, signed by the summaries account."
run cosign verify-attestation --new-bundle-format \
  --type https://slsa.dev/verification_summary/v1 \
  --certificate-oidc-issuer "$ISSUER" \
  --certificate-identity "$SUMMARIZER" \
  "$IMAGE" | jq -r '.payload | @base64d | fromjson | .predicate
    | "    verifier \(.verifier.id): \(.verificationResult) \(.verifiedLevels | join(", "))"'

step "4. Origin signature" \
  "The signature the staging pipeline made before promotion, also a referrer."
run cosign verify --new-bundle-format \
  --certificate-oidc-issuer "$ISSUER" \
  --certificate-identity "$ORIGIN_SIGNER" \
  "$IMAGE" | jq -r '.[] | .critical.image["docker-manifest-digest"] as $d | "    signed digest: \($d)"'

ok "All cosign checks passed for $IMAGE"
