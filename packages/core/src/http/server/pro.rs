use crate::http::pro::ProCapabilitiesDto;
use crate::http::server::common::response::JsonResponse;
use hyper::StatusCode;

/// The caller must have passed the mTLS gate in handle_request_inner.
/// This endpoint contains no hotspot credentials or file/session metadata.
pub(crate) fn capabilities() -> JsonResponse<ProCapabilitiesDto> {
    JsonResponse {
        status: StatusCode::OK,
        body: ProCapabilitiesDto::current(),
    }
}

/// A read-only feature advertisement is available only when the server's
/// LocalSend v2 mode is enabled AND TLS provided an actual client certificate.
/// This does not itself authorize file reception or hotspot association.
pub(crate) fn eligible(v2_enabled: bool, client_cert_present: bool) -> bool {
    v2_enabled && client_cert_present
}

#[cfg(test)]
mod tests {
    use super::eligible;

    #[test]
    fn capability_advertisement_is_not_exposed_over_plaintext_or_without_cert() {
        assert!(!eligible(false, false));
        assert!(!eligible(false, true));
        assert!(!eligible(true, false));
        assert!(eligible(true, true));
    }
}
