use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::Serialize;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ApiError {
    #[error("Unauthorized")]
    Unauthorized,

    #[error("Invalid pairing token")]
    InvalidToken,

    #[error("Bad request: {0}")]
    BadRequest(String),

    #[error("Payload too large: {0}")]
    TooLarge(String),

    #[error("Unsupported media type")]
    Unsupported,

    #[error("Rate limit exceeded")]
    RateLimited,

    #[error("Internal server error: {0}")]
    Internal(String),

    #[error("Not found: {0}")]
    NotFound(String),
}

#[derive(Serialize)]
struct ErrorBody {
    error: ErrorDetail,
}

#[derive(Serialize)]
struct ErrorDetail {
    code: &'static str,
    message: String,
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, code, message) = match self {
            ApiError::Unauthorized => (StatusCode::UNAUTHORIZED, "unauthorized", "Unauthorized".to_string()),
            ApiError::InvalidToken => (StatusCode::UNAUTHORIZED, "invalid_token", "Invalid or expired token".to_string()),
            ApiError::BadRequest(msg) => (StatusCode::BAD_REQUEST, "bad_request", msg),
            ApiError::TooLarge(msg) => (StatusCode::PAYLOAD_TOO_LARGE, "too_large", msg),
            ApiError::Unsupported => (StatusCode::UNSUPPORTED_MEDIA_TYPE, "unsupported", "Unsupported format".to_string()),
            ApiError::RateLimited => (StatusCode::TOO_MANY_REQUESTS, "rate_limited", "Rate limit exceeded".to_string()),
            ApiError::Internal(msg) => (StatusCode::INTERNAL_SERVER_ERROR, "internal", msg),
            ApiError::NotFound(msg) => (StatusCode::NOT_FOUND, "not_found", msg),
        };

        let body = Json(ErrorBody {
            error: ErrorDetail { code, message },
        });

        (status, body).into_response()
    }
}
