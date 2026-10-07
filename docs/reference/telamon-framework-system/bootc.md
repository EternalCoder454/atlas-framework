---
title: bootc
summary: Typed views of bootc status --json for Telamon OS (booted, staged and rollback images, the update channel and available updates) and the channel tag rewrite.
order: 30
---

The `bootc` module has types for the output of `bootc status --json` (bootc 1.16, API `org.containers.bootc/v1`) and the helpers that decide what is booted, staged, available and which channel the system follows.

Every field is lenient: unknown fields are ignored and optional ones default, so a newer bootc does not break the parser. The module does not run `bootc`; the caller (the root helper) does and passes the JSON in.

## Example

```rust
use telamon_framework_system::bootc::{Channel, Status};

let json = std::fs::read_to_string("status.json")?; // the output of `bootc status --json`
let status = Status::from_json(&json)?;
if let Some(booted) = status.status.booted.as_ref() {
    println!("booted {}", booted.version().unwrap_or("unknown"));
}
if status.update_available() {
    println!("an update is available");
}
let next = status.booted_ref().map(|r| r.with_channel("testing"));
assert_eq!("stable".parse::<Channel>().unwrap(), Channel::Stable);
```

## Status

`#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)] #[serde(rename_all = "camelCase")] pub struct Status`

| Field | Type | Description |
|---|---|---|
| `api_version` | `String` | `apiVersion` |
| `kind` | `String` | |
| `spec` | `Spec` | The desired state |
| `status` | `HostStatus` | The observed state |
| `image_ref_heads` | `Vec<String>` | Not in bootc's JSON (`serde(skip)`): the caller fills it from [`image_ref_heads`](#functions-and-constants). Without it `latest_image` falls back to the booted entry |
| `bad_image_digests` | `Vec<String>` | Not in bootc's JSON: the caller fills it from [`bad_image_digests`](#functions-and-constants) |

| Method | Description |
|---|---|
| `fn from_json(json: &str) -> Result<Status, serde_json::Error>` | Parses the document |
| `fn booted_ref(&self) -> Option<&ImageReference>` | The booted image's reference; falls back to `spec.image` |
| `fn channel(&self) -> Option<Channel>` | The channel the system follows, from `spec.image` (a switch changes it at once, while the booted ref keeps the old channel until the restart) |
| `fn has_staged(&self) -> bool` | A staged deployment exists |
| `fn latest_image(&self) -> Option<&ImageStatus>` | The newest image of the tracked reference this system knows of: the `cachedUpdate` of the entry holding the image ref's commit, or that entry's own image when it has none. Without ref heads, or when no entry holds the commit, the booted entry's `cachedUpdate` |
| `fn available_update(&self) -> Option<&ImageStatus>` | `latest_image` when it is neither the booted nor the staged image: an update found by `upgrade --check` that is not staged yet. An image older than the booted or staged one, or one with no digest, is not an update |
| `fn update_available(&self) -> bool` | `available_update()` has one |
| `fn is_downgrade(&self, candidate: &ImageStatus) -> bool` | `candidate` is older than the booted or staged image of the same reference (a tag moved back to an older build). Such an image is never offered or staged; Go Back and a channel switch are the ways to an older build |
| `fn is_bad_image(&self, digest: &str) -> bool` | `digest` failed its boot health checks on this machine |

## Deployment types

All derive `Debug, Clone, PartialEq, Serialize, Deserialize, Default` with camelCase JSON names.

| Type | Fields |
|---|---|
| `Spec` | `image: Option<ImageReference>` (the image the host tracks), `boot_order: Option<String>` |
| `HostStatus` | `staged`, `booted`, `rollback`: `Option<BootEntry>`; `rollback_queued: bool`; `host_type: Option<String>` (JSON `type`: `bootcHost` on a bootc system, null on a plain container) |
| `BootEntry` | `image: Option<ImageStatus>` (null for a deployment that is not a container image), `cached_update: Option<ImageStatus>` (an update bootc found with `upgrade --check` but has not downloaded), `incompatible: bool`, `pinned: bool`, `store: Option<String>`, `ostree: Option<OstreeEntry>` |
| `OstreeEntry` | `checksum: String`, `deploy_serial: u32`, `stateroot: String` |
| `ImageStatus` | `image: ImageReference` (missing reads as empty), `architecture: Option<String>`, `version: Option<String>`, `timestamp: Option<String>` (build time, RFC 3339), `image_digest: String` |
| `ImageReference` | `image: String` (name with tag, such as `ghcr.io/eternalcoder454/atlasos:stable`), `transport: Option<String>` (`registry`, `oci`, `containers-storage`, ...; missing means `registry`), `signature: Option<serde_json::Value>` |

