# demo-kubernetes-images

Verifying the images Kubernetes publishes on `registry.k8s.io`, three ways.

Every promoted Kubernetes image carries four pieces of security material:

| What | Where | Signed by |
|---|---|---|
| Tag signature | classic cosign `.sig` tag | the image promoter (`krel-trust@k8s-releng-prod`) |
| SLSA verification summary (VSA) | OCI referrer, sigstore bundle | the promoter's summaries account (`promoter-summaries@k8s-releng-prod`) |
| Promotion record | OCI referrer, sigstore bundle | the image promoter |
| Origin signature | OCI referrer, sigstore bundle | the staging pipeline that built the image |

The scripts check `registry.k8s.io/security-profiles-operator/security-profiles-operator:v1.1.1`
by default; pass another image reference as the first argument. Each one
announces every step, says what it is about to check and prints the command
before running it (`demo-lib.sh`; colors go off with `NO_COLOR` or when the
output is not a terminal).

## 1. cosign

```sh
./verify-cosign.sh
```

Verifies the tag signature (old bundle format), then the promotion record,
the verification summary and the origin signature attached as referrers (new
bundle format), each against the identity expected to have signed it. Needs
`cosign` and `jq`.

## 2. SLSA verifier

```sh
./verify-slsa-verifier.sh
```

Finds the verification summary among the image's referrers, downloads the
bundle and runs `slsa-verifier vsa` on it: the summary must be signed by the
promoter's summaries account for the verifier `https://k8s.io/promo-tools/verifier/v1`,
name this image as its resource and record `SLSA_BUILD_LEVEL_3` and
`K8S_PROMOTION_MANIFEST_REVIEWED`. Needs `crane`, `oras`, `jq` and the
[verifier](https://github.com/slsa-framework/verifier) (`$SLSA_VERIFIER`, the
PATH, or `go run` of `$VERIFIER_VERSION`).

## 3. AMPEL

```sh
./verify-ampel.sh
```

Evaluates [`policies/kubernetes-image.policyset.json`](policies/kubernetes-image.policyset.json),
one policy per piece of material. AMPEL collects the referrers with its `oci`
collector and the tag signature with `coci`, and each policy pins the sigstore
identity its attestation must carry:

- `tag-signature`: a verified promoter signature on the image.
- `verification-summary`: issued by the expected verifier, `PASSED` at SLSA
  Build L3 with a reviewed promotion manifest, and about this image.
- `promotion-record`: names this image and digest, promoted from the staging
  registry by promo-tools in a postsubmit job from a `registry.k8s.io` manifest.
- `origin-signature`: a verified signature by the staging pipeline's account.

Needs `crane` and [ampel](https://github.com/carabiner-dev/ampel) (`$AMPEL`,
the PATH, or `go run` of `$AMPEL_VERSION`). `FORMAT` picks the output
(`tty`, `summary`, `attestation`, ...).

The `tag-signature` policy needs an ampel built with policylabs/signer newer
than v0.6.4: earlier releases refuse to verify a sigstore bundle that wraps a
message signature instead of a DSSE envelope, which is how the cosign tag
signature reaches the policy, and report "required attestations missing".
