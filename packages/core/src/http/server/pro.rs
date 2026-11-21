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