Methods on these:

| Method | Description |
|---|---|
| `BootEntry::version(&self) -> Option<&str>` | The image version label (`org.opencontainers.image.version`) |
| `BootEntry::timestamp(&self) -> Option<&str>` | The image build time, RFC 3339 |
| `BootEntry::digest(&self) -> Option<&str>` | The image digest |
| `ImageStatus::is_older_than(&self, other: &ImageStatus) -> bool` | Built before `other`: the version labels (when both are numeric, such as `44.20261008-2`) and the build times (RFC 3339 UTC to the second) are compared, and one must say so with neither saying the opposite. Images that cannot be compared are not held back |
| `ImageReference::same_image(&self, other: &ImageReference) -> bool` | Same image and transport (the signature policy is not compared) |
| `ImageReference::transport_or_default(&self) -> &str` | The transport, `registry` when not given |
| `ImageReference::tag(&self) -> Option<&str>` | The tag of `image`. A port in the host (`host:5000/img`) and a `@digest` are not tags |
| `ImageReference::channel(&self) -> Option<Channel>` | The channel in the tag, if it is `stable` or `testing` |
| `ImageReference::with_channel(&self, channel: &str) -> Result<ImageReference, RefError>` | The same reference with only the tag replaced by `channel`. Transport and name stay; a digest is dropped, since it would pin the old image. Errors with `RefError` for a bad channel, a transport outside `TRANSPORTS`, or an unusable name |

## Channel and errors

| Item | Description |
|---|---|
| `enum Channel { Stable, Testing }` | An update channel. Only these two exist. `Copy`. `as_str()` gives `stable` or `testing`; implements `Display` and `FromStr` (exactly `stable` or `testing`, else `RefError::BadChannel`) |
| `enum RefError { BadChannel(String), BadImage(String), BadTransport(String) }` | Why a reference or channel was refused. Implements `Display` and `std::error::Error` |

## Functions and constants

| Name | Signature or value | Description |
|---|---|---|
| `IMAGE_REFS_DIR` | `"/ostree/repo/refs/heads/ostree/container/image"` | Where ostree-ext keeps one ref per container image reference. Readable without root |
| `image_ref_heads` | `pub fn image_ref_heads(dir: &Path) -> Vec<String>` | The commit checksums of the image refs under `dir`. Empty when they cannot be read |
| `BAD_IMAGE_DIGESTS` | `"/var/lib/atlasos/bad-image-digests"` | Digests of images that failed their boot health checks and were rolled back by greenboot, one per line, newest last (at most 20). Readable without root |
| `bad_image_digests` | `pub fn bad_image_digests(path: &Path) -> Vec<String>` | The digests in such a file. Empty when it cannot be read |
| `TRANSPORTS` | `&[&str]` | Transports a switch may use: `registry`, `oci`, `oci-archive`, `containers-storage`, `docker-daemon` |
| `CONTAINERS_POLICY` | `"/etc/containers/policy.json"` | The system's containers policy |
| `policy_requires_signature` | `pub fn policy_requires_signature(policy: &serde_json::Value, image: &str) -> bool` | True when the parsed containers `policy` demands a signature (`signedBy` or `sigstoreSigned`) for the registry image `image` under the most specific matching scope, and its `default` does not accept anything |
| `version_cmp` | `pub fn version_cmp(a: &str, b: &str) -> Option<std::cmp::Ordering>` | Compares numeric versions such as `44.20261008` or `44.20261008-2`; `None` if either has a non-numeric part |
| `utc_second` | `pub fn utc_second(t: &str) -> Option<&str>` | An RFC 3339 time in UTC to the second (`2026-10-02T18:54:39`), which orders as text; `None` for any other form |
