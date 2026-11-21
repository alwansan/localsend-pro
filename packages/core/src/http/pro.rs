use serde::{Deserialize, Serialize};

/// Additive, read-only Pro capability advertisement. Never put passwords,
/// network SSIDs, transfer tokens, device identifiers or credentials here.
///
/// This data can only be interpreted after the calling client has pinned the
/// server certificate and the server has observed an mTLS client certificate.
/// An advertisement does not grant permission to join Wi-Fi or receive files.
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProCapabilitiesDto {
    pub schema_version: u16,
    pub pinned_tls_required: bool,
    pub resumable_upload: bool,
    pub hotspot_coordination: bool,
    pub network_bound_upload: bool,
    pub max_chunk_bytes: u32,
}

impl ProCapabilitiesDto {
    pub const SCHEMA_VERSION: u16 = 1;

    /// These features are intentionally disabled until a verified end-to-end
    /// implementation exists on both sender and receiver.
    pub fn current() -> Self {
        Self {
            schema_version: Self::SCHEMA_VERSION,
            pinned_tls_required: true,
            resumable_upload: false,
            hotspot_coordination: false,
            network_bound_upload: false,
            max_chunk_bytes: 0,
        }
    }

    /// Fail closed for unsupported schemas and untrusted network claims.
    pub fn is_safe_to_negotiate(&self) -> bool {
        self.schema_version == Self::SCHEMA_VERSION
            && self.pinned_tls_required
            && (!self.resumable_upload
                || (self.max_chunk_bytes > 0 && self.max_chunk_bytes <= 4 * 1024 * 1024))
            && (self.resumable_upload || self.max_chunk_bytes == 0)
    }
}

#[cfg(test)]
mod tests {
    use super::ProCapabilitiesDto;

    #[test]
    fn initial_advertisement_never_claims_unimplemented_live_transport() {
        let advertised = ProCapabilitiesDto::current();
        assert!(advertised.is_safe_to_negotiate());
        assert!(!advertised.resumable_upload);
        assert!(!advertised.hotspot_coordination);
        assert!(!advertised.network_bound_upload);
        assert_eq!(advertised.max_chunk_bytes, 0);
        let value = serde_json::to_value(&advertised).unwrap();
        assert_eq!(value["pinnedTlsRequired"], true);
        assert_eq!(value["resumableUpload"], false);
        assert_eq!(value["schemaVersion"], 1);
        let decoded = serde_json::from_value::<ProCapabilitiesDto>(value).unwrap();
        assert_eq!(decoded, advertised);
    }

    #[test]
    fn invalid_schema_or_unsafe_chunk_limits_are_rejected() {
        let mut caps = ProCapabilitiesDto::current();
        caps.schema_version = 2;
        assert!(!caps.is_safe_to_negotiate());
        caps.schema_version = 1;
        caps.pinned_tls_required = false;
        assert!(!caps.is_safe_to_negotiate());
        caps.pinned_tls_required = true;
        caps.resumable_upload = true;
        caps.max_chunk_bytes = 4 * 1024 * 1024 + 1;
        assert!(!caps.is_safe_to_negotiate());
        caps.max_chunk_bytes = 1024;
        assert!(caps.is_safe_to_negotiate());
    }
}
